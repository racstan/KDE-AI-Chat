"""Runs tests/qml/stt/dictation.qml: SttBackend -> kde_ai_helper.py stt_dictate/stt_stop -> a fake speech server, end to end.

The environment points the helper at a fake recorder (never the microphone),
a private runtime folder, a sandboxed unit folder and a no-op systemctl.
"""
import json
import os
import re
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_qml import REQUIRED, RUNNER, ROOT  # noqa: E402

FAKE_RECORDER = r'''#!%s
import signal, struct, sys, time
stop = []
signal.signal(signal.SIGINT, lambda *a: stop.append(1))
with open(sys.argv[-1], "wb") as f:
    f.write(b"RIFF" + struct.pack("<I", 0) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, 16000, 32000, 2, 16)
            + b"data" + struct.pack("<I", 0))
    while not stop:
        f.write(b"\x01\x00" * 1600)
        f.flush()
        time.sleep(0.05)
'''



class FakeServer(BaseHTTPRequestHandler):
    """An /audio/transcriptions server: answers with the language it was asked for."""
    requests = []

    def log_message(self, *args):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        language = re.search(rb'name="language"\r\n\r\n([a-z-]+)', body)
        FakeServer.requests.append(self.path)
        data = json.dumps({"text": "fake heard " + (language.group(1).decode() if language else "auto")}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


@pytest.mark.skipif(RUNNER is None and not REQUIRED, reason="Qt 6 qmltestrunner not installed")
def test_dictation_through_the_helper(tmp_path):
    build = os.path.join(ROOT, "build", "stt-qml")
    os.makedirs(build, exist_ok=True)
    path = os.path.join(build, "fake-recorder")
    with open(path, "w") as f:
        f.write(FAKE_RECORDER % sys.executable)
    os.chmod(path, 0o755)
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), FakeServer)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    with open(os.path.join(build, "server.js"), "w") as f:
        f.write(".pragma library\nvar port = %d;\n" % httpd.server_address[1])
    run = tmp_path / "run"
    run.mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(run), XDG_DATA_HOME=str(tmp_path / "data"),
               KDEAICHAT_STT_RECORDER=os.path.join(build, "fake-recorder"), KDEAICHAT_SYSTEMCTL="true",
               KDEAICHAT_UNIT_DIR=str(tmp_path / "units"), KDEAICHAT_WALLET_FOLDER="KDEAIChat-test-nonexistent")
    try:
        result = subprocess.run([RUNNER, "-platform", "offscreen", "-input", os.path.join(ROOT, "tests", "qml", "stt", "dictation.qml")],
                                capture_output=True, text=True, timeout=120, env=env, cwd=ROOT)
    finally:
        httpd.shutdown()
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "Totals: 3 passed" in output, output
    assert FakeServer.requests == ["/v1/audio/transcriptions"]
    assert not os.listdir(run / "kdeaichat"), "the recording was not deleted"
