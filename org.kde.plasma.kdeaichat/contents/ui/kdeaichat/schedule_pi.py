"""A Pi-mode scheduled run, through the same Pi bridge the widget uses.

The bridge (pi_bridge_server.py) runs one ``pi --mode rpc`` per chat on the
chat's own Pi session, in the chat's folder, so a scheduled prompt continues
the chat exactly like one typed in the widget, and the bridge keeps the
widget and the job from driving the same Pi session at once (HTTP 409 while
a run is going on). The job opens the chat's event stream, sends the prompt
once the bridge says ``bridge_connected``, and collects the assistant
messages until ``agent_settled``.

Nobody is there to answer Pi's dialogs: a ``confirm`` is answered "no", any
other dialog is cancelled, and the reply says so. The bridge exits by itself
when idle, as it does after the widget's runs.
"""
import http.client
import json
import threading
import time
import urllib.parse
from typing import Any, Dict, List

from kdeaichat import pi_bridge
from kdeaichat.schedule_direct import RunError

from kdeaichat.pi_bridge_server import THINKING  # noqa: E402  (one copy of the levels, as the bridge checks them)


def _post(port: int, token: str, path: str, body: Dict[str, Any], timeout: float = 30) -> Any:
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        conn.request("POST", path, body=json.dumps(body), headers={"Authorization": "Bearer " + token,
                                                                    "Content-Type": "application/json"})
        response = conn.getresponse()
        text = response.read().decode("utf-8", "replace")
        try:
            return response.status, json.loads(text)
        except ValueError:
            return response.status, {}
    finally:
        conn.close()


def _text(message: Dict[str, Any], kind: str) -> str:
    key = "text" if kind == "text" else "thinking"
    return "\n".join(str(p.get(key, "")) for p in message.get("content") or [] if isinstance(p, dict) and p.get("type") == kind)


def run(chat_id: str, body: Dict[str, Any], timeout: float) -> Dict[str, Any]:
    """Runs one prompt; returns {content, reasoning, tokens?, notes}. Raises RunError."""
    if body.get("thinking") not in THINKING:
        body = dict(body, thinking="")
    bridge = pi_bridge.ensure_bridge()
    if bridge.get("status") == "error":
        raise RunError("Pi: " + str(bridge.get("message") or "the Pi bridge couldn't be started."))
    port, token = int(bridge["port"]), str(bridge["token"])
    quoted = urllib.parse.quote(chat_id, safe="")
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    conn.request("GET", f"/chats/{quoted}/events", headers={"Authorization": "Bearer " + token})
    stream = conn.getresponse()
    if stream.status != 200:
        conn.close()
        raise RunError(f"Pi: the bridge refused the event stream (HTTP {stream.status}).")
    texts: List[str] = []
    thinking: List[str] = []
    notes: List[str] = []
    usage = {"input": 0, "output": 0}
    error = ""
    deadline = time.monotonic() + timeout
    timer = threading.Timer(timeout, conn.close)   # never hang on a silent stream
    timer.daemon = True
    timer.start()
    try:
        for raw in stream:
            if time.monotonic() > deadline:
                break
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            try:
                event = json.loads(line[5:].strip())
            except ValueError:
                continue
            kind = event.get("type") if isinstance(event, dict) else None
            if kind == "bridge_connected":
                if event.get("running"):
                    raise RunError("Pi is busy with this chat right now.")
                status, reply = _post(port, token, f"/chats/{quoted}/prompt", body)
                if status == 409:
                    raise RunError("Pi is busy with this chat right now.")
                if not 200 <= status < 300:
                    raise RunError("Pi: " + str(reply.get("error") or f"the bridge refused the message (HTTP {status})."))
            elif kind == "response" and event.get("command") == "prompt" and event.get("success") is False:
                raise RunError("Pi refused the message: " + str(event.get("error") or "unknown error"))
            elif kind == "message_end" and (event.get("message") or {}).get("role") == "assistant":
                message = event["message"]
                if _text(message, "text"):
                    texts.append(_text(message, "text"))
                if _text(message, "thinking"):
                    thinking.append(_text(message, "thinking"))
                for key in ("input", "output"):
                    usage[key] += int((message.get("usage") or {}).get(key) or 0)
                if message.get("stopReason") == "error":
                    error = "Pi: " + str(message.get("errorMessage") or "the request failed.")
            elif kind == "extension_ui_request" and event.get("method") in ("confirm", "select", "input", "editor"):
                answer = {"confirmed": False} if event["method"] == "confirm" else {"cancelled": True}
                _post(port, token, f"/chats/{quoted}/ui-response", dict(answer, id=str(event.get("id", ""))))
                notes.append(f"Pi asked \"{str(event.get('title') or '')[:200]}\"; no one was there to answer, so it was declined.")
            elif kind == "agent_settled":
                if error:
                    raise RunError(error)
                out: Dict[str, Any] = {"content": "\n\n".join(texts).strip(), "reasoning": "\n\n".join(thinking), "notes": notes}
                if usage["input"] or usage["output"]:
                    out["tokens"] = usage
                return out
            elif kind == "bridge_exit":
                raise RunError(f"Pi stopped unexpectedly (exit code {event.get('code')}).")
    except (OSError, http.client.HTTPException):
        pass
    finally:
        timer.cancel()
        conn.close()
    timed_out = time.monotonic() >= deadline - 1
    try:
        _post(port, token, f"/chats/{quoted}/abort", {}, timeout=10)
    except (OSError, http.client.HTTPException):
        pass
    raise RunError(f"Pi didn't finish within {max(1, int(timeout // 60))} minutes." if timed_out
                   else "Pi: the bridge closed the event stream.")
