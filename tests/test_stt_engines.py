"""Speech-to-text engine adapters (helper side) with fake binaries and servers."""
import base64
import json
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from kdeaichat import schedule_wallet, stt_engines, stt_http, stt_settings
from kdeaichat.stt_settings import SettingsError, from_payload

UI = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
TEST_WAV = os.path.join(UI, "voice", "stt-test.wav")
SECRET = "sk-test-SECRET-never-shown"


def script(path, body):
    path.write_text("#!%s\n%s" % (sys.executable, body))
    path.chmod(0o755)
    return str(path)


@pytest.fixture
def home(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path / "run"))
    (tmp_path / "run").mkdir(mode=0o700)
    monkeypatch.setenv("KDEAICHAT_SYSTEMCTL", "true")
    monkeypatch.setenv("KDEAICHAT_UNIT_DIR", str(tmp_path / "units"))
    return tmp_path


class Recorder(BaseHTTPRequestHandler):
    reply = {"text": " hello there "}
    status = 200
    seen = []

    def log_message(self, *a):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        type(self).seen.append({"path": self.path, "headers": dict(self.headers), "body": body})
        data = json.dumps(self.reply if self.status == 200 else {"error": {"message": "bad key"}}).encode()
        self.send_response(self.status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


@pytest.fixture
def server():
    Recorder.seen = []
    Recorder.status = 200
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), Recorder)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    yield "http://127.0.0.1:%d" % httpd.server_address[1]
    httpd.shutdown()


def test_settings_validation():
    s = from_payload({})
    assert (s["engine"], s["model"], s["device"], s["language"]) == ("faster-whisper", "small", "auto", "auto")
    assert from_payload({"sttModel": "~/models/ct2"})["model"] == os.path.expanduser("~/models/ct2")
    for bad in ({"sttEngine": "x"}, {"sttDevice": "tpu"}, {"sttLanguage": "en us"}, {"sttModel": "rel/dir"},
                {"sttRemoteUrl": "ftp://x"}, {"sttRemoteUrl": "https://u:p@host/v1"}, {"sttCommand": "a\nb"}):
        with pytest.raises(SettingsError):
            from_payload(bad)


def test_whisper_cpp_cli(tmp_path):
    model = tmp_path / "ggml-base.bin"
    model.write_bytes(b"ggml")
    log = tmp_path / "args.json"
    binary = script(tmp_path / "whisper-cli", "import json, sys\njson.dump(sys.argv[1:], open(%r, 'w'))\n"
                    "print(' Hello, this is [BLANK_AUDIO] a test.')\n" % str(log))
    s = from_payload({"sttEngine": "whisper-cpp", "sttWhisperCppBinary": binary, "sttWhisperCppModel": str(model),
                      "sttLanguage": "de"})
    reply = stt_engines.transcribe(TEST_WAV, s)
    assert reply["type"] == "stt_result" and reply["text"] == "Hello, this is a test." and reply["engine"] == "whisper-cpp"
    assert json.load(open(log)) == ["-m", str(model), "-f", TEST_WAV, "-nt", "-np", "-l", "de"]
    failing = script(tmp_path / "broken-cli", "import sys\nsys.stderr.write('model load failed\\n')\nsys.exit(3)\n")
    reply = stt_engines.transcribe(TEST_WAV, dict(s, whisper_cpp_binary=failing))
    assert reply["type"] == "stt_error" and "exit 3" in reply["error"] and "model load failed" in reply["error"]
    reply = stt_engines.transcribe(TEST_WAV, dict(s, whisper_cpp_model=str(tmp_path / "missing.bin")))
    assert reply["code"] == "not_configured"


def test_whisper_cpp_server(server):
    s = from_payload({"sttEngine": "whisper-cpp", "sttWhisperCppServer": server, "sttLanguage": "en"})
    reply = stt_engines.transcribe(TEST_WAV, s)
    assert reply["text"] == "hello there"
    seen = Recorder.seen[0]
    assert seen["path"] == "/inference" and b'name="language"\r\n\r\nen' in seen["body"]
    assert b'filename="speech.wav"' in seen["body"] and open(TEST_WAV, "rb").read() in seen["body"]


def test_remote_sends_key_from_the_wallet_never_in_errors(server):
    s = from_payload({"sttEngine": "remote", "sttRemoteUrl": server + "/v1", "sttRemoteModel": "whisper-large-v3",
                      "sttLanguage": "fr"})
    asked = []
    reply = stt_engines.remote(TEST_WAV, s, read_key=lambda entry: asked.append(entry) or SECRET)
    assert reply["text"] == "hello there" and asked == ["stt-remote"]
    seen = Recorder.seen[0]
    assert seen["path"] == "/v1/audio/transcriptions"
    assert seen["headers"]["Authorization"] == "Bearer " + SECRET
    assert b'name="model"\r\n\r\nwhisper-large-v3' in seen["body"] and b'name="language"\r\n\r\nfr' in seen["body"]
    Recorder.status = 401
    with pytest.raises(stt_http.EngineError) as err:
        stt_engines.remote(TEST_WAV, s, read_key=lambda entry: SECRET)
    assert err.value.code == "auth" and "401" in str(err.value) and SECRET not in str(err.value)


def test_remote_wallet_locked(server):
    def locked(entry):
        raise schedule_wallet.WalletUnavailable("wallet locked")

    remote = from_payload({"sttEngine": "remote", "sttRemoteUrl": "https://api.example.invalid/v1"})
    with pytest.raises(stt_http.EngineError) as err:
        stt_engines.remote(TEST_WAV, remote, read_key=locked)
    assert err.value.code == "wallet"
    # A server on this computer works without the wallet (no key sent).
    local = from_payload({"sttEngine": "remote", "sttRemoteUrl": server})
    assert stt_engines.remote(TEST_WAV, local, read_key=locked)["text"] == "hello there"
    assert "Authorization" not in Recorder.seen[-1]["headers"]


