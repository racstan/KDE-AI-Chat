"""Speech-to-text through the speech server (helper side) against a fake server.

Speech Note is the default engine and runs through speechnote_* (tests/test_speechnote.py); the engines
of earlier builds (faster-whisper, Parakeet, whisper.cpp, custom command) are gone and must be refused.
"""
import base64
import json
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from kdeaichat import schedule_wallet, stt_engines, stt_http
from kdeaichat.stt_settings import ENGINES, SettingsError, from_payload

UI = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
TEST_WAV = os.path.join(UI, "voice", "stt-test.wav")
SECRET = "sk-test-SECRET-never-shown"


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


def test_only_speech_note_and_the_speech_server_remain():
    assert ENGINES == ("speechnote", "remote")
    assert from_payload({})["engine"] == "speechnote"
    assert from_payload({"sttLanguage": "de", "sttRemoteUrl": "http://localhost:8000/v1/"})["remote_url"] == "http://localhost:8000/v1"
    for gone in ("parakeet", "faster-whisper", "whisper-cpp", "command"):
        with pytest.raises(SettingsError):
            from_payload({"sttEngine": gone})


def test_settings_validation():
    for bad in ({"sttEngine": "x"}, {"sttLanguage": "en us"}, {"sttRemoteUrl": "ftp://x"},
                {"sttRemoteUrl": "https://u:p@host/v1"}, {"sttRemoteModel": "a\nb"}):
        with pytest.raises(SettingsError):
            from_payload(bad)


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
    assert b'filename="speech.wav"' in seen["body"] and open(TEST_WAV, "rb").read() in seen["body"]
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


def test_transcribe_refuses_speech_note():
    # Speech Note listens through the speechnote_* commands, not through stt_*.
    reply = stt_engines.transcribe(TEST_WAV, from_payload({}))
    assert reply["type"] == "stt_error" and reply["code"] == "bad_request"


def helper(command, payload, env):
    encoded = base64.b64encode(json.dumps(payload).encode()).decode()
    out = subprocess.run([sys.executable, os.path.join(UI, "kde_ai_helper.py"), command, encoded], env=env,
                         capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stdout + out.stderr
    return json.loads(out.stdout.strip().splitlines()[-1])


def test_helper_commands(home, server):
    env = dict(os.environ, KDEAICHAT_WALLET_FOLDER="KDEAIChat-test-nonexistent")
    Recorder.reply = {"text": "Hello, this is a speech test."}
    try:
        payload = {"sttEngine": "remote", "sttRemoteUrl": server + "/v1"}
        reply = helper("stt_test", payload, env)
        assert reply["type"] == "stt_result" and reply["text"] == reply["expected"], reply
        assert helper("stt_transcribe", dict(payload, wav=TEST_WAV), env)["text"]
    finally:
        Recorder.reply = {"text": " hello there "}
    assert helper("stt_transcribe", {"wav": "/nonexistent.wav"}, env)["code"] == "bad_request"
    assert helper("stt_test", {"sttEngine": "parakeet"}, env)["code"] == "bad_settings"
    assert helper("stt_stop", {}, env) == {"type": "stt_stopped", "recording": False}
    # The removed commands are gone.
    for name in ("stt_engines", "stt_models", "stt_setup_size", "stt_download_model", "stt_sync_units", "stt_service_status",
                 "voice_data", "voice_data_remove", "tts_probe", "tts_piper_voices", "stt_install", "tts_neural_status"):
        out = subprocess.run([sys.executable, os.path.join(UI, "kde_ai_helper.py"), name, ""], env=env,
                             capture_output=True, text=True, timeout=60)
        assert "Unknown command" in out.stdout, name
    # The run folder stays private.
    assert os.stat(os.path.join(str(home / "run"), "kdeaichat")).st_mode & 0o777 == 0o700
