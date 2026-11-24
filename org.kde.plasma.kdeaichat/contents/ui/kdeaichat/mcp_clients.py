"""MCP clients for the tool bridge: a stdio server (a child process) and a remote
Streamable HTTP server. stdlib only; imported by tool_bridge_server.py by plain name.

Both speak JSON-RPC 2.0 and offer the same few methods: initialize(), list_tools(),
call(tool, arguments), alive() and stop(). Failures raise McpError with a short
message for the user.
"""
import collections
import json
import os
import re
import signal
import subprocess
import threading
import time
import urllib.error
import urllib.request
from typing import Any, Callable, Dict, List

import http_safe

PROTOCOL = "2025-06-18"
CLIENT_VERSION = "1.0"
INIT_TIMEOUT = float(os.environ.get("KDEAICHAT_TOOL_INIT_TIMEOUT", 30))
CALL_TIMEOUT = float(os.environ.get("KDEAICHAT_TOOL_CALL_TIMEOUT", 120))
MAX_TOOLS = 200
MAX_STDERR_LOG = 64 * 1024
MAX_RESPONSE = 32 * 1024 * 1024


class McpError(Exception):
    pass


def tool_env() -> Dict[str, str]:
    env = os.environ.copy()
    extra = [os.path.expanduser(p) for p in ("~/.npm-global/bin", "~/.local/bin", "~/bin")]
    env["PATH"] = os.pathsep.join([env.get("PATH", "")] + extra)
    return env


