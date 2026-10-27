"""The natural read-aloud voice: service (fake model), worker, setup commands."""
import hashlib
import http.server
import json
import os
import socket
import sys
import threading
import time
import wave

import pytest

UI = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)
sys.path.insert(0, os.path.join(UI, "voice"))
import tts_service  # noqa: E402
from kdeaichat import tts_neural, tts_worker  # noqa: E402


def _short_dir():
    # Unix socket paths are limited to ~100 characters.
    import tempfile
    d = tempfile.mkdtemp(prefix="kt")
    os.chmod(d, 0o700)
    return d


@pytest.fixture
def folder():
    d = _short_dir()
    yield d
    import shutil
    shutil.rmtree(d, ignore_errors=True)


def _ask(path, data):
    return tts_worker._request(path, data, 5)


def _try(sock):
    try:
        return _ask(sock, {"op": "status"}).get("ok") is True
    except OSError:
        return False


def _serve(folder, idle=30, extra=()):
    sock = os.path.join(folder, "t.sock")
    result = {}
    t = threading.Thread(target=lambda: result.setdefault("rc", tts_service.main(
        ["--socket", sock, "--out-dir", folder, "--idle-timeout", str(idle), "--fake", *extra])))
    t.start()
    for _ in range(100):
        if os.path.exists(sock):
            break
        time.sleep(0.05)
    return sock, t, result


def test_service_synthesizes_wav_with_pause(folder):
    sock, t, result = _serve(folder)
    out = os.path.join(folder, "a.wav")
    r = _ask(sock, {"op": "synthesize", "text": "hello", "out": out, "pause_ms": 500, "voice": "af_heart"})
    assert r["ok"] and r["path"] == os.path.realpath(out)
    with wave.open(out) as w:
        seconds = w.getnframes() / w.getframerate()
    assert abs(seconds - (0.3 + 0.5)) < 0.02 and abs(r["seconds"] - seconds) < 0.01
    assert _ask(sock, {"op": "status"})["loaded"] is True
    _ask(sock, {"op": "stop"})
    t.join(5)
    assert result["rc"] == 0 and not os.path.exists(sock)


def test_service_rejects_bad_requests(folder):
    sock, t, _ = _serve(folder)
    other = os.path.join(folder, "sub")
    os.mkdir(other)
    for out in (os.path.join(other, "x.wav"), os.path.join(folder, "x.txt"), "/etc/x.wav"):
        r = _ask(sock, {"op": "synthesize", "text": "hi", "out": out})
        assert r["ok"] is False and "speech folder" in r["error"]
    assert not _ask(sock, {"op": "synthesize", "text": "  ", "out": os.path.join(folder, "x.wav")})["ok"]
    assert not _ask(sock, {"op": "synthesize", "text": "hi", "voice": "../x", "out": os.path.join(folder, "x.wav")})["ok"]
    assert not _ask(sock, {"op": "nope"})["ok"]
    _ask(sock, {"op": "stop"})
    t.join(5)


def test_service_exits_when_idle_and_cleans_socket(folder):
    sock, t, result = _serve(folder, idle=0.5)
    t.join(10)
    assert not t.is_alive() and result["rc"] == 0
    assert not os.path.exists(sock)


def test_service_replaces_stale_socket_and_refuses_open_folder(folder):
    stale = os.path.join(folder, "t.sock")
    s = socket.socket(socket.AF_UNIX)
    s.bind(stale)
    s.close()  # nothing listens: a crashed copy
    sock, t, _ = _serve(folder)
    for _ in range(100):
        if _try(sock):
            break
        time.sleep(0.05)
    assert _ask(sock, {"op": "status"})["ok"]
    _ask(sock, {"op": "stop"})
    t.join(5)
    os.chmod(folder, 0o755)
    assert tts_service.main(["--socket", stale, "--out-dir", folder, "--fake"]) == 1


def _fake_install(data_home):
    root = os.path.join(data_home, "kdeaichat")
    venv = os.path.join(root, "tts-venv")
    os.makedirs(os.path.join(venv, "bin"))
    os.symlink(sys.executable, os.path.join(venv, "bin", "python3"))
    for pkg in ("kokoro_onnx", "onnxruntime"):
        os.makedirs(os.path.join(venv, "lib", "python3.99", "site-packages", pkg))
    models = os.path.join(root, "tts-models", "kokoro")
    os.makedirs(models)
    for name in ("kokoro-v1.0.fp16.onnx", "voices-v1.0.bin"):
        open(os.path.join(models, name), "wb").write(b"x")