def test_remote_unreachable():
    s = from_payload({"sttEngine": "remote", "sttRemoteUrl": "http://127.0.0.1:9"})
    with pytest.raises(stt_http.EngineError) as err:
        stt_engines.remote(TEST_WAV, s, read_key=lambda e: "")
    assert err.value.code == "unreachable"


def test_custom_command(tmp_path):
    folder = tmp_path / "with space"
    folder.mkdir()
    prog = script(folder / "my-stt", "import sys\nprint('heard', sys.argv[1].endswith('.wav'), sys.argv[2])\n")
    s = from_payload({"sttEngine": "command", "sttCommand": "'%s' {wav} --lang={lang}" % prog, "sttLanguage": "en"})
    reply = stt_engines.transcribe(TEST_WAV, s)
    assert reply["text"] == "heard True --lang=en"
    for template, message in (("%s --no-file" % prog, "{wav}"), ("/nonexistent/stt {wav}", "not found"),
                              ("{wav}", "placeholder"), ("'unterminated {wav}", "parsed")):
        reply = stt_engines.transcribe(TEST_WAV, dict(s, command=template))
        assert reply["type"] == "stt_error" and message in reply["error"], (template, reply)
    # No shell: metacharacters are plain arguments.
    marker = tmp_path / "pwned"
    reply = stt_engines.transcribe(TEST_WAV, dict(s, command="'%s' {wav} ; touch %s" % (prog, marker)))
    assert reply["type"] == "stt_result" and not marker.exists()


def test_faster_whisper_adapter_talks_to_the_service(home, monkeypatch):
    sys.path.insert(0, os.path.join(UI, "voice"))
    import stt_service
    import stt_whisper

    class Fake:
        def transcribe(self, audio, **kw):
            return iter([type("S", (), {"text": "from service"})()]), type("I", (), {"language": "en"})()

    from kdeaichat import voice_services
    token = voice_services.ensure_voice_http_token(stt_engines.token_path())
    holder = stt_whisper.ModelHolder(loader=lambda *a: Fake(), cuda_count=lambda: 0)
    srv = stt_service.SttServer(None, 0, token, holder, 60)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    monkeypatch.setenv("KDEAICHAT_STT_PORT", str(srv.server_address[1]))
    try:
        reply = stt_engines.transcribe(TEST_WAV, from_payload({"sttModel": "tiny"}))
        assert reply["type"] == "stt_result" and reply["text"] == "from service" and reply["device"] == "cpu"
    finally:
        srv.shutdown()
        srv.server_close()


def test_faster_whisper_not_installed(home, monkeypatch):
    # Nothing listens: it tries to start the socket unit once, then says what to do.
    monkeypatch.setenv("KDEAICHAT_STT_PORT", "9")
    started = []
    with pytest.raises(stt_http.EngineError) as err:
        stt_engines.faster_whisper(TEST_WAV, from_payload({}), start_socket=lambda: started.append(1) or 0)
    assert started == [1] and err.value.code == "not_installed"


def test_engine_listing(home, tmp_path, monkeypatch):
    venv = tmp_path / "venv"
    bindir = tmp_path / "bin"
    bindir.mkdir()
    monkeypatch.setenv("PATH", str(bindir))
    s = from_payload({"venv": str(venv)})
    rows = {r["id"]: r for r in stt_engines.available(s)}
    assert [r["available"] for r in rows.values()] == [False, False, False, False]
    assert rows["whisper-cpp"]["reason"] == "whisper-cli not found"
    # A venv with faster-whisper, whisper-cli with a model, a URL and a command.
    (venv / "bin").mkdir(parents=True)
    (venv / "bin" / "python3").write_text("")
    (venv / "lib" / "python3.12" / "site-packages" / "faster_whisper").mkdir(parents=True)
    cli = script(bindir / "whisper-cli", "print('x')\n")
    model = tmp_path / "ggml.bin"
    model.write_bytes(b"x")
    s = from_payload({"venv": str(venv), "sttWhisperCppModel": str(model), "sttRemoteUrl": "https://api.groq.com/openai/v1",
                      "sttCommand": cli + " {wav}"})
    rows = {r["id"]: r for r in stt_engines.available(s)}
    assert all(r["available"] for r in rows.values()), rows
    assert rows["whisper-cpp"]["binary"] == cli


def helper(command, payload, env):
    encoded = base64.b64encode(json.dumps(payload).encode()).decode()
    out = subprocess.run([sys.executable, os.path.join(UI, "kde_ai_helper.py"), command, encoded], env=env,
                         capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stdout + out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


def test_helper_commands(home, tmp_path):
    env = dict(os.environ)
    prog = script(tmp_path / "echo-stt", "print('Hello, this is a speech test.')\n")
    reply = helper("stt_test", {"sttEngine": "command", "sttCommand": prog + " {wav}"}, env)
    assert reply["type"] == "stt_result" and reply["text"] == reply["expected"]
    assert helper("stt_engines", {}, env)["type"] == "stt_engines"
    assert helper("stt_transcribe", {"sttEngine": "command", "sttCommand": prog + " {wav}", "wav": TEST_WAV}, env)["text"]
    assert helper("stt_transcribe", {"wav": "/nonexistent.wav"}, env)["code"] == "bad_request"
    assert helper("stt_engines", {"sttEngine": "bogus"}, env)["code"] == "bad_settings"
    assert helper("stt_stop", {}, env) == {"type": "stt_stopped", "recording": False}
    # The run folder stays private.
    assert os.stat(os.path.join(str(home / "run"), "kdeaichat")).st_mode & 0o777 == 0o700
