"""Tool bridge: runs the user's MCP servers and two web tools for the widget's chats over loopback HTTP.

QML can't keep a pipe to a process open, so this small server does: it starts
the MCP servers the widget lists (child processes or remote HTTP servers),
offers their tools to the widget and runs a tool when the widget says the user
approved the call.

Every request but /health needs `Authorization: Bearer <token>`. The port and
token are written to the state file given as the only argument (mode 0600);
the helper (tool_bridge.py) starts this script and reads them from there.

Routes:
  GET  /health
  POST /tools      {servers: {...mcpServers format...}, web: {search, searxngUrl, fetch}}
                   -> {tools: [{name, server, description, inputSchema}], errors: [{server, message}]}
                   Starts, restarts (changed definition) and stops servers to match; unchanged ones keep running.
  POST /call       {name, arguments} -> {output, isError}
  POST /shutdown

The bridge exits after SERVER_IDLE seconds without requests, stopping every MCP
process it started. Search keys are read from KWallet by this process, kept in
memory and never logged or returned. Stdlib only.
"""
import concurrent.futures
import hmac
import itertools
import json
import os
import re
import secrets
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Started with `python -I`: only this file's own folder is added, for the sibling modules.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schedule_wallet  # noqa: E402
import web_tools  # noqa: E402
from mcp_clients import HttpClient, McpError, StdioClient, format_result  # noqa: E402
from mcp_config import parse_servers  # noqa: E402
from pi_files import private_write  # noqa: E402

SERVER_IDLE = float(os.environ.get("KDEAICHAT_TOOL_SERVER_IDLE", 10 * 60))
MAX_BODY = 4 * 1024 * 1024
MAX_OUTPUT = 100000
SEARCH_SERVICES = ("none", "searxng", "brave", "tavily")

lock = threading.Lock()          # guards entries, registry, web_state, busy, last_activity
config_lock = threading.Lock()   # one /tools at a time
entries = {}                     # server name -> Entry
registry = {}                    # tool name -> (server name, the server's own tool name)
web_state = {"search": "none", "url": "", "key": "", "fetch": False}
busy = 0
last_activity = time.monotonic()
server = None


def log(message):
    print(time.strftime("%H:%M:%S"), message, file=sys.stderr, flush=True)


class Entry:
    def __init__(self, spec, client, tools):
        self.spec, self.client, self.tools = spec, client, tools
        self.restarts = 0
        self.lock = threading.Lock()


def connect(name, spec):
    """(client, tools) of a started and listed server, or McpError."""
    client = None
    try:
        client = StdioClient(name, spec, log) if spec["kind"] == "stdio" else HttpClient(name, spec)
        client.initialize()
        return client, client.list_tools()
    except McpError:
        if client:
            client.stop()
        raise
    except Exception as exc:  # noqa: BLE001  (a misbehaving server must not take the bridge down)
        if client:
            client.stop()
        raise McpError("the server answered in an unexpected way: " + type(exc).__name__) from None


def _stop(entry):
    try:
        entry.client.stop()
    except Exception:  # noqa: BLE001
        pass


def tool_name(server_name, tool, used):
    base = re.sub(r"[^a-zA-Z0-9_-]", "_", f"{server_name}__{tool}")[:64]
    name = base
    for n in itertools.count(2):
        if name not in used:
            return name
        suffix = f"_{n}"
        name = base[:64 - len(suffix)] + suffix


def _web_config(value):
    """{search, url, fetch} from the request's `web` object, with unknown values turned off."""
    value = value if isinstance(value, dict) else {}
    search = value.get("search") if value.get("search") in SEARCH_SERVICES else "none"
    url = value.get("searxngUrl") if isinstance(value.get("searxngUrl"), str) else ""
    return {"search": search, "url": url.strip()[:2048], "fetch": value.get("fetch") is True}