class _Client:
    name = ""

    def request(self, method: str, params: Dict[str, Any], timeout: float) -> Dict[str, Any]:
        raise NotImplementedError

    def notify(self, method: str, params: Dict[str, Any]) -> None:
        raise NotImplementedError

    def alive(self) -> bool:
        return True

    def stop(self) -> None:
        pass

    def initialize(self) -> None:
        result = self.request("initialize", {"protocolVersion": PROTOCOL, "capabilities": {},
                                             "clientInfo": {"name": "kde-ai-chat", "version": CLIENT_VERSION}}, INIT_TIMEOUT)
        self.protocol = str(result.get("protocolVersion") or PROTOCOL)
        self.notify("notifications/initialized", {})

    def list_tools(self) -> List[Dict[str, Any]]:
        tools: List[Dict[str, Any]] = []
        cursor = ""
        for _ in range(MAX_TOOLS):  # pages hold at least one tool or we stop
            result = self.request("tools/list", {"cursor": cursor} if cursor else {}, INIT_TIMEOUT)
            tools += [t for t in result.get("tools") or [] if isinstance(t, dict) and isinstance(t.get("name"), str) and t["name"]]
            cursor = result.get("nextCursor") if isinstance(result.get("nextCursor"), str) else ""
            if not cursor or len(tools) >= MAX_TOOLS:
                break
        return tools[:MAX_TOOLS]

    def call(self, tool: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        return self.request("tools/call", {"name": tool, "arguments": arguments}, CALL_TIMEOUT)

    protocol = PROTOCOL


class StdioClient(_Client):
    """A child process speaking newline-delimited JSON-RPC on stdin/stdout."""

    def __init__(self, name: str, spec: Dict[str, Any], log: Callable[[str], None]):
        self.name = name
        self._log = log
        self._lock = threading.Lock()
        self._write_lock = threading.Lock()
        self._pending: Dict[int, Dict[str, Any]] = {}
        self._next = 0
        self._closed = False
        self.stderr_tail: collections.deque = collections.deque(maxlen=20)
        env = tool_env()
        env.update(spec.get("env") or {})
        cwd = spec.get("cwd") or os.path.expanduser("~")
        if not os.path.isdir(cwd):
            raise McpError("the working folder doesn't exist: " + cwd)
        command = spec["command"]
        try:
            self.proc = subprocess.Popen([command] + list(spec.get("args") or []), cwd=cwd, env=env, stdin=subprocess.PIPE,
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, close_fds=True)
        except FileNotFoundError:
            raise McpError("the command wasn't found: " + command) from None
        except OSError as exc:
            raise McpError("the command couldn't start: " + str(exc.strerror or exc)) from None
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def _send(self, message: Dict[str, Any]) -> None:
        data = (json.dumps(message, separators=(",", ":")) + "\n").encode("utf-8")
        with self._write_lock:
            self.proc.stdin.write(data)  # type: ignore[union-attr]
            self.proc.stdin.flush()  # type: ignore[union-attr]

    def _read_stdout(self) -> None:
        for raw in self.proc.stdout:  # type: ignore[union-attr]
            try:
                message = json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                continue
            if not isinstance(message, dict):
                continue
            if "method" in message:
                if "id" in message:  # a request from the server: we offer nothing
                    try:
                        self._send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32601, "message": "Method not found"}})
                    except (OSError, ValueError):
                        pass
                continue
            with self._lock:
                slot = self._pending.pop(message.get("id"), None)  # type: ignore[arg-type]
            if slot:
                slot["message"] = message
                slot["event"].set()
        self._closed = True
        with self._lock:
            slots, self._pending = list(self._pending.values()), {}
        for slot in slots:
            slot["message"] = {"error": {"message": "the server stopped" + self._tail()}}
            slot["event"].set()

    def _tail(self) -> str:
        return (": " + " | ".join(list(self.stderr_tail)[-3:])[:300]) if self.stderr_tail else ""

    def _read_stderr(self) -> None:
        logged = 0
        for raw in self.proc.stderr:  # type: ignore[union-attr]
            line = raw.decode("utf-8", "replace").rstrip()
            self.stderr_tail.append(line[:200])
            if logged < MAX_STDERR_LOG:
                logged += len(raw)
                self._log(f"[{self.name}] {line[:500]}")

    def request(self, method: str, params: Dict[str, Any], timeout: float) -> Dict[str, Any]:
        slot: Dict[str, Any] = {"event": threading.Event()}
        with self._lock:
            self._next += 1
            rid = self._next
            self._pending[rid] = slot
        try:
            self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        except (OSError, ValueError):
            with self._lock:
                self._pending.pop(rid, None)
            raise McpError("the server isn't running" + self._tail()) from None
        if not slot["event"].wait(timeout):
            with self._lock:
                self._pending.pop(rid, None)
            raise McpError(f"{method} timed out after {timeout:g} s")
        error = slot["message"].get("error")
        if error is not None:
            raise McpError(str(error.get("message") if isinstance(error, dict) else error)[:500])
        result = slot["message"].get("result")
        return result if isinstance(result, dict) else {}

    def notify(self, method: str, params: Dict[str, Any]) -> None:
        try:
            self._send({"jsonrpc": "2.0", "method": method, "params": params})
        except (OSError, ValueError):
            raise McpError("the server isn't running" + self._tail()) from None

    def alive(self) -> bool:
        return self.proc.poll() is None

    def stop(self) -> None:
        try:
            self.proc.stdin.close()  # type: ignore[union-attr]
        except OSError:
            pass
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
            self.proc.wait(timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
                self.proc.wait(timeout=3)
            except (OSError, subprocess.TimeoutExpired):
                pass


class HttpClient(_Client):
    """A remote MCP server over Streamable HTTP (a JSON answer or an SSE stream per POST)."""

    def __init__(self, name: str, spec: Dict[str, Any]):
        self.name = name
        self.url = spec["url"]
        self.headers = dict(spec.get("headers") or {})
        self.session = ""
        self._lock = threading.Lock()
        self._next = 0
        self._ok = True

    def _post(self, message: Dict[str, Any], rid: Any, timeout: float) -> Dict[str, Any]:
        headers = dict(self.headers)
        headers.update({"Content-Type": "application/json", "Accept": "application/json, text/event-stream"})
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        if rid is not None and message.get("method") != "initialize":
            headers["MCP-Protocol-Version"] = self.protocol
        request = urllib.request.Request(self.url, data=json.dumps(message).encode("utf-8"), headers=headers, method="POST")
        deadline = time.monotonic() + timeout
        try:
            with http_safe.urlopen(request, timeout=timeout) as response:
                self.session = response.headers.get("Mcp-Session-Id") or self.session
                if rid is None:
                    response.read(65536)
                    return {}
                if "text/event-stream" in (response.headers.get("Content-Type") or "").lower():
                    return _from_events(response, rid, deadline)
                return _from_body(response.read(MAX_RESPONSE + 1), rid)
        except urllib.error.HTTPError as exc:
            if exc.code == 404 and self.session:
                self.session = ""
                raise McpError("the server ended the session (HTTP 404)") from None
            raise McpError(f"the server answered HTTP {exc.code}" + (" (check the headers or key)" if exc.code in (401, 403) else "")) from None
        except (OSError, ValueError) as exc:
            raise McpError("couldn't reach the server: " + str(getattr(exc, "reason", exc))[:200]) from None

    def request(self, method: str, params: Dict[str, Any], timeout: float) -> Dict[str, Any]:
        with self._lock:
            self._next += 1
            rid = self._next
        message = self._post({"jsonrpc": "2.0", "id": rid, "method": method, "params": params}, rid, timeout)
        if message.get("error") is not None:
            error = message["error"]
            raise McpError(str(error.get("message") if isinstance(error, dict) else error)[:500])
        result = message.get("result")
        return result if isinstance(result, dict) else {}

    def notify(self, method: str, params: Dict[str, Any]) -> None:
        self._post({"jsonrpc": "2.0", "method": method, "params": params}, None, INIT_TIMEOUT)

    def stop(self) -> None:
        if not self.session:
            return
        try:
            request = urllib.request.Request(self.url, method="DELETE", headers=dict(self.headers, **{"Mcp-Session-Id": self.session}))
            http_safe.urlopen(request, timeout=2).close()
        except (OSError, ValueError):
            pass


def _pick(message: Any, rid: Any) -> Dict[str, Any]:
    """``message`` if it is the response to request ``rid`` (else {})."""
    if isinstance(message, dict) and message.get("id") == rid and ("result" in message or "error" in message):
        return message
    return {}


def _from_body(data: bytes, rid: Any) -> Dict[str, Any]:
    if len(data) > MAX_RESPONSE:
        raise McpError("the answer is too large")
    try:
        body = json.loads(data.decode("utf-8", "replace"))
    except ValueError:
        raise McpError("the server's answer isn't JSON") from None
    for message in body if isinstance(body, list) else [body]:
        if _pick(message, rid):
            return message
    raise McpError("the server's answer has no response to the request")


def _from_events(response: Any, rid: Any, deadline: float) -> Dict[str, Any]:
    data: List[str] = []
    total = 0
    for raw in response:
        if time.monotonic() > deadline:
            raise McpError("the answer timed out")
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        total += len(line)
        if total > MAX_RESPONSE:
            raise McpError("the answer is too large")
        if line.startswith("data:"):
            data.append(line[5:].lstrip(" "))
        elif not line and data:
            try:
                found = _pick(json.loads("\n".join(data)), rid)
            except ValueError:
                found = {}
            data = []
            if found:
                return found
    raise McpError("the stream ended without a response")


def format_result(result: Dict[str, Any]) -> "tuple[str, bool]":
    """(text, isError) for a tools/call result."""
    parts: List[str] = []
    has_text = False
    for item in result.get("content") or []:
        if not isinstance(item, dict):
            continue
        kind = item.get("type")
        if kind == "text":
            has_text = True
            parts.append(str(item.get("text", "")))
        elif kind in ("image", "audio"):
            size = max(1, round(len(str(item.get("data", ""))) * 3 / 4 / 1024))
            parts.append(f"[{kind}: {item.get('mimeType') or 'unknown type'}, {size} KB]")
        elif kind == "resource":
            resource = item.get("resource") if isinstance(item.get("resource"), dict) else {}
            if isinstance(resource.get("text"), str):
                has_text = True
                parts.append(resource["text"])
                continue
            parts.append(f"[resource: {resource.get('uri') or 'unnamed'}, {resource.get('mimeType') or 'unknown type'}]")
        elif kind == "resource_link":
            parts.append(f"[resource: {item.get('uri') or 'unnamed'}, {item.get('mimeType') or 'unknown type'}]")
    if not has_text and result.get("structuredContent") is not None:
        parts.append(json.dumps(result["structuredContent"], ensure_ascii=False))
    return "\n".join(parts), result.get("isError") is True


SERVER_NAME = re.compile(r"[A-Za-z0-9._-]{1,64}")
HEADER_NAME = re.compile(r"[A-Za-z0-9!#$%&'*+.^_`|~-]{1,128}")
