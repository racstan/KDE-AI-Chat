#!/usr/bin/env python3
"""A fake `opencode serve` for testing the widget's OpenCode mode end to end.

Implements the routes the widget uses (OpenCode 1.18 v1 API) and, for each
prompt, plays a scripted run: reasoning, a `write` tool call with a permission
request, the reply text and token usage, then idle. Requests are logged to
stdout as JSON lines so a test can check what the widget sent.

Usage: scripts/dev-opencode-mock.py [port]   (default 4918)
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4918
SESSION = "ses_mock"
streams = []
streams_lock = threading.Lock()


def log(entry):
    print(json.dumps(entry), flush=True)


def broadcast(event_type, properties):
    data = "data: " + json.dumps({"type": event_type, "properties": properties}) + "\n\n"
    with streams_lock:
        for wfile in list(streams):
            try:
                wfile.write(data.encode())
                wfile.flush()
            except OSError:
                streams.remove(wfile)


def scripted_run(prompt_text):
    s = {"sessionID": SESSION}
    steps = [
        ("message.updated", {**s, "info": {"id": "msg_user", "role": "user"}}),
        ("message.part.updated", {**s, "part": {"id": "p_user", "messageID": "msg_user", "type": "text", "text": prompt_text}}),
        ("session.status", {**s, "status": {"type": "busy"}}),
        ("message.updated", {**s, "info": {"id": "msg_a", "role": "assistant"}}),
        ("message.part.updated", {**s, "part": {"id": "p_r", "messageID": "msg_a", "type": "reasoning", "text": "I'll write the file."}}),
        ("message.part.updated", {**s, "part": {"id": "p_t", "messageID": "msg_a", "type": "tool", "callID": "call_1", "tool": "write",
                                                 "state": {"status": "pending", "input": {"filePath": "hello.txt"}, "raw": ""}}}),
        ("permission.asked", {**s, "id": "per_mock", "permission": "edit", "patterns": ["hello.txt"], "metadata": {}, "always": []}),
        ("message.part.updated", {**s, "part": {"id": "p_t", "messageID": "msg_a", "type": "tool", "callID": "call_1", "tool": "write",
                                                 "state": {"status": "completed", "input": {}, "output": "Wrote hello.txt", "title": "hello.txt",
                                                           "metadata": {}, "time": {}}}}),
        ("message.part.updated", {**s, "part": {"id": "p_x", "messageID": "msg_a", "type": "text", "text": ""}}),
        ("message.part.delta", {**s, "messageID": "msg_a", "partID": "p_x", "field": "text", "delta": "Created "}),
        ("message.part.delta", {**s, "messageID": "msg_a", "partID": "p_x", "field": "text", "delta": "hello.txt."}),
        ("message.part.updated", {**s, "part": {"id": "p_f", "messageID": "msg_a", "type": "step-finish", "reason": "stop", "cost": 0.0012,
                                                 "tokens": {"input": 1200, "output": 9, "reasoning": 4}}}),
        ("session.status", {**s, "status": {"type": "idle"}}),
        ("session.idle", s),
    ]
    for event_type, properties in steps:
        time.sleep(0.15)
        broadcast(event_type, properties)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, status, obj=None):
        body = b"" if obj is None else json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw or b"null")
        except ValueError:
            return None

    def do_GET(self):
        url = urlparse(self.path)
        log({"method": "GET", "path": url.path, "query": url.query})
        if url.path == "/event":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(b'data: {"type":"server.connected","properties":{}}\n\n')
            self.wfile.flush()
            with streams_lock:
                streams.append(self.wfile)
            try:
                while True:
                    time.sleep(1)
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
            except OSError:
                return
        if url.path == "/global/health":
            return self._json(200, {"healthy": True, "version": "mock"})
        return self._json(404, {"error": "not mocked"})

    def do_POST(self):
        url = urlparse(self.path)
        body = self._body()
        log({"method": "POST", "path": url.path, "query": url.query, "body": body})
        if url.path == "/session":
            return self._json(200, {"id": SESSION, "title": (body or {}).get("title", "")})
        if url.path.endswith("/prompt_async"):
            text = " ".join(p.get("text", "") for p in (body or {}).get("parts", []) if p.get("type") == "text")
            threading.Thread(target=scripted_run, args=(text,), daemon=True).start()
            return self._json(204)
        if url.path.endswith("/abort") or url.path.endswith("/reply") or url.path.endswith("/reject"):
            return self._json(200, True)
        return self._json(404, {"error": "not mocked"})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