WEB_TOOLS = {
    "web_search": ("Search the web. Returns a numbered list of titles, links and snippets.",
                   {"type": "object", "properties": {"query": {"type": "string", "description": "What to search for"},
                                                     "count": {"type": "integer", "description": "How many results (1-10)", "default": 5}},
                    "required": ["query"]}),
    "fetch_url": ("Fetch a public web page or text file and return it as readable text.",
                  {"type": "object", "properties": {"url": {"type": "string", "description": "An http or https link"},
                                                    "max_chars": {"type": "integer", "description": "Longest text to return (default 50000)"}},
                   "required": ["url"]}),
}


def _search_key(provider):
    """(key, problem) for brave/tavily from the tools wallet folder; the key stays in memory."""
    try:
        key = schedule_wallet.read_key(provider, folder=schedule_wallet.tools_folder())
    except schedule_wallet.WalletUnavailable as exc:
        return "", f"The {provider} key can't be read ({exc.reason}). Unlock KWallet and try again."
    return (key, "") if key else ("", f"No {provider} key is saved: add it in the settings to use web search.")


def apply_config(body):
    servers, errors = parse_servers(body.get("servers"))
    web = _web_config(body.get("web"))
    with config_lock:
        with lock:
            current = dict(entries)
        for name, entry in current.items():
            if name not in servers or entry.spec != servers[name] or not entry.client.alive():
                with lock:
                    entries.pop(name, None)
                _stop(entry)
        with lock:
            todo = [name for name in servers if name not in entries]
        if todo:
            with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(todo))) as pool:
                futures = {name: pool.submit(connect, name, servers[name]) for name in todo}
            for name, future in futures.items():
                try:
                    client, tools = future.result()
                except McpError as exc:
                    errors.append({"server": name, "message": str(exc)})
                    continue
                with lock:
                    entries[name] = Entry(servers[name], client, tools)
                log(f"started {name} ({len(tools)} tools)")
        web_state.update({"search": "none", "url": "", "key": "", "fetch": web["fetch"]})
        if web["search"] == "searxng":
            if web["url"]:
                web_state.update({"search": "searxng", "url": web["url"]})
            else:
                errors.append({"server": "web", "message": "The SearXNG address is empty."})
        elif web["search"] in ("brave", "tavily"):
            key, problem = _search_key(web["search"])
            if key:
                web_state.update({"search": web["search"], "key": key})
            else:
                errors.append({"server": "web", "message": problem})
        tools, used, new_registry = [], set(), {}
        for tool, on in (("web_search", web_state["search"] != "none"), ("fetch_url", web_state["fetch"])):
            if on:
                used.add(tool)
                new_registry[tool] = ("web", tool)
                tools.append({"name": tool, "server": "web", "description": WEB_TOOLS[tool][0], "inputSchema": WEB_TOOLS[tool][1]})
        for name in servers:
            entry = entries.get(name)
            for tool in (entry.tools if entry else []):
                exposed = tool_name(name, tool["name"], used)
                used.add(exposed)
                new_registry[exposed] = (name, tool["name"])
                schema = tool.get("inputSchema")
                tools.append({"name": exposed, "server": name, "description": str(tool.get("description") or tool.get("title") or "")[:2000],
                              "inputSchema": schema if isinstance(schema, dict) else {"type": "object", "properties": {}}})
        with lock:
            registry.clear()
            registry.update(new_registry)
    return {"tools": tools, "errors": errors}


def _cap(text):
    if len(text) <= MAX_OUTPUT:
        return text
    return text[:MAX_OUTPUT] + f"\n\n[output truncated: {len(text) - MAX_OUTPUT} more characters]"


def _web_call(tool, arguments):
    with lock:
        state = dict(web_state)
    if tool == "web_search":
        return web_tools.web_search(state["search"], arguments.get("query"), arguments.get("count", 5), state["url"], state["key"])
    return web_tools.fetch_url(arguments.get("url"), arguments.get("max_chars"))


