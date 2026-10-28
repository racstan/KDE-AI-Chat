#!/usr/bin/env python3
"""The OpenCode server of the demo video (scripts/dev-media.sh): what `opencode serve` answers, played from a
script, but on real files. Several agents (build, plan, docs and review, plus a helper subagent that is not
offered), one provider "Demo", and per prompt a run with reasoning, tool calls and a reply:

  - "what does <path> do/check":  `read` of that real file in the chat's folder (its real first lines), a summary;
  - "create <name>":              a `write` that waits for the permission answer, then really writes the file
                                  (only inside the chat's folder, only under build/);
  - with the plan agent:          a plan, no tools.

Usage: scripts/media/demo_opencode.py [port]   (default 18766). Loopback only; nothing leaves the machine.
"""
import itertools
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18766
AGENTS = [{"name": "build", "mode": "primary"}, {"name": "plan", "mode": "primary"},
          {"name": "docs", "mode": "primary"}, {"name": "review", "mode": "primary"},
          {"name": "general", "mode": "subagent"}, {"name": "title", "mode": "primary", "hidden": True}]
PROVIDERS = {"providers": [{"id": "demo", "name": "Demo", "models": {
    "nova-coder": {"id": "nova-coder", "name": "Nova Coder", "variants": {"low": {}, "high": {}}},
    "nova-mini": {"id": "nova-mini", "name": "Nova Mini"}}}], "default": {"demo": "nova-coder"}}

streams, lock = [], threading.Lock()
ids = itertools.count(1)
permissions = {}   # id -> threading.Event, answer


def broadcast(kind, props):
    data = ("data: " + json.dumps({"type": kind, "properties": props}) + "\n\n").encode()
    with lock:
        for w in list(streams):
            try:
                w.write(data)
                w.flush()
            except OSError:
                streams.remove(w)


def inside(folder, rel):
    path = os.path.realpath(os.path.join(folder, rel))
    return path if folder and path.startswith(os.path.realpath(folder) + os.sep) else None


def stream_text(s, msg, text):
    part = "p%d" % next(ids)
    broadcast("message.part.updated", {**s, "part": {"id": part, "messageID": msg, "type": "text", "text": ""}})
    words = text.split(" ")
    for i in range(0, len(words), 3):
        time.sleep(0.06)
        chunk = " ".join(words[i:i + 3]) + (" " if i + 3 < len(words) else "")
        broadcast("message.part.delta", {**s, "messageID": msg, "partID": part, "field": "text", "delta": chunk})


def tool(s, msg, name, call, status, inp, output="", title=""):
    state = {"status": status, "input": inp}
    if status == "completed":
        state.update({"output": output, "title": title, "metadata": {}, "time": {}})
    broadcast("message.part.updated", {**s, "part": {"id": "t" + call, "messageID": msg, "type": "tool", "callID": call,
                                                    "tool": name, "state": state}})


def think(s, msg, text):
    broadcast("message.part.updated", {**s, "part": {"id": "r%d" % next(ids), "messageID": msg, "type": "reasoning", "text": text}})
    time.sleep(0.5)


