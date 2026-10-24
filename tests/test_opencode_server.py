"""Starting/stopping `opencode serve`: the widget only stops what it started."""
import contextlib
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kdeaichat import opencode_server  # noqa: E402

FAKE_OPENCODE = """#!/usr/bin/env python3
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
port = int(sys.argv[sys.argv.index("--port") + 1])
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200 if self.path == "/global/health" else 404)
        self.end_headers()
HTTPServer(("127.0.0.1", port), H).serve_forever()
"""


def _free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _run(fn, payload):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        fn(payload)
    return json.loads(out.getvalue())


def test_start_status_stop_only_our_server():
    with tempfile.TemporaryDirectory() as tmp:
        bindir = os.path.join(tmp, "bin")
        os.makedirs(bindir)
        fake = os.path.join(bindir, "opencode")
        with open(fake, "w") as f:
            f.write(FAKE_OPENCODE)
        os.chmod(fake, 0o755)
        env = {"PATH": bindir + os.pathsep + os.environ["PATH"], "XDG_DATA_HOME": os.path.join(tmp, "data")}
        port = _free_port()
        with patch.dict(os.environ, env):
            started = _run(opencode_server.cmd_opencode_server_start, {"port": port, "directory": tmp})
            assert started["status"] == "started", started
            pid = started["pid"]
            try:
                assert _run(opencode_server.cmd_opencode_server_status, {"port": port}) == {"running": True, "ours": True, "binary": fake}
                assert _run(opencode_server.cmd_opencode_server_start, {"port": port})["status"] == "already-running"
                assert _run(opencode_server.cmd_opencode_server_stop, {})["status"] == "stopped"
                for _ in range(50):
                    if not opencode_server.healthy(port, 0.2):
                        break
                    time.sleep(0.1)
                assert not opencode_server.healthy(port, 0.2)
            finally:
                try:
                    os.kill(pid, 9)
                except OSError:
                    pass


def test_a_server_we_did_not_start_is_never_stopped():
    with tempfile.TemporaryDirectory() as tmp:
        fake = os.path.join(tmp, "opencode")
        with open(fake, "w") as f:
            f.write(FAKE_OPENCODE)
        port = _free_port()
        foreign = subprocess.Popen([sys.executable, fake, "serve", "--port", str(port)])
        try:
            with patch.dict(os.environ, {"XDG_DATA_HOME": os.path.join(tmp, "data")}):
                for _ in range(50):
                    if opencode_server.healthy(port, 0.2):
                        break
                    time.sleep(0.1)
                assert _run(opencode_server.cmd_opencode_server_start, {"port": port})["status"] == "already-running"
                assert _run(opencode_server.cmd_opencode_server_stop, {})["status"] == "not-ours"
                assert foreign.poll() is None, "the user's own server must keep running"
        finally:
            foreign.kill()
            foreign.wait()


def test_missing_binary_and_bad_port():
    with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"PATH": tmp, "HOME": tmp, "XDG_DATA_HOME": tmp}):
        result = _run(opencode_server.cmd_opencode_server_start, {"port": _free_port()})
        assert result["status"] == "error" and "isn't installed" in result["message"]
    try:
        _run(opencode_server.cmd_opencode_server_start, {"port": 80})
        assert False, "privileged port accepted"
    except ValueError:
        pass
