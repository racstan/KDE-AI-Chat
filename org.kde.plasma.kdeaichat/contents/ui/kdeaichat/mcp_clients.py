"""MCP clients for the MCP bridge: stdio (a child process) and Streamable HTTP.

Both speak JSON-RPC 2.0: `initialize`, `notifications/initialized`,
`tools/list` (following nextCursor) and `tools/call`. Server definitions
(env, headers) can hold secrets: they are used here and never logged. Stdlib only.
"""
import collections
import json
import os
import signal
import subprocess
import threading
import urllib.error
import urllib.request

PROTOCOL = "2025-06-18"
CLIENT_INFO = {"name": "kdeaichat", "version": "1.5"}
INIT_TIMEOUT = 20.0


class McpError(Exception):
    pass


def _init_params():
    return {"protocolVersion": PROTOCOL, "capabilities": {}, "clientInfo": CLIENT_INFO}


def _result(message):
    if message.get("error"):
        err = message["error"]
        raise McpError(str(err.get("message", err)) if isinstance(err, dict) else str(err))
    return message.get("result") or {}


class Client:
    """Shared logic; subclasses implement _ensure() and _rpc()."""

    def __init__(self, definition):
        self.definition = definition
        self.id_lock = threading.Lock()
        self.next_id = 0

    def _new_id(self):
        with self.id_lock:
            self.next_id += 1
            return self.next_id

    def list_tools(self, timeout=30.0):
        tools, cursor = [], None
        for _ in range(100):
            result = self.request("tools/list", {"cursor": cursor} if cursor else {}, timeout)
            for t in result.get("tools") or []:
                tools.append({"name": t.get("name", ""), "description": t.get("description", ""),
                              "inputSchema": t.get("inputSchema") or {"type": "object"}})
            cursor = result.get("nextCursor")
            if not cursor:
                break
        return tools

    def call(self, tool, arguments, timeout=60.0):
        return self.request("tools/call", {"name": tool, "arguments": arguments or {}}, timeout)

    def request(self, method, params, timeout):
        self._ensure()
        return self._rpc(method, params, timeout)

    def close(self):
        pass


