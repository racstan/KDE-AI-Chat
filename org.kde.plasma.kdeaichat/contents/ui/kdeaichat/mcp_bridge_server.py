"""MCP bridge: keeps the user's MCP servers running for the widget behind token-protected loopback HTTP.

QML can't keep a pipe to a process open, so this small server does: one child
process per stdio server, a session per URL server. It runs only what the
request bodies name; definitions (and the secrets in their env/headers) arrive
in request bodies, never argv, and are never logged.

Every request but GET /health needs `Authorization: Bearer <token>`. Port and
token go to the state file given as the only argument (mode 0600).

Routes (a server definition is {id, command, args, env, cwd} or {id, url, headers}):
  GET  /health
  POST /tools   {servers: [def, ...]} -> {servers: {id: {tools: [{name, description, inputSchema}]} | {error}}}
  POST /call    {server: def, tool, arguments, timeout?} -> {content: text, isError}
  POST /stop    stops every server process (the bridge keeps running until idle)

The bridge exits after SERVER_IDLE seconds without requests. Stdlib only.
"""
import hashlib
import hmac
import json
import os
import secrets
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # started with -I
from mcp_clients import McpError, make_client  # noqa: E402
from pi_files import private_write  # noqa: E402

SERVER_IDLE = float(os.environ.get("KDEAICHAT_MCP_SERVER_IDLE", 10 * 60))
MAX_BODY = 8 * 1024 * 1024
MAX_TEXT = 32 * 1024
LIST_TIMEOUT = 30.0
CALL_TIMEOUT = 60.0

lock = threading.Lock()
clients = {}  # server id -> (fingerprint, Client)
last_activity = time.monotonic()
server = None


def fingerprint(definition):
    return hashlib.sha256(json.dumps(definition, sort_keys=True).encode()).hexdigest()


def validate(definition):
    if not isinstance(definition, dict) or not str(definition.get("id") or ""):
        raise McpError("A server needs an id.")
    if not (definition.get("command") or definition.get("url")):
        raise McpError("A server needs a command or a url.")
    for key in ("env", "headers"):
        values = definition.get(key) or {}
        if not isinstance(values, dict) or not all(isinstance(v, (str, int, float)) for v in values.values()):
            raise McpError(f"{key} must hold plain values.")
    return definition


def client_for(definition):
    """The running client for this definition; a changed definition replaces (and stops) the old one."""
    validate(definition)
    sid, fp = str(definition["id"]), fingerprint(definition)
    with lock:
        held = clients.get(sid)
        if held and held[0] == fp:
            return held[1]
        stale = held[1] if held else None
        client = make_client(definition)
        clients[sid] = (fp, client)
    if stale:
        stale.close()
    return client


def flatten(result):
    """MCP tool result -> (text, isError): text joined, other items described in one line, cut at MAX_TEXT bytes."""
    parts = []
    for item in result.get("content") or []:
        kind = item.get("type") if isinstance(item, dict) else None
        if kind == "text":
            parts.append(str(item.get("text", "")))
        elif kind in ("image", "audio"):
            size = len(item.get("data") or "") * 3 // 4
            parts.append(f"[{kind}: {item.get('mimeType', 'unknown type')}, about {size} bytes, not shown]")
        elif kind == "resource":
            res = item.get("resource") or {}
            parts.append(" ".join(f"[resource: {res.get('uri', '')} {res.get('mimeType', '')}, not shown]".split()))
        elif kind == "resource_link":
            parts.append(f"[resource link: {item.get('uri', '')}]")
        else:
            parts.append(f"[{kind or 'unknown'} content, not shown]")
    text = "\n".join(parts)
    if not parts and result.get("structuredContent") is not None:
        text = json.dumps(result["structuredContent"])
    raw = text.encode("utf-8")
    if len(raw) > MAX_TEXT:
        text = raw[:MAX_TEXT].decode("utf-8", "ignore") + f"\n[cut: the result was {len(raw)} bytes, showing the first {MAX_TEXT}]"
    return text, bool(result.get("isError"))


def do_tools(body):
    out = {}
    for definition in body.get("servers") or []:
        sid = str(definition.get("id", "")) if isinstance(definition, dict) else ""
        try:
            out[sid] = {"tools": client_for(definition).list_tools(LIST_TIMEOUT)}
        except McpError as e:
            out[sid] = {"error": str(e)}
    return {"servers": out}


def do_call(body):
    tool = body.get("tool")
    if not isinstance(tool, str) or not tool:
        return 400, {"error": "tool is required"}
    arguments = body.get("arguments") or {}
    if not isinstance(arguments, dict):
        return 400, {"error": "arguments must be an object"}
    try:
        timeout = min(600.0, max(0.1, float(body.get("timeout") or CALL_TIMEOUT)))
        text, is_error = flatten(client_for(body.get("server")).call(tool, arguments, timeout))
        return 200, {"content": text, "isError": is_error}
    except (McpError, ValueError) as e:
        return 200, {"content": str(e), "isError": True}


def stop_all():
    with lock:
        held = list(clients.values())
        clients.clear()
    for _, client in held:
        client.close()


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
        self._reply(404, {"error": "not found"})

    def do_POST(self):
        global last_activity
        if not self._authorised():
            return
        last_activity = time.monotonic()
        try:
            length = int(self.headers.get("Content-Length") or 0)
            if length > MAX_BODY:
                return self._reply(413, {"error": "too large"})
            body = json.loads(self.rfile.read(length) or b"{}")
            if not isinstance(body, dict):
                raise ValueError
        except ValueError:
            return self._reply(400, {"error": "bad request"})
        path = self.path.split("?", 1)[0]
        if path == "/tools":
            self._reply(200, do_tools(body))
        elif path == "/call":
            self._reply(*do_call(body))
        elif path == "/stop":
            stop_all()
            self._reply(200, {"ok": True})
        else:
            self._reply(404, {"error": "not found"})
        last_activity = time.monotonic()


def shutdown():
    stop_all()
    server.shutdown()


def janitor():
    while True:
        time.sleep(min(30, max(0.5, SERVER_IDLE / 4)))
        if time.monotonic() - last_activity > SERVER_IDLE:
            shutdown()
            return


def main():
    global server
    state_path = sys.argv[1]
    Handler.token = secrets.token_urlsafe(32)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    private_write(state_path, json.dumps({"pid": os.getpid(), "port": server.server_address[1], "token": Handler.token,
                                          "argv": [sys.executable] + sys.argv}))
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=shutdown, daemon=True).start())
    threading.Thread(target=janitor, daemon=True).start()
    try:
        server.serve_forever()
    finally:
        stop_all()
        try:
            with open(state_path, encoding="utf-8") as f:
                if json.load(f).get("pid") == os.getpid():
                    os.unlink(state_path)
        except (OSError, ValueError):
            pass


if __name__ == "__main__":
    main()
