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
                assert opencode_server.healthy(port) and opencode_server.find_binary() == fake
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


FAKE_OPENCODE_AUTH = """#!/usr/bin/env python3
import base64, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
port = int(sys.argv[sys.argv.index("--port") + 1])
want = "Basic " + base64.b64encode(("opencode:" + os.environ.get("OPENCODE_SERVER_PASSWORD", "")).encode()).decode()
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        ok = os.environ.get("OPENCODE_SERVER_PASSWORD") and self.headers.get("Authorization") == want
        self.send_response(200 if ok and self.path == "/global/health" else 401)
        self.end_headers()
HTTPServer(("127.0.0.1", port), H).serve_forever()
"""


def test_the_server_the_widget_starts_has_a_random_password_kept_private():
    import stat
    import urllib.error
    import urllib.request
    with tempfile.TemporaryDirectory() as tmp:
        bindir = os.path.join(tmp, "bin")
        os.makedirs(bindir)
        fake = os.path.join(bindir, "opencode")
        with open(fake, "w") as f:
            f.write(FAKE_OPENCODE_AUTH)
        os.chmod(fake, 0o755)
        data = os.path.join(tmp, "data")
        os.makedirs(os.path.join(data, "kdeaichat"), mode=0o755)  # an older folder with loose permissions
        os.chmod(os.path.join(data, "kdeaichat"), 0o755)
        port = _free_port()
        env = {"PATH": bindir + os.pathsep + os.environ["PATH"], "XDG_DATA_HOME": data}
        with patch.dict(os.environ, env):
            started = _run(opencode_server.cmd_opencode_server_start, {"port": port, "directory": tmp})
            assert started["status"] == "started", started
            try:
                state_file = os.path.join(data, "kdeaichat", "opencode-server.json")
                with open(state_file) as f:
                    state = json.load(f)
                password = state["password"]
                assert len(password) >= 32
                assert password not in " ".join(state["argv"]), "never in argv"
                with open(f"/proc/{started['pid']}/cmdline", "rb") as f:
                    assert password.encode() not in f.read()
                with open(os.path.join(data, "kdeaichat", "opencode-server.log"), "rb") as f:
                    assert password.encode() not in f.read()
                assert stat.S_IMODE(os.stat(state_file).st_mode) == 0o600
                assert stat.S_IMODE(os.stat(os.path.join(data, "kdeaichat", "opencode-server.log")).st_mode) == 0o600
                assert stat.S_IMODE(os.stat(os.path.join(data, "kdeaichat")).st_mode) == 0o700
                # Without the password the server refuses; with it (what the widget sends) it answers.
                try:
                    urllib.request.urlopen(f"http://127.0.0.1:{port}/global/health", timeout=2)
                    assert False, "answered without a password"
                except urllib.error.HTTPError as e:
                    assert e.code == 401
                auth = _run(opencode_server.cmd_opencode_server_auth, {"port": port})["authorization"]
                request = urllib.request.Request(f"http://127.0.0.1:{port}/global/health", headers={"Authorization": auth})
                assert urllib.request.urlopen(request, timeout=2).status == 200
                assert _run(opencode_server.cmd_opencode_server_auth, {"port": port + 1})["authorization"] == ""
                assert _run(opencode_server.cmd_opencode_server_start, {"port": port})["status"] == "already-running"
            finally:
                _run(opencode_server.cmd_opencode_server_stop, {})
                try:
                    os.kill(started["pid"], 9)
                except OSError:
                    pass


def test_a_server_the_user_started_gets_no_credentials():
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
                assert _run(opencode_server.cmd_opencode_server_auth, {"port": port})["authorization"] == ""
        finally:
            foreign.kill()
            foreign.wait()