@pytest.fixture
def data_home(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    return str(tmp_path / "data")


def test_worker_spawns_service_and_synthesizes(data_home, folder, monkeypatch):
    _fake_install(data_home)
    monkeypatch.setenv("KDEAICHAT_TTS_FAKE", "1")
    out = os.path.join(folder, "s1.wav")
    try:
        reply = tts_worker.synthesize("hello there", {"voiceTtsNeuralSpeed": 1}, out, 200)
        assert reply["ok"] and os.path.getsize(out) > 44
        assert tts_worker.alive(folder) and tts_worker.status(folder)["loaded"]
        # a second call reuses the running service
        pid = tts_worker.status(folder)["pid"]
        tts_worker.synthesize("again", {}, os.path.join(folder, "s2.wav"))
        assert tts_worker.status(folder)["pid"] == pid
    finally:
        assert tts_worker.stop(folder)
    for _ in range(100):
        if not tts_worker.alive(folder):
            break
        time.sleep(0.05)
    assert not os.path.exists(tts_worker.socket_path(folder))


def test_worker_not_installed_codes(data_home, folder):
    with pytest.raises(tts_worker.TtsError) as e:
        tts_worker.synthesize("hi", {}, os.path.join(folder, "a.wav"))
    assert e.value.code == "not_installed"
    _fake_install(data_home)
    import shutil
    shutil.rmtree(tts_neural.models_dir())
    with pytest.raises(tts_worker.TtsError) as e:
        tts_worker.synthesize("hi", {}, os.path.join(folder, "a.wav"))
    assert e.value.code == "not_installed"


def test_estimate_and_status(data_home, monkeypatch, folder):
    monkeypatch.setenv("KDEAICHAT_TTS_DIR", folder)
    e = tts_neural.estimate(True)
    assert e["program_mb"] == 52 and e["gpu_mb"] == 1554 and e["model_mb"] == 206
    assert e["total_mb"] == 52 + 1554 + 206
    st = tts_neural.status()
    assert st["installed"] is False and st["running"] is False
    _fake_install(data_home)
    e = tts_neural.estimate(False)
    assert e["total_mb"] == 0
    st = tts_neural.status()
    assert st["installed"] is True and st["model"].endswith("kokoro-v1.0.fp16.onnx")


class _Handler(http.server.BaseHTTPRequestHandler):
    files = {}

    def do_GET(self):
        body = self.files.get(self.path.lstrip("/"))
        self.send_response(200 if body is not None else 404)
        self.end_headers()
        self.wfile.write(body or b"")

    def log_message(self, *a):
        pass


@pytest.fixture
def server(monkeypatch):
    srv = http.server.HTTPServer(("127.0.0.1", 0), _Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    monkeypatch.setenv("KDEAICHAT_TTS_MODEL_URL", "http://127.0.0.1:%d/" % srv.server_port)
    yield _Handler
    srv.shutdown()
    srv.server_close()


def test_download_checks_checksum(data_home, server, monkeypatch):
    good = b"model-bytes"
    monkeypatch.setattr(tts_neural, "FILES", {"m.onnx": (len(good), hashlib.sha256(good).hexdigest())})
    server.files = {"m.onnx": b"damaged-bts"}
    with pytest.raises(RuntimeError, match="checksum"):
        tts_neural.download_models()
    names = os.listdir(tts_neural.models_dir())
    assert names == []  # the bad download is not kept
    server.files = {"m.onnx": good}
    tts_neural.download_models()
    assert open(os.path.join(tts_neural.models_dir(), "m.onnx"), "rb").read() == good


def test_install_with_setup_script(data_home, server, monkeypatch, tmp_path):
    script = tmp_path / "setup.sh"
    script.write_text('#!/bin/bash\nmkdir -p "$1/bin" "$1/lib/python3.99/site-packages/kokoro_onnx" '
                      '"$1/lib/python3.99/site-packages/onnxruntime"\ntouch "$1/bin/python3"\n')
    monkeypatch.setenv("KDEAICHAT_TTS_SETUP", str(script))
    good = b"abc"
    monkeypatch.setattr(tts_neural, "FILES", {"kokoro-v1.0.fp16.onnx": (3, hashlib.sha256(good).hexdigest()),
                                              "voices-v1.0.bin": (3, hashlib.sha256(good).hexdigest())})
    server.files = {"kokoro-v1.0.fp16.onnx": good, "voices-v1.0.bin": good}
    r = tts_neural.install()
    assert r["ok"] is True and tts_neural.packages_installed() and tts_neural.model_files()
    # a failing script reports a log
    script.write_text("#!/bin/bash\necho boom >&2\nexit 3\n")
    import shutil
    shutil.rmtree(tts_neural.venv_dir())
    r = tts_neural.install()
    assert r["ok"] is False and "boom" in r["log"]


def test_install_reports_failed_download(data_home, server, monkeypatch, tmp_path):
    script = tmp_path / "setup.sh"
    script.write_text('#!/bin/bash\nmkdir -p "$1/lib/python3.99/site-packages/kokoro_onnx" '
                      '"$1/lib/python3.99/site-packages/onnxruntime"\n')
    monkeypatch.setenv("KDEAICHAT_TTS_SETUP", str(script))
    server.files = {}
    r = tts_neural.install()
    assert r["ok"] is False and "Downloading" in r["error"]


def test_remove_deletes_venv_and_models(data_home, folder, monkeypatch, capsys):
    monkeypatch.setenv("KDEAICHAT_TTS_DIR", folder)
    _fake_install(data_home)
    r = tts_neural.remove()
    assert r["ok"] and len(r["removed"]) == 2
    assert not os.path.exists(tts_neural.venv_dir()) and not os.path.exists(tts_neural.models_dir())
    tts_neural.cmd_tts_neural_status({})
    assert json.loads(capsys.readouterr().out)["installed"] is False
