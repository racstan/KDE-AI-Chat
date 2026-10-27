"""Read aloud through a speech server (kdeaichat/tts.py) against a fake /audio/speech server.

Piper, the custom command and the Kokoro "natural voice" are gone: tts_synthesize refuses them. The removal of
the old units is tested in tests/test_voice_legacy.py."""
import base64
import http.server
import json
import os
import stat
import subprocess
import sys
import threading

import pytest

UI = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)

from kdeaichat import schedule_wallet, tts  # noqa: E402

WAV = b"RIFF\x24\x00\x00\x00WAVEfmt " + b"\x10\x00\x00\x00\x01\x00\x01\x00\x80\x3e\x00\x00\x00\x7d\x00\x00\x02\x00\x10\x00" + b"data\x00\x00\x00\x00"


@pytest.fixture(autouse=True)
def tts_dir(tmp_path, monkeypatch):
    folder = tmp_path / "tts-out"
    monkeypatch.setenv("KDEAICHAT_TTS_DIR", str(folder))
    return folder


class SpeechServer(http.server.BaseHTTPRequestHandler):
    requests = []
    status = 200

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        SpeechServer.requests.append({"path": self.path, "body": body, "auth": self.headers.get("Authorization")})
        self.send_response(SpeechServer.status)
        self.end_headers()
        self.wfile.write(WAV if SpeechServer.status == 200 else b'{"error": "bad key"}')

    def log_message(self, *args):
        pass


@pytest.fixture
def server():
    SpeechServer.requests = []
    SpeechServer.status = 200
    httpd = http.server.HTTPServer(("127.0.0.1", 0), SpeechServer)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{httpd.server_port}/v1"
    httpd.shutdown()


def test_remote_server_gets_the_key_from_the_wallet_not_the_payload(server, monkeypatch):
    monkeypatch.setattr(schedule_wallet, "read_key", lambda entry: "sk-test" if entry == "tts-remote" else "")
    result = tts.synthesize({"engine": "remote", "text": "Hello", "options": {
        "voiceTtsRemoteUrl": server + "/", "voiceTtsRemoteModel": "kokoro", "voiceTtsRemoteVoice": "af_bella", "voiceTtsRemoteSpeed": 1.5}})
    assert result["ok"], result
    request = SpeechServer.requests[0]
    assert request["path"] == "/v1/audio/speech"
    assert request["body"] == {"model": "kokoro", "input": "Hello", "voice": "af_bella", "response_format": "wav", "speed": 1.5}
    assert request["auth"] == "Bearer sk-test"


def test_remote_without_wallet_or_with_a_refused_key(server, monkeypatch):
    def locked(entry):
        raise schedule_wallet.WalletUnavailable("wallet locked")
    monkeypatch.setattr(schedule_wallet, "read_key", locked)
    assert tts.synthesize({"engine": "remote", "text": "Hi", "options": {"voiceTtsRemoteUrl": server}})["ok"]
    assert SpeechServer.requests[0]["auth"] is None
    SpeechServer.status = 401
    error = tts.synthesize({"engine": "remote", "text": "Hi", "options": {"voiceTtsRemoteUrl": server}})["error"]
    assert error.startswith("the server answered 401 (is the API key saved?)")
    assert tts.synthesize({"engine": "remote", "text": "Hi", "options": {"voiceTtsRemoteUrl": "file:///etc/passwd"}})["error"] \
        == "the server URL must start with http:// or https://"


def test_cleanup_only_removes_its_own_wav_files(tmp_path):
    folder = tts.out_dir()
    played = os.path.join(folder, "speech-1.wav")
    open(played, "wb").write(WAV)
    outside = tmp_path / "keep.wav"
    outside.write_bytes(WAV)
    assert tts.cleanup(str(outside)) == 0 and outside.exists()
    assert tts.cleanup(played) == 1 and not os.path.exists(played)
    old = os.path.join(folder, "speech-2.wav")
    open(old, "wb").write(WAV)
    os.utime(old, (1, 1))
    fresh = os.path.join(folder, "speech-3.wav")
    open(fresh, "wb").write(WAV)
    assert tts.cleanup() == 1
    assert os.path.exists(fresh)
    assert stat.S_IMODE(os.stat(folder).st_mode) == 0o700


def test_removed_engines_are_refused():
    for engine in ("piper", "command", "neural"):
        assert tts.synthesize({"engine": engine, "text": "hi", "options": {}}) == {"ok": False, "error": "unknown read-aloud engine"}
    assert tts.synthesize({"engine": "remote", "text": "  "})["error"] == "nothing to read"
    assert set(tts.COMMANDS) == {"tts_synthesize", "tts_cleanup"}


def test_helper_runs_the_commands(tmp_path, server):
    payload = base64.b64encode(json.dumps({"engine": "remote", "text": "hi",
                                           "options": {"voiceTtsRemoteUrl": server}}).encode()).decode()
    env = dict(os.environ, KDEAICHAT_TTS_DIR=str(tmp_path / "out"), KDEAICHAT_WALLET_FOLDER="KDEAIChat-test-nonexistent")
    out = subprocess.run([sys.executable, os.path.join(UI, "kde_ai_helper.py"), "tts_synthesize", payload],
                         capture_output=True, text=True, env=env, timeout=30)
    result = json.loads(out.stdout)
    assert result["ok"] and result["path"].startswith(str(tmp_path / "out")), result


def test_widget_wiring_for_read_aloud():
    """Voice errors reach a notification (the old fileReaderDs path is gone),
    the widget never starts the old TTS service, and the startup cleanup runs."""
    ui = os.path.join(UI)
    main = open(os.path.join(ui, "main.qml")).read()
    voice = open(os.path.join(ui, "VoiceManager.qml")).read()
    commands = open(os.path.join(ui, "chat", "HelperCommands.qml")).read()
    assert "fileReaderDs" not in main
    assert 'notifier.sender(voiceManager.errorTitle' in main
    assert "helperCommands.cleanupLegacy()" in main
    assert "voice_startup" in commands
    for unit in ("kde-ai-tts.service", "kde-ai-stt.service", "kde-ai-stt.socket"):
        assert unit in commands
    assert "9016" not in voice
    assert 'lang_code: "a"' not in voice