def run(session, folder, agent, text):
    s = {"sessionID": session}
    msg = "m%d" % next(ids)
    # Memories go before the message (chat/Memory.qml withMemories): only the message itself picks the run.
    if text.startswith("## Things the user asked you to remember") and "\n\n---\n\n" in text:
        text = text.split("\n\n---\n\n", 1)[1]
    low = text.lower()
    broadcast("session.status", {**s, "status": {"type": "busy"}})
    broadcast("message.updated", {**s, "info": {"id": msg, "role": "assistant"}})
    time.sleep(0.6)
    words = [w.strip("?.,") for w in text.split()]
    target = next((w for w in words if "/" in w or w.endswith((".py", ".md", ".txt"))), "")
    if agent == "plan":
        reply = PLAN
        think(s, msg, "Planning only: no files change in plan mode.")
    elif low.startswith("create") and target:
        think(s, msg, "I'll write %s in the build folder." % target)
        call = "c%d" % next(ids)
        tool(s, msg, "write", call, "pending", {"filePath": target})
        perm = "per%d" % next(ids)
        event = threading.Event()
        permissions[perm] = [event, "reject"]
        broadcast("permission.asked", {**s, "id": perm, "permission": "edit", "patterns": [target], "metadata": {}, "always": []})
        event.wait(120)
        broadcast("permission.replied", {**s, "requestID": perm, "reply": permissions[perm][1]})
        path = inside(folder, target)
        if permissions[perm][1] != "reject" and path and "/build/" in path:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write("Hello from KDE AI Chat! This file was written by the build agent.\n")
            tool(s, msg, "write", call, "completed", {"filePath": target}, "Wrote %s" % target, target)
            reply = "Created `%s` with a short greeting." % target
        else:
            reply = "I left `%s` alone." % target
    elif target and inside(folder, target) and os.path.isfile(inside(folder, target)):
        think(s, msg, "Let me read %s first." % target)
        call = "c%d" % next(ids)
        tool(s, msg, "read", call, "running", {"filePath": target})
        with open(inside(folder, target), encoding="utf-8", errors="replace") as f:
            head = "".join(f.readlines()[:40])
        time.sleep(0.8)
        tool(s, msg, "read", call, "completed", {"filePath": target}, head, target)
        reply = SUMMARIES.get(target, "I read `%s`; it is %d lines long." % (target, head.count("\n")))
    else:
        think(s, msg, "A short answer will do.")
        reply = "Tell me a file to look at, for example `scripts/check_file_sizes.py`."
    stream_text(s, msg, reply)
    broadcast("message.part.updated", {**s, "part": {"id": "f%d" % next(ids), "messageID": msg, "type": "step-finish", "reason": "stop",
                                                    "cost": 0.0021, "tokens": {"input": 3400, "output": 160, "reasoning": 40}}})
    broadcast("session.status", {**s, "status": {"type": "idle"}})
    broadcast("session.idle", s)


# Accurate summaries of the real files the video asks about.
SUMMARIES = {
    "scripts/check_file_sizes.py": "It keeps the code easy to read: every QML, JavaScript and Python file in the widget must "
                                   "stay under **400 lines**. A few older files are on an allowlist, and that list may only "
                                   "shrink. CI runs it on every push.",
}
PLAN = """Here is a plan; nothing is changed yet.

1. **Find the setting**: add `darkCodeBlocks` to `main.xml`.
2. **Show it**: a switch in Settings → Appearance.
3. **Use it**: code blocks pick their colours from it.
4. **Test it**: a QML test that flips the switch and checks a code block.

Switch to the **build** agent when you want me to do it."""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _json(self, code, obj=None):
        body = b"" if obj is None else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/event":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(b'data: {"type":"server.connected","properties":{}}\n\n')
            self.wfile.flush()
            with lock:
                streams.append(self.wfile)
            try:
                while True:
                    time.sleep(1)
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
            except OSError:
                return
        if url.path == "/global/health":
            return self._json(200, {"healthy": True, "version": "1.18.0"})
        if url.path in ("/config/providers", "/provider"):
            return self._json(200, PROVIDERS)
        if url.path == "/agent":
            return self._json(200, AGENTS)
        if url.path in ("/permission", "/session/status"):
            return self._json(200, [] if url.path == "/permission" else {})
        if url.path.startswith("/session/") and url.path.endswith("/message"):
            return self._json(200, [])
        return self._json(404, {"error": "not found"})

    def do_POST(self):
        url = urlparse(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"null") or {}
        except ValueError:
            body = {}
        folder = (parse_qs(url.query).get("directory") or [""])[0]
        if url.path == "/session":
            return self._json(200, {"id": "ses_demo%d" % next(ids), "title": body.get("title", "")})
        if url.path.endswith("/prompt_async"):
            session = url.path.split("/")[2]
            text = " ".join(p.get("text", "") for p in body.get("parts", []) if p.get("type") == "text")
            threading.Thread(target=run, args=(session, folder, body.get("agent", "build"), text), daemon=True).start()
            return self._json(204)
        if url.path.startswith("/permission/") and url.path.endswith("/reply"):
            entry = permissions.get(url.path.split("/")[2])
            if entry:
                entry[1] = body.get("reply", "once")
                entry[0].set()
            return self._json(200, True)
        if url.path.endswith("/abort"):
            return self._json(200, True)
        return self._json(404, {"error": "not found"})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
