"""Headless scheduled runs in OpenCode and Pi mode (fake `opencode serve`, Pi bridge with the Pi mock)."""
import datetime as dt
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request

import pytest

from kdeaichat import pi_bridge, schedule_exec

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOW = dt.datetime(2026, 10, 27, 9, 0)
SCHEDULE = {"id": "agent-1", "name": "Morning check", "chatId": "s-1", "message": "Check the build", "notify": True}

FAKE_OPENCODE = r'''#!/usr/bin/env python3
# A fake `opencode serve --port N`: sessions, a blocking /message that first asks for a permission, /event.
import json, os, queue, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
port = int(sys.argv[sys.argv.index("--port") + 1])
log = os.environ["FAKE_OC_LOG"]
clients, replies = [], queue.Queue()
def record(entry):
    with open(log, "a") as f:
        f.write(json.dumps(entry) + "\n")
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, status, obj):
        data = json.dumps(obj).encode()
        self.send_response(status); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        if self.path == "/global/health":
            return self.reply(200, {"healthy": True})
        if self.path.startswith("/event"):
            q = queue.Queue(); clients.append(q)
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
            self.wfile.write(b"data: {\"type\":\"server.connected\",\"properties\":{}}\n\n"); self.wfile.flush()
            while True:
                self.wfile.write(("data: " + q.get() + "\n\n").encode()); self.wfile.flush()
        self.reply(404, {})
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"null") if n else None
        record({"path": self.path, "body": body})
        path = self.path.split("?")[0]
        if path == "/session":
            return self.reply(200, {"id": "ses_new"})
        if path.startswith("/permission/"):
            replies.put(body); return self.reply(200, True)
        if path.endswith("/message"):
            sid = path.split("/")[2]
            if sid == "ses_gone":
                return self.reply(404, {"name": "NotFound"})
            event = {"type": "permission.asked", "properties": {"id": "per_1", "sessionID": sid, "permission": "bash"}}
            for q in list(clients):
                q.put(json.dumps(event))
            try:
                replies.get(timeout=10)
            except queue.Empty:
                return self.reply(500, {"error": "nobody answered"})
            return self.reply(200, {"info": {"role": "assistant", "tokens": {"input": 3, "output": 4}},
                                    "parts": [{"type": "reasoning", "text": "thinking"},
                                              {"type": "text", "text": "Done in OpenCode", "synthetic": False}]})
        self.reply(404, {})
ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
'''


def _free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _healthy(port):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/global/health", timeout=1):
            return True
    except OSError:
        return False


@pytest.fixture
def opencode(tmp_path, monkeypatch):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    fake = bindir / "opencode"
    fake.write_text(FAKE_OPENCODE)
    fake.chmod(0o755)
    log = tmp_path / "opencode.log"
    monkeypatch.setenv("FAKE_OC_LOG", str(log))
    monkeypatch.setenv("PATH", str(bindir) + os.pathsep + os.environ["PATH"])

    class OC:
        def requests(self):
            return [json.loads(line) for line in open(log)] if log.exists() else []
    return OC()


def test_opencode_runs_in_the_chats_session_and_refuses_permissions(chat_env, opencode, tmp_path):
    port = _free_port()
    server = subprocess.Popen([os.path.join(tmp_path, "bin", "opencode"), "serve", "--port", str(port)])
    try:
        deadline = time.time() + 10
        while not _healthy(port) and time.time() < deadline:
            time.sleep(0.1)
        chat_env.config(useOpenCode=False, openCodeUrl=f"http://127.0.0.1:{port}/v1", openCodeProvider="prov",
                        openCodeModel="mod", openCodeAgent="build", systemPrompt="Sys.")
        chat_env.add_chat("s-1", [], source="opencode", openCodeSessionId="ses_old", openCodeWorkspaceCwd=str(tmp_path))
        assert schedule_exec.run_prompt(dict(SCHEDULE), None, NOW) == "ok"
    finally:
        server.terminate()
    calls = opencode.requests()
    message = next(c for c in calls if c["path"].startswith("/session/ses_old/message"))
    assert "directory=" + str(tmp_path).replace("/", "%2F") in message["path"]
    assert message["body"] == {"parts": [{"type": "text", "text": "Check the build"}], "agent": "build",
                               "model": {"providerID": "prov", "modelID": "mod"}, "system": "Sys."}
    assert any(c["path"].startswith("/permission/per_1/reply") and c["body"] == {"reply": "reject"} for c in calls)
    reply = chat_env.messages("s-1")[-1]
    assert reply["content"].startswith("Done in OpenCode") and "no one was there to allow it" in reply["content"]
    assert reply["reasoning"] == "thinking" and reply["model"] == "prov/mod" and reply["tokens"] == {"input": 3, "output": 4}
    assert "sessionUpdates" not in chat_env.inbox_entry(chat_env.inbox()[0])


