"""The on-demand faster-whisper service (voice/stt_service.py) with a fake model.

Covers socket activation (a passed fd, the systemd LISTEN_FDS protocol and,
when installed, the real ``systemd-socket-activate``), token/host/origin
checks, idle exit (never during a request), lazy loading and reloading when
the requested settings change, CUDA fallback, and no torch anywhere.
"""
import http.client
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import textwrap
import time

import pytest

UI = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
VOICE = os.path.join(UI, "voice")
sys.path.insert(0, VOICE)
import stt_whisper  # noqa: E402
from stt_whisper import ModelHolder, SttError  # noqa: E402

TOKEN = "t" * 40

WRAPPER = textwrap.dedent("""
    import os, sys, time
    sys.path.insert(0, %(voice)r)
    import stt_service, stt_whisper

    class Seg:
        def __init__(self, text): self.text = text

    class Info:
        language = "en"

    class Fake:
        def __init__(self, model, device): self.model, self.device = model, device
        def transcribe(self, audio, **kw):
            delay = float(os.environ.get("FAKE_DELAY", "0"))
            time.sleep(delay)
            return iter([Seg("fake %%s on %%s" %% (os.path.basename(self.model), self.device))]), Info()

    def load(model, device, compute, allow):
        with open(os.environ["FAKE_LOADS"], "a") as f:
            f.write("%%s %%s %%s\\n" %% (model, device, compute))
        return Fake(model, device)

    if os.environ.get("FAKE_SYSTEMD"):
        fd = int(os.environ.pop("FAKE_SYSTEMD"))
        os.dup2(fd, 3)
        os.environ["LISTEN_PID"] = str(os.getpid())
        os.environ["LISTEN_FDS"] = "1"
    holder = stt_whisper.ModelHolder(loader=load, cuda_count=lambda: 0)
    sys.exit(stt_service.main(sys.argv[1:], holder=holder, downloader=lambda m: "/models/" + m))
""")


@pytest.fixture
def env(tmp_path):
    token = tmp_path / "token"
    token.write_text(TOKEN + "\n")
    token.chmod(0o600)
    wrapper = tmp_path / "wrapper.py"
    wrapper.write_text(WRAPPER % {"voice": VOICE})
    wav = tmp_path / "speech.wav"
    shutil.copyfile(os.path.join(VOICE, "stt-test.wav"), wav)
    return {"token": str(token), "wrapper": str(wrapper), "wav": str(wav), "loads": str(tmp_path / "loads"),
            "tmp": tmp_path}


def listening_socket():
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    sock.listen(8)
    return sock


