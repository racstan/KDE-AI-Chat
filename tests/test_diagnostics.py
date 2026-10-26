"""setup_check: fake programs, fake servers and missing tools; nothing real is probed or started."""
import json
import os
import socket
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from kdeaichat import diag_agents, diag_system, diagnostics, schedule_store

from tests.conftest import UI_DIR

HELPER = os.path.join(UI_DIR, "kde_ai_helper.py")


@pytest.fixture
def env(sched_env, tmp_path, monkeypatch):
    """Empty PATH (only fakes), a temp HOME, the sched_env folders and fake systemctl."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "python3").symlink_to(sys.executable)  # for the fake systemctl's `#!/usr/bin/env python3`
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("PATH", str(bin_dir))
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("KDEAICHAT_STT_RECORDER", raising=False)
    monkeypatch.setenv("HF_HUB_CACHE", str(tmp_path / "hf"))
    sched_env.bin = bin_dir
    return sched_env


def fake_program(env, name, output="1.2.3", code=0):
    path = env.bin / name
    path.write_text(f"#!{sys.executable}\nimport sys\nprint({output!r})\nsys.exit({code})\n")
    path.chmod(0o755)
    return str(path)


class _Server:
    """A loopback HTTP server answering GET <path> with (status, JSON body)."""

    def __init__(self, routes):
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                status, body = outer.routes.get(self.path, (404, {"error": "not found"}))
                data = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.routes = routes
        self.httpd = HTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


@pytest.fixture
def server():
    made = []

    def make(routes):
        s = _Server(routes)
        made.append(s)
        return s
    yield make
    for s in made:
        s.close()


def closed_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def codes(rows):
    return [(r["status"], r["code"]) for r in rows]


# ── Local servers ──────────────────────────────────────────────────────────

def test_endpoint_answers_with_models(env, server):
    s = server({"/v1/models": (200, {"data": [{"id": "llama3"}, {"id": "qwen3"}]})})
    r = diag_agents.check_endpoint({"id": "ollama", "name": "Ollama", "url": s.url + "/v1/"})
    assert (r["status"], r["code"], r["args"]) == ("ok", "local-ok", ["Ollama", s.url + "/v1", "2"])
    assert r["id"] == "endpoint:ollama" and r["area"] == "connection"


def test_endpoint_404_refused_timeout_bad_url_and_key(env, server):
    s = server({"/v1/models": (401, {})})
    assert diag_agents.check_endpoint({"id": "a", "name": "A", "url": s.url + "/api"})["code"] == "local-not-found"
    assert diag_agents.check_endpoint({"id": "a", "name": "A", "url": s.url + "/v1"})["code"] == "local-needs-key"
    refused = diag_agents.check_endpoint({"id": "lm", "name": "LM Studio", "url": f"http://127.0.0.1:{closed_port()}/v1"})
    assert (refused["status"], refused["code"]) == ("error", "local-refused")
    # A server that accepts the connection but never answers.
    silent = socket.socket()
    silent.bind(("127.0.0.1", 0))
    silent.listen(1)
    try:
        slow = diag_agents.check_endpoint({"id": "x", "name": "X", "url": f"http://127.0.0.1:{silent.getsockname()[1]}/v1"},
                                          timeout=0.3)
    finally:
        silent.close()
    assert (slow["status"], slow["code"]) == ("error", "local-timeout")
    for bad in ("", "ftp://x/v1", "http://", "http://user@host/v1", "http://a b/v1"):
        assert diag_agents.check_endpoint({"id": "b", "name": "B", "url": bad})["code"] == "url-bad", bad


def test_endpoint_other_http_error(env, server):
    s = server({"/v1/models": (500, {})})
    r = diag_agents.check_endpoint({"id": "a", "name": "A", "url": s.url + "/v1"})
    assert (r["status"], r["code"], r["args"][2]) == ("warn", "local-http", "500")


# ── OpenCode ───────────────────────────────────────────────────────────────

def test_opencode_running_reports_version(env, server):
    s = server({"/global/health": (200, {"healthy": True, "version": "1.18.2"})})
    rows = diag_agents.check_opencode(s.url + "/v1")
    assert codes(rows) == [("ok", "opencode-running")] and rows[0]["args"] == [s.url, "1.18.2"]


def test_opencode_not_running(env, server):
    url = f"http://127.0.0.1:{closed_port()}/v1"
    # Not installed: one clear error, nothing about the server.
    assert codes(diag_agents.check_opencode(url)) == [("error", "opencode-missing")]
    # Installed: the widget starts it on the first message.
    fake_program(env, "opencode", "1.18.2")
    rows = diag_agents.check_opencode(url)
    assert codes(rows) == [("ok", "opencode-starts")] and rows[0]["args"][1] == "1.18.2"
    # Something else on that port.
    s = server({})
    assert codes(diag_agents.check_opencode(s.url)) == [("error", "opencode-not-server")]
    # A remote address isn't started by the widget, and needs no local program.
    os.unlink(env.bin / "opencode")
    assert codes(diag_agents.check_opencode("http://192.0.2.1:9/v1", timeout=0.2))[0][0] == "error"
    assert codes(diag_agents.check_opencode("not a url")) == [("error", "opencode-bad-url")]


def test_opencode_base_url():
    assert diag_agents.opencode_base("http://127.0.0.1:4096/v1/") == "http://127.0.0.1:4096"
    assert diag_agents.opencode_base("") == "http://127.0.0.1:4096"
    assert diag_agents.opencode_base("https://oc.example/") == "https://oc.example"


# ── Pi ────────────────────────────────────────────────────────────────────

def test_pi_missing_and_installed(env):
    rows = diag_agents.check_pi()
    assert codes(rows) == [("error", "pi-missing"), ("ok", "pi-bridge-starts")]
    fake_program(env, "pi", "0.84.0")
    rows = diag_agents.check_pi()
    assert codes(rows)[0] == ("ok", "pi-ok") and rows[0]["args"][1] == "0.84.0"
    # A program that fails --version still counts as installed, without a version.
    fake_program(env, "pi", "boom", code=3)
    assert diag_agents.check_pi()[0]["args"][1] == ""


# ── Attachments, voice, schedules ─────────────────────────────────────────

def test_attachments(env):
    assert codes(diag_system.check_attachments()) == [("warn", "pdf-missing"), ("warn", "docx-basic")]
    fake_program(env, "pdftotext")
    fake_program(env, "pandoc")
    assert codes(diag_system.check_attachments()) == [("ok", "pdf-ok"), ("ok", "docx-ok")]


def test_dictation(env, monkeypatch):
    rows = diag_system.check_dictation({"sttEngine": "faster-whisper"})
    assert ("error", "stt-no-recorder") in codes(rows)
    assert codes(rows)[-1][1] in ("stt-fw-missing", "stt-no-venv")
    fake_program(env, "pw-record")
    assert codes(diag_system.check_dictation({"sttEngine": "remote"})) == [("ok", "stt-recorder-ok"),
                                                                        ("error", "stt-remote-url")]
    assert codes(diag_system.check_dictation({"sttEngine": "remote", "sttRemoteUrl": "http://localhost:9/v1"}))[-1] \
        == ("ok", "stt-ready")
    assert codes(diag_system.check_dictation({"sttEngine": "whisper-cpp"}))[-1] == ("error", "stt-whispercpp-missing")
    fake_program(env, "whisper-cli")
    assert codes(diag_system.check_dictation({"sttEngine": "whisper-cpp"}))[-1] == ("error", "stt-whispercpp-model")
    assert codes(diag_system.check_dictation({"sttEngine": "command", "sttCommand": "nope {wav}"}))[-1] \
        == ("error", "stt-command-bad")
    assert codes(diag_system.check_dictation({"sttEngine": "warp"})) == [("error", "stt-bad-settings")]


def test_dictation_faster_whisper_model(env, tmp_path):
    venv = tmp_path / "venv"
    (venv / "bin").mkdir(parents=True)
    (venv / "bin" / "python3").write_text("")
    (venv / "lib" / "python3.13" / "site-packages" / "faster_whisper").mkdir(parents=True)
    fake_program(env, "pw-record")
    payload = {"sttEngine": "faster-whisper", "sttModel": "small", "venv": str(venv)}
    rows = diag_system.check_dictation(payload)
    assert codes(rows)[-1] == ("warn", "stt-model-missing") and rows[-1]["args"] == ["small"]
    snap = tmp_path / "hf" / "models--Systran--faster-whisper-small" / "snapshots" / "abc"
    snap.mkdir(parents=True)
    (snap / "model.bin").write_text("x")
    assert codes(diag_system.check_dictation(payload))[-1] == ("ok", "stt-ready")
    rows = diag_system.check_dictation(dict(payload, sttModel=str(tmp_path / "missing-model")))
    assert codes(rows)[-1] == ("error", "stt-model-folder-missing")


def test_read_aloud(env, tmp_path):
    assert codes(diag_system.check_read_aloud({"voiceTtsEngine": "piper"})) == [("error", "tts-piper-missing")]
    fake_program(env, "piper")
    assert codes(diag_system.check_read_aloud({"voiceTtsEngine": "piper", "voiceTtsPiperModel": "/nope.onnx"})) \
        == [("error", "tts-piper-voice")]
    voice = tmp_path / "v.onnx"
    voice.write_text("x")
    assert codes(diag_system.check_read_aloud({"voiceTtsEngine": "piper", "voiceTtsPiperModel": str(voice)})) \
        == [("ok", "tts-ready")]
    assert codes(diag_system.check_read_aloud({"voiceTtsEngine": "remote", "voiceTtsRemoteUrl": "x"})) \
        == [("error", "tts-remote-url")]
    assert codes(diag_system.check_read_aloud({"voiceTtsEngine": "command", "voiceTtsCommand": "missing-prog"})) \
        == [("error", "tts-command-bad")]
    assert codes(diag_system.check_read_aloud({"voiceTtsEngine": "system"})) == [("warn", "tts-speechd-missing")]
    assert codes(diag_system.check_read_aloud({"voiceTtsEngine": "kokoro"})) == [("ok", "tts-qt-engine")]


OWNER = {"name": "News", "chatId": "chat-news", "message": "hi",
         "rules": [{"kind": "daily", "times": ["16:00"]}]}


def test_schedules(env, capsys, monkeypatch):
    assert codes(diag_system.check_schedules()) == [("ok", "sched-none")]
    schedule_store.cmd_schedule_save({"schedule": dict(OWNER, id="news-1")})
    capsys.readouterr()
    assert codes(diag_system.check_schedules()) == [("ok", "sched-ok")]
    calls = len(env.calls())
    os.unlink(os.path.join(env.units, "kdeaichat-sched-news-1.timer"))
    rows = diag_system.check_schedules()
    assert codes(rows) == [("error", "sched-timers-missing")] and rows[0]["args"] == ["1"]
    # Only looked: no unit was written, enabled or reloaded.
    assert not os.path.exists(os.path.join(env.units, "kdeaichat-sched-news-1.timer"))
    assert all("show-environment" in c or "is-enabled" in c for c in env.calls()[calls:])
    monkeypatch.setenv("FAKE_SYSTEMCTL_EXIT", "1")
    assert codes(diag_system.check_schedules()) == [("error", "sched-no-systemd")]


# ── The command ───────────────────────────────────────────────────────────

def test_setup_check_command_per_mode(env, server):
    s = server({"/v1/models": (200, {"data": []})})
    payload = {"mode": "direct", "endpoints": [{"id": "ollama", "name": "Ollama", "url": s.url + "/v1"}],
               "stt": {"sttEnabled": False}, "tts": {"voiceTtsEnabled": False}}
    ids = [r["id"] for r in diagnostics.run_checks(payload)]
    assert ids == ["endpoint:ollama", "attach-pdf", "attach-docx", "schedules"]
    ids = [r["id"] for r in diagnostics.run_checks({"mode": "pi", "stt": {"sttEnabled": True}})]
    assert ids[:2] == ["pi-program", "pi-bridge"] and "stt-recorder" in ids and "endpoint:ollama" not in ids
    ids = [r["id"] for r in diagnostics.run_checks({"mode": "opencode", "openCodeUrl": "bad url",
                                                    "tts": {"voiceTtsEnabled": True, "voiceTtsEngine": "kokoro"}})]
    assert ids == ["opencode-server", "attach-pdf", "attach-docx", "tts-engine", "schedules"]


def test_setup_check_through_the_helper(env):
    payload = {"mode": "pi"}
    import base64
    arg = base64.b64encode(json.dumps(payload).encode()).decode()
    out = subprocess.run([sys.executable, HELPER, "setup_check", arg], capture_output=True, text=True, timeout=60,
                         env=dict(os.environ))
    assert out.returncode == 0, out.stdout + out.stderr
    rows = json.loads(out.stdout)["checks"]
    assert rows[0]["code"] == "pi-missing"
    assert all(set(r) == {"id", "area", "status", "code", "args"} for r in rows)
    assert all(r["status"] in ("ok", "warn", "error") for r in rows)