def test_opencode_starts_a_temporary_server_and_a_new_session(chat_env, opencode):
    closed = _free_port()   # nothing listens on the configured local URL
    chat_env.config(openCodeUrl=f"http://127.0.0.1:{closed}")
    chat_env.add_chat("s-1", [], source="opencode")
    assert schedule_exec.run_prompt(dict(SCHEDULE), None, NOW) == "ok"
    calls = opencode.requests()
    assert calls[0]["path"].startswith("/session") and calls[0]["body"] == {"title": "Chat s-1"}
    assert any(c["path"].startswith("/session/ses_new/message") for c in calls)
    entry = chat_env.inbox_entry(chat_env.inbox()[0])
    assert entry["sessionUpdates"] == {"openCodeSessionId": "ses_new"}
    # the temporary server is gone again
    out = subprocess.run(["pgrep", "-f", str(os.environ["FAKE_OC_LOG"]).rsplit("/", 1)[0] + "/bin/opencode serve"],
                         capture_output=True, text=True)
    assert out.stdout.strip() == ""


def test_opencode_not_installed_is_an_error(chat_env, monkeypatch):
    monkeypatch.setenv("PATH", "/nonexistent")
    monkeypatch.setattr("kdeaichat.opencode_server.find_binary", lambda: None)
    chat_env.config(openCodeUrl=f"http://127.0.0.1:{_free_port()}")
    chat_env.add_chat("s-1", [], source="opencode")
    status = schedule_exec.run_prompt(dict(SCHEDULE), None, NOW)
    assert status == "error: OpenCode isn't installed (no `opencode` command found)."
    assert chat_env.messages("s-1") == []


@pytest.fixture
def pi_mock(tmp_path, monkeypatch):
    bindir = tmp_path / "pibin"
    bindir.mkdir()
    os.symlink(os.path.join(ROOT, "scripts", "dev-pi-mock.py"), bindir / "pi")
    log = tmp_path / "pi.log"
    monkeypatch.setenv("PATH", str(bindir) + os.pathsep + os.environ["PATH"])
    monkeypatch.setenv("KDEAICHAT_PI_MOCK_LOG", str(log))
    yield log
    pi_bridge.cmd_pi_bridge_stop({})


def test_pi_runs_through_the_bridge_in_the_chats_folder(chat_env, pi_mock, tmp_path, capsys):
    work = tmp_path / "work"
    work.mkdir()
    chat_env.config(usePi=False, piProvider="ollama", piModel="qwen")
    chat_env.add_chat("s-1", [], source="pi", openCodeWorkspaceCwd=str(work), chatSystemPrompt="Be careful.", piThinking="high",
                      ownModel=False)
    assert schedule_exec.run_prompt(dict(SCHEDULE), None, NOW) == "ok"
    reply = chat_env.messages("s-1")[-1]
    assert reply["content"] == "done" and reply["model"] == "Pi · qwen" and reply["tokens"]["input"] > 0
    log = [json.loads(line) for line in open(pi_mock)]
    start = log[0]
    assert start["cwd"] == str(work) and "--session-id" in start["argv"] and "kde-ai-chat-s-1" in start["argv"]
    assert start["argv"][start["argv"].index("--model") + 1] == "qwen"
    prompt = next(e["command"] for e in log if "command" in e and e["command"]["type"] == "prompt")
    assert prompt["message"] == "Check the build"


def test_pi_dialogs_are_declined(chat_env, pi_mock, monkeypatch):
    monkeypatch.setenv("KDEAICHAT_PI_MOCK_FIXTURE", os.path.join(ROOT, "tests", "fixtures", "pi-0.84-ollama-permission-denied.jsonl"))
    chat_env.config(piProvider="ollama", piModel="qwen")
    chat_env.add_chat("s-1", [], source="pi")
    schedule_exec.run_prompt(dict(SCHEDULE), None, NOW)
    log = [json.loads(line) for line in open(pi_mock)]
    answers = [e["command"] for e in log if "command" in e and e["command"]["type"] == "extension_ui_response"]
    assert answers and answers[0]["cancelled"] is True  # a "select" dialog (Allow? Yes/No): cancelled
    assert "no one was there to answer" in chat_env.messages("s-1")[-1]["content"]


def test_pi_not_installed(chat_env, monkeypatch):
    monkeypatch.setenv("PATH", "/nonexistent-bin")
    chat_env.config()
    chat_env.add_chat("s-1", [], source="pi")
    try:
        status = schedule_exec.run_prompt(dict(SCHEDULE), None, NOW)
    finally:
        pi_bridge.cmd_pi_bridge_stop({})
    assert status.startswith("error: Pi") and chat_env.messages("s-1") == []