def start(env, extra, *, fds=(), environ=None, idle=30):
    e = dict(os.environ, FAKE_LOADS=env["loads"], **(environ or {}))
    argv = [sys.executable, env["wrapper"], "--token-file", env["token"], "--idle-timeout", str(idle)] + extra
    return subprocess.Popen(argv, env=e, pass_fds=fds, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def call(port, method, path, body=None, headers=None, token=TOKEN, timeout=10):
    h = {"Content-Type": "application/json"}
    if token:
        h["X-KDE-AI-Chat-Token"] = token
    h.update(headers or {})
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        conn.request(method, path, body=json.dumps(body) if body is not None else None, headers=h)
        response = conn.getresponse()
        return response.status, json.loads(response.read() or b"{}")
    finally:
        conn.close()


def loads(env):
    try:
        with open(env["loads"]) as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def stop(proc):
    if proc.poll() is None:
        proc.terminate()
        proc.wait(5)


def test_passed_fd_auth_lazy_load_and_reload_on_settings_change(env):
    sock = listening_socket()
    port = sock.getsockname()[1]
    proc = start(env, ["--listen-fd", str(sock.fileno())], fds=(sock.fileno(),))
    try:
        # Nothing is loaded before the first request.
        assert call(port, "GET", "/status")[1]["loaded"] is False
        assert loads(env) == []
        # Auth: token, host and browsers.
        assert call(port, "GET", "/status", token="")[0] == 403
        assert call(port, "GET", "/status", token="x" * 40)[0] == 403
        assert call(port, "GET", "/status", headers={"Origin": "http://127.0.0.1"})[0] == 403
        assert call(port, "GET", "/status", headers={"Host": "evil.example"})[0] == 403
        assert call(port, "POST", "/transcribe", {"wav": env["wav"]}, token="")[0] == 403
        assert loads(env) == []

        status, reply = call(port, "POST", "/transcribe", {"wav": env["wav"], "model": "tiny", "language": "auto"})
        assert status == 200 and reply["type"] == "stt_result", reply
        assert reply["text"] == "fake tiny on cpu" and reply["device"] == "cpu" and reply["language"] == "en"
        # Same settings: no reload ("auto" is the CPU here). Other model: reload.
        call(port, "POST", "/transcribe", {"wav": env["wav"], "model": "tiny", "device": "cpu"})
        assert loads(env) == ["tiny cpu int8"]
        reply = call(port, "POST", "/transcribe", {"wav": env["wav"], "model": "base"})[1]
        assert reply["text"] == "fake base on cpu"
        assert loads(env) == ["tiny cpu int8", "base cpu int8"]
        status = call(port, "GET", "/status")[1]
        assert status["model"] == "base" and status["loads"] == 2 and status["loaded"] is True

        # Validation errors come back as stt_error with a code; the service keeps running.
        assert call(port, "POST", "/transcribe", {"wav": "/nonexistent.wav"})[1]["code"] == "bad_wav"
        assert call(port, "POST", "/transcribe", {"wav": env["wav"], "model": "huge"})[1]["code"] == "bad_model"
        assert call(port, "POST", "/transcribe", {"wav": env["wav"], "language": "x y"})[1]["code"] == "bad_language"
        assert call(port, "POST", "/transcribe", {"wav": env["wav"], "device": "tpu"})[1]["code"] == "bad_device"
        assert call(port, "POST", "/download", {"model": "small"})[1] == {"type": "stt_downloaded", "model": "small",
                                                                          "path": "/models/small"}
        assert call(port, "POST", "/unload", {})[1]["type"] == "stt_unloaded"
        assert call(port, "GET", "/status")[1]["loaded"] is False
    finally:
        stop(proc)
        sock.close()


def test_systemd_listen_fds_protocol_and_idle_exit(env):
    sock = listening_socket()
    port = sock.getsockname()[1]
    proc = start(env, [], fds=(sock.fileno(),), environ={"FAKE_SYSTEMD": str(sock.fileno())}, idle=1)
    try:
        assert call(port, "POST", "/transcribe", {"wav": env["wav"], "model": "tiny"})[1]["text"] == "fake tiny on cpu"
        assert proc.wait(timeout=10) == 0
        assert "idle, exiting" in proc.stdout.read()
    finally:
        stop(proc)
    # The socket stays with its owner (systemd): connections queue until the next start.
    proc = start(env, [], fds=(sock.fileno(),), environ={"FAKE_SYSTEMD": str(sock.fileno())}, idle=1)
    try:
        assert call(port, "GET", "/status")[1]["loaded"] is False  # a fresh process loads lazily again
    finally:
        stop(proc)
        sock.close()


def test_idle_exit_waits_for_a_running_request(env):
    sock = listening_socket()
    port = sock.getsockname()[1]
    proc = start(env, ["--listen-fd", str(sock.fileno())], fds=(sock.fileno(),), environ={"FAKE_DELAY": "2"}, idle=0.5)
    try:
        started = time.monotonic()
        status, reply = call(port, "POST", "/transcribe", {"wav": env["wav"], "model": "tiny"})
        assert status == 200 and reply["type"] == "stt_result" and time.monotonic() - started >= 2
        assert proc.wait(timeout=10) == 0
    finally:
        stop(proc)
        sock.close()


@pytest.mark.skipif(not shutil.which("systemd-socket-activate"), reason="systemd-socket-activate not installed")
def test_real_systemd_socket_activate(env):
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    e = dict(os.environ, FAKE_LOADS=env["loads"])
    proc = subprocess.Popen(["systemd-socket-activate", "-l", "127.0.0.1:%d" % port, "-E", "FAKE_LOADS=" + env["loads"],
                             sys.executable, env["wrapper"],
                             "--token-file", env["token"], "--idle-timeout", "1"], env=e,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        for _ in range(100):
            try:
                reply = call(port, "POST", "/transcribe", {"wav": env["wav"], "model": "tiny"})[1]
                break
            except OSError:
                time.sleep(0.05)
        assert reply.get("text") == "fake tiny on cpu", reply
        assert proc.wait(timeout=10) == 0  # the service exited when idle (systemd would keep the socket)
    finally:
        stop(proc)


def test_missing_token_file_refuses_to_start(env, tmp_path):
    sock = listening_socket()
    proc = subprocess.run([sys.executable, env["wrapper"], "--token-file", str(tmp_path / "none"),
                           "--listen-fd", str(sock.fileno())], pass_fds=(sock.fileno(),),
                          env=dict(os.environ, FAKE_LOADS=env["loads"]), capture_output=True, text=True, timeout=20)
    sock.close()
    assert proc.returncode == 1 and "token" in proc.stderr


# --- ModelHolder in-process --------------------------------------------------------------------

class _Model:
    def __init__(self, fail=None):
        self.fail = fail

    def transcribe(self, audio, **kw):
        if self.fail:
            raise RuntimeError(self.fail)
        return iter([type("S", (), {"text": " hi "})()]), type("I", (), {"language": "de"})()


def test_cuda_auto_detection_and_fallback_when_loading_fails(tmp_path, env):
    calls = []

    def loader(model, device, compute, allow):
        calls.append((device, compute))
        if device == "cuda":
            raise RuntimeError("no CUDA driver")
        return _Model()

    holder = ModelHolder(loader=loader, cuda_count=lambda: 1)
    reply = holder.transcribe({"wav": env["wav"], "model": "small"})
    assert calls == [("cuda", "float16"), ("cpu", "int8")]
    assert reply["device"] == "cpu" and "CUDA failed" in reply["note"] and reply["text"] == "hi"
    # Later requests remember CUDA is broken: no second CUDA attempt.
    holder.transcribe({"wav": env["wav"], "model": "small", "device": "cuda"})
    assert calls == [("cuda", "float16"), ("cpu", "int8")]


def test_cuda_fallback_when_transcription_fails(env):
    models = []

    def loader(model, device, compute, allow):
        models.append(device)
        return _Model(fail="libcublas.so.12 is not found" if device == "cuda" else None)

    holder = ModelHolder(loader=loader, cuda_count=lambda: 1)
    reply = holder.transcribe({"wav": env["wav"], "model": "small"})
    assert models == ["cuda", "cpu"] and reply["device"] == "cpu" and "libcublas" in reply["note"]


def test_model_missing_and_folder_models(env, tmp_path):
    def loader(model, device, compute, allow):
        if not allow:
            raise SttError("The speech model 'small' is not downloaded yet", "model_missing")
        return _Model()

    with pytest.raises(SttError) as err:
        ModelHolder(loader=loader, cuda_count=lambda: 0).transcribe({"wav": env["wav"], "model": "small"})
    assert err.value.code == "model_missing"
    folder = tmp_path / "ct2"
    folder.mkdir()
    with pytest.raises(SttError):
        stt_whisper.check_model(str(folder))
    (folder / "model.bin").write_bytes(b"x")
    assert stt_whisper.check_model(str(folder)) == str(folder)
    assert stt_whisper.check_model(str(folder / "model.bin")) == str(folder)
    with pytest.raises(SttError):
        stt_whisper.check_model("relative/folder")


def test_wav_must_be_a_private_regular_file(tmp_path):
    with pytest.raises(SttError):
        stt_whisper.check_wav("relative.wav")
    with pytest.raises(SttError):
        stt_whisper.check_wav(str(tmp_path))


def test_no_torch_anywhere_in_the_stt_service():
    for name in ("stt_service.py", "stt_whisper.py"):
        with open(os.path.join(VOICE, name)) as f:
            source = f.read()
        assert not re.search(r"^\s*(import|from)\s+torch", source, re.M) and "torch.cuda" not in source
    code = "import sys; sys.path.insert(0, %r); import stt_service; print('torch' in sys.modules)" % VOICE
    assert subprocess.run([sys.executable, "-c", code], capture_output=True, text=True).stdout.strip() == "False"