def _ensure_alive(entry, name):
    with entry.lock:
        if entry.client.alive():
            return
        if entry.restarts >= 1:
            raise McpError("the server stopped again; it will be started again when the tools are reloaded")
        entry.restarts += 1
        log(f"restarting {name}")
        entry.client.stop()
        entry.client, entry.tools = connect(name, entry.spec)


def call_tool(name, arguments):
    with lock:
        target = registry.get(name)
        entry = entries.get(target[0]) if target else None
    if not target:
        return 404, {"output": "Unknown tool: " + str(name)[:100], "isError": True}
    if target[0] == "web":
        text, is_error = _web_call(target[1], arguments)
        return 200, {"output": _cap(text), "isError": is_error}
    if entry is None:
        return 404, {"output": "That tool's server is not running.", "isError": True}
    try:
        _ensure_alive(entry, target[0])
        text, is_error = format_result(entry.client.call(target[1], arguments))
    except McpError as exc:
        return 200, {"output": "The tool call failed: " + str(exc), "isError": True}
    return 200, {"output": _cap(text), "isError": is_error}


class Handler(BaseHTTPRequestHandler):
    token = ""

    def log_message(self, *args):
        pass

    def _reply(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorised(self):
        given = self.headers.get("Authorization", "")
        if hmac.compare_digest(given.encode(), ("Bearer " + self.token).encode()):
            return True
        self._reply(401, {"error": "unauthorised"})
        return False

    def do_GET(self):
        if self.path == "/health":
            return self._reply(200, {"ok": True})
        if not self._authorised():
            return
        self._reply(404 if self.path not in ("/tools", "/call", "/shutdown") else 405, {"error": "not found or use POST"})

    def do_POST(self):
        global busy, last_activity
        if not self._authorised():
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = -1
        if length < 0 or length > MAX_BODY:
            return self._reply(413, {"error": "request too large"})
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return self._reply(400, {"error": "invalid JSON"})
        if not isinstance(payload, dict):
            return self._reply(400, {"error": "expected an object"})
        if self.path == "/shutdown":
            self._reply(200, {"ok": True})
            threading.Thread(target=shutdown, daemon=True).start()
            return
        if self.path not in ("/tools", "/call"):
            return self._reply(404, {"error": "not found"})
        with lock:
            busy += 1
            last_activity = time.monotonic()
        try:
            if self.path == "/tools":
                return self._reply(200, apply_config(payload))
            arguments = payload.get("arguments")
            return self._reply(*call_tool(payload.get("name"), arguments if isinstance(arguments, dict) else {}))
        except Exception as exc:  # noqa: BLE001
            log("request failed: " + type(exc).__name__)
            return self._reply(500, {"error": "internal error", "output": "The tool bridge failed.", "isError": True})
        finally:
            with lock:
                busy -= 1
                last_activity = time.monotonic()


def shutdown(only_if_idle=False):
    with lock:
        if only_if_idle and (busy or time.monotonic() - last_activity <= SERVER_IDLE):
            return False  # a request arrived since the janitor looked
        running = list(entries.values())
        entries.clear()
        registry.clear()
    for entry in running:
        _stop(entry)
    server.shutdown()
    return True


def janitor():
    while True:
        time.sleep(min(30, max(0.2, SERVER_IDLE / 4)))
        if shutdown(only_if_idle=True):
            return


def write_state(path, port, token):
    private_write(path, json.dumps({"pid": os.getpid(), "port": port, "token": token, "argv": [sys.executable] + sys.argv}))


def main():
    global server
    state_path = sys.argv[1]
    Handler.token = secrets.token_urlsafe(32)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    write_state(state_path, server.server_address[1], Handler.token)
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=shutdown, daemon=True).start())
    threading.Thread(target=janitor, daemon=True).start()
    try:
        server.serve_forever()
    finally:
        try:
            with open(state_path, encoding="utf-8") as f:
                if json.load(f).get("pid") == os.getpid():
                    os.unlink(state_path)
        except (OSError, ValueError):
            pass


if __name__ == "__main__":
    main()
