"""An OpenCode-mode scheduled run, over the same server API the widget uses.

The prompt goes to the chat's own OpenCode session (a new one if the chat has
none yet; the widget then stores its id) in the chat's folder, with the
chat's provider/model/agent/variant, through ``POST /session/:id/message``,
which answers once the reply is complete (backends/OpenCodeBackend.js uses
the async route plus the event stream; the result is the same).

The server: the one configured in Settings (openCodeUrl) if it answers.
Otherwise, for a local URL, a temporary ``opencode serve`` on a free
loopback port is started for this run and stopped afterwards, so nothing
keeps running between schedules. Nobody can answer permission requests or
questions: while the prompt runs, the event stream is watched and each one
for this session is rejected, and the reply says so.
"""
import json
import os
import secrets
import signal
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional

from kdeaichat import opencode_server
from kdeaichat.schedule_direct import RunError


def base_url(config: Dict[str, Any]) -> str:
    raw = str(config.get("openCodeUrl") or "http://127.0.0.1:4096/v1").strip()
    if not raw.lower().startswith(("http://", "https://")):
        raise RunError("OpenCode: the server URL in Settings is not an http(s) URL.")
    base = raw.rstrip("/")
    return base[:-3] if base.endswith("/v1") else base


def _url(base: str, path: str, directory: str) -> str:
    return base + path + (("&" if "?" in path else "?") + "directory=" + urllib.parse.quote(directory, safe="") if directory else "")


_TEMP_AUTH: Dict[int, str] = {}  # port -> Authorization of a temporary server this run started


def _headers(url: str, extra: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    """Request headers; a local server with a password (the widget's, or this run's own) gets its credentials."""
    headers = dict(extra or {})
    parts = urllib.parse.urlparse(url)
    if parts.hostname in ("127.0.0.1", "localhost", "::1") and parts.port:
        auth = _TEMP_AUTH.get(parts.port) or opencode_server.auth_for_port(parts.port)
        if auth:
            headers["Authorization"] = auth
    return headers


def _request(method: str, url: str, body: Optional[Dict[str, Any]] = None, timeout: float = 15) -> Any:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=_headers(url, {"Content-Type": "application/json"}))
    with urllib.request.urlopen(req, timeout=timeout) as response:
        text = response.read(50_000_000).decode("utf-8", "replace")
    return json.loads(text) if text.strip() else None


def _healthy(base: str) -> bool:
    try:
        with urllib.request.urlopen(urllib.request.Request(base + "/global/health", headers=_headers(base)), timeout=2) as response:
            return 200 <= response.status < 300
    except OSError:
        return False


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Server:
    """The configured server, or a temporary one for this run (stopped by close())."""

    def __init__(self, base: str, directory: str):
        self.process: Optional[subprocess.Popen] = None
        self.base = base
        if _healthy(base):
            return
        host = urllib.parse.urlparse(base).hostname or ""
        if host not in ("127.0.0.1", "localhost", "::1"):
            raise RunError(f"OpenCode isn't reachable at {base}.")
        binary = opencode_server.find_binary()
        if not binary:
            raise RunError("OpenCode isn't installed (no `opencode` command found).")
        port = _free_port()
        cwd = directory if directory and os.path.isdir(directory) else os.path.expanduser("~")
        password = secrets.token_urlsafe(32)  # this run's own server: only we know it (environment, never argv)
        _TEMP_AUTH[port] = opencode_server.authorization(password)
        env = dict(os.environ, OPENCODE_SERVER_PASSWORD=password)
        env.pop("OPENCODE_SERVER_USERNAME", None)
        self.process = subprocess.Popen([binary, "serve", "--port", str(port), "--hostname", "127.0.0.1"], cwd=cwd,
                                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                        start_new_session=True, close_fds=True, env=env)
        self.base = f"http://127.0.0.1:{port}"
        deadline = time.time() + 30
        while time.time() < deadline:
            if self.process.poll() is not None:
                break
            if _healthy(self.base):
                return
            time.sleep(0.3)
        self.close()
        raise RunError("OpenCode didn't start for the scheduled run.")

    def close(self) -> None:
        if self.process and self.process.poll() is None:
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
                self.process.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                try:
                    os.killpg(self.process.pid, signal.SIGKILL)
                except OSError:
                    pass