class StdioClient(Client):
    def __init__(self, definition):
        super().__init__(definition)
        self.proc = None
        self.pending = {}
        self.stderr_tail = collections.deque(maxlen=20)
        self.start_lock = threading.Lock()
        self.write_lock = threading.Lock()  # concurrent calls must not interleave their lines

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def _ensure(self):
        with self.start_lock:
            if self.alive():
                return
            self.close()
            self._spawn()
            try:
                self._rpc("initialize", _init_params(), INIT_TIMEOUT)
                self._write({"jsonrpc": "2.0", "method": "notifications/initialized"})
            except Exception:
                self.close()
                raise

    def _spawn(self):
        d = self.definition
        env = os.environ.copy()
        env.update({str(k): str(v) for k, v in (d.get("env") or {}).items()})
        cwd = d.get("cwd") or os.path.expanduser("~")
        try:
            self.proc = subprocess.Popen([d["command"]] + [str(a) for a in d.get("args") or []], cwd=cwd, env=env,
                                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                         start_new_session=True, close_fds=True)
        except OSError as e:
            raise McpError(f"Couldn't start {d['command']}: {e.strerror or e}")
        self.pending = {}
        threading.Thread(target=self._read_stdout, args=(self.proc, self.pending, self._answer_request), daemon=True).start()
        threading.Thread(target=self._read_stderr, args=(self.proc,), daemon=True).start()

    def _answer_request(self, message):
        """A request from the server: `ping` gets an empty result, anything else "method not found"."""
        if message.get("method") == "ping":
            reply = {"jsonrpc": "2.0", "id": message["id"], "result": {}}
        else:
            reply = {"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": "Method not found"}}
        try:
            self._write(reply)
        except McpError:
            pass

    @staticmethod
    def _read_stdout(proc, pending, on_request=None):
        for raw in proc.stdout:
            try:
                message = json.loads(raw)
            except ValueError:
                continue
            if isinstance(message, dict) and message.get("id") is not None and "method" in message:
                if on_request:
                    on_request(message)
                continue
            if isinstance(message, dict) and "id" in message and "method" not in message:
                slot = pending.get(message["id"])
                if slot:
                    slot[1] = message
                    slot[0].set()
        for slot in list(pending.values()):  # process ended: wake waiters
            slot[0].set()

    def _read_stderr(self, proc):
        for raw in proc.stderr:
            self.stderr_tail.append(raw.decode("utf-8", "replace").rstrip()[:300])

    def _write(self, message):
        data = (json.dumps(message, separators=(",", ":")) + "\n").encode("utf-8")
        try:
            with self.write_lock:
                self.proc.stdin.write(data)
                self.proc.stdin.flush()
        except (OSError, ValueError, AttributeError):
            raise McpError("The MCP server's process ended.")

    def _rpc(self, method, params, timeout):
        rid = self._new_id()
        slot = [threading.Event(), None]
        pending = self.pending
        pending[rid] = slot
        try:
            self._write({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
            if not slot[0].wait(timeout):
                raise McpError(f"The MCP server didn't answer {method} within {timeout:g} s.")
        finally:
            pending.pop(rid, None)
        if slot[1] is None:
            tail = self.stderr_tail[-1] if self.stderr_tail else ""
            raise McpError("The MCP server's process ended." + (f" Last message: {tail}" if tail else ""))
        return _result(slot[1])

    def close(self):
        proc, self.proc = self.proc, None
        if not proc:
            return
        if proc.poll() is None:
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(proc.pid, sig)
                    proc.wait(timeout=2)
                    break
                except subprocess.TimeoutExpired:
                    continue
                except OSError:
                    break
        for stream in (proc.stdin, proc.stdout, proc.stderr):
            try:
                stream.close()
            except (OSError, ValueError):
                pass


class HttpClient(Client):
    def __init__(self, definition):
        super().__init__(definition)
        self.session = ""
        self.ready = False
        self.init_lock = threading.Lock()

    def _ensure(self):
        with self.init_lock:
            if self.ready:
                return
            self._rpc("initialize", _init_params(), INIT_TIMEOUT)
            self._post({"jsonrpc": "2.0", "method": "notifications/initialized"}, INIT_TIMEOUT, None)
            self.ready = True

    def _post(self, message, timeout, rid):
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                   "MCP-Protocol-Version": PROTOCOL}
        headers.update({str(k): str(v) for k, v in (self.definition.get("headers") or {}).items()})
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        req = urllib.request.Request(self.definition["url"], data=json.dumps(message).encode(), headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as response:
                self.session = response.headers.get("Mcp-Session-Id") or self.session
                if rid is None:
                    return None
                if "text/event-stream" in (response.headers.get("Content-Type") or ""):
                    return _read_sse(response, rid)
                body = response.read(64 * 1024 * 1024)
                return _match(json.loads(body) if body.strip() else None, rid)
        except urllib.error.HTTPError as e:
            if e.code == 404 and self.session:
                self.session, self.ready = "", False  # session expired: the next request starts a new one
            raise McpError(f"The MCP server answered HTTP {e.code}.")
        except (urllib.error.URLError, OSError) as e:
            reason = getattr(e, "reason", e)
            if "timed out" in str(reason):
                raise McpError(f"The MCP server didn't answer within {timeout:g} s.")
            raise McpError(f"Couldn't reach the MCP server: {reason}")
        except ValueError:
            raise McpError("The MCP server sent something that isn't JSON.")

    def _rpc(self, method, params, timeout):
        rid = self._new_id()
        message = self._post({"jsonrpc": "2.0", "id": rid, "method": method, "params": params}, timeout, rid)
        if message is None:
            raise McpError("The MCP server sent no answer.")
        return _result(message)

    def close(self):
        self.ready, self.session = False, ""


def _match(body, rid):
    for item in body if isinstance(body, list) else [body]:
        if isinstance(item, dict) and item.get("id") == rid and "method" not in item:
            return item
    return None


def _read_sse(response, rid):
    data = []
    for raw in response:
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        if line.startswith("data:"):
            data.append(line[5:].lstrip(" "))
        elif not line and data:
            try:
                found = _match(json.loads("\n".join(data)), rid)
            except ValueError:
                found = None
            data = []
            if found:
                return found
    if data:
        try:
            return _match(json.loads("\n".join(data)), rid)
        except ValueError:
            pass
    return None


def make_client(definition):
    return HttpClient(definition) if definition.get("url") else StdioClient(definition)