def _answer(base: str, directory: str, event: Any, session_id: str, notes: List[str]) -> None:
    props = (event.get("properties") or {}) if isinstance(event, dict) else {}
    if props.get("sessionID") != session_id:
        return
    rid = urllib.parse.quote(str(props.get("id", "")), safe="")
    try:
        if event.get("type") in ("permission.asked", "permission.v2.asked"):
            _request("POST", _url(base, f"/permission/{rid}/reply", directory), {"reply": "reject"})
            notes.append(f"OpenCode asked for permission ({props.get('permission') or 'a tool'}); "
                         "no one was there to allow it, so it was refused.")
        elif event.get("type") in ("question.asked", "question.v2.asked"):
            _request("POST", _url(base, f"/question/{rid}/reject", directory))
            notes.append("OpenCode asked a question; no one was there to answer, so it was dismissed.")
    except (OSError, ValueError):
        pass


def _watch(base: str, directory: str, session_id: str, notes: List[str], stop: threading.Event,
           connected: threading.Event) -> None:
    """Rejects permission requests and questions for our session until stopped."""
    while not stop.is_set():
        try:
            event_url = _url(base, "/event", directory)
            with urllib.request.urlopen(urllib.request.Request(event_url, headers=_headers(event_url)), timeout=60) as response:
                connected.set()
                for raw in response:
                    if stop.is_set():
                        return
                    line = raw.decode("utf-8", "replace").strip()
                    if line.startswith("data:"):
                        try:
                            _answer(base, directory, json.loads(line[5:].strip()), session_id, notes)
                        except ValueError:
                            pass
        except OSError:
            stop.wait(1)


def prompt_body(text: str, eff: Dict[str, Any], system: str, use_agent_model: bool) -> Dict[str, Any]:
    """backends/OpenCodeBackend.js promptBody."""
    body: Dict[str, Any] = {"parts": [{"type": "text", "text": text}]}
    if eff.get("agent"):
        body["agent"] = eff["agent"]
    if eff.get("provider") and eff.get("model") and (not eff.get("agent") or not use_agent_model):
        body["model"] = {"providerID": eff["provider"], "modelID": eff["model"]}
    if system:
        body["system"] = system
    if eff.get("variant"):
        body["variant"] = eff["variant"]
    return body


def run(config: Dict[str, Any], chat: Dict[str, Any], directory: str, body: Dict[str, Any], timeout: float) -> Dict[str, Any]:
    """Runs one prompt; returns {content, reasoning, tokens?, notes, sessionId}. Raises RunError."""
    server = Server(base_url(config), directory)
    notes: List[str] = []
    stop = threading.Event()
    try:
        session_id = str(chat.get("openCodeSessionId") or "")
        for attempt in range(2):
            try:
                if not session_id:
                    created = _request("POST", _url(server.base, "/session", directory), {"title": chat.get("text") or "KDE AI Chat"})
                    session_id = str((created or {}).get("id") or "")
                    if not session_id:
                        raise RunError("OpenCode didn't create a session.")
                connected = threading.Event()
                threading.Thread(target=_watch, args=(server.base, directory, session_id, notes, stop, connected),
                                 daemon=True).start()
                connected.wait(10)   # listen before the prompt goes out, so no request is missed
                sid = urllib.parse.quote(session_id, safe="")
                reply = _request("POST", _url(server.base, f"/session/{sid}/message", directory), body, timeout=timeout)
                break
            except urllib.error.HTTPError as e:
                if e.code == 404 and attempt == 0 and chat.get("openCodeSessionId"):
                    session_id = ""     # the server forgot the session: start a new one, once
                    continue
                raise RunError(f"OpenCode answered HTTP {e.code}.") from None
            except (OSError, ValueError) as e:
                raise RunError(f"OpenCode: {getattr(e, 'reason', e)}") from None
        info = (reply or {}).get("info") or {}
        if info.get("error"):
            err = info["error"]
            detail = (err.get("data") or {}).get("message") or err.get("name") if isinstance(err, dict) else err
            raise RunError("OpenCode: " + str(detail or "the request failed."))
        parts = [p for p in (reply or {}).get("parts") or [] if isinstance(p, dict)]
        out: Dict[str, Any] = {
            "content": "\n\n".join(str(p.get("text", "")) for p in parts if p.get("type") == "text" and not p.get("synthetic")).strip(),
            "reasoning": "\n\n".join(str(p.get("text", "")) for p in parts if p.get("type") == "reasoning").strip(),
            "notes": notes, "sessionId": session_id}
        tokens = info.get("tokens") or {}
        if tokens.get("input") or tokens.get("output"):
            out["tokens"] = {"input": int(tokens.get("input") or 0), "output": int(tokens.get("output") or 0)}
        return out
    finally:
        stop.set()
        server.close()
