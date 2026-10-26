"""Read-aloud engines that write sound files (kdeaichat/tts.py), with a fake
piper, a fake command and a fake /audio/speech server; and the one-time
removal of the old kde-ai-tts.service (kdeaichat/voice_legacy.py)."""
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

from kdeaichat import schedule_wallet, tts, voice_legacy  # noqa: E402

WAV = b"RIFF\x24\x00\x00\x00WAVEfmt " + b"\x10\x00\x00\x00\x01\x00\x01\x00\x80\x3e\x00\x00\x00\x7d\x00\x00\x02\x00\x10\x00" + b"data\x00\x00\x00\x00"


@pytest.fixture(autouse=True)
def tts_dir(tmp_path, monkeypatch):
    folder = tmp_path / "tts-out"
    monkeypatch.setenv("KDEAICHAT_TTS_DIR", str(folder))
    return folder


def write_script(path, body):
    path.write_text("#!/usr/bin/env python3\n" + body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return str(path)


def test_piper_gets_the_text_on_stdin_and_the_voice_options(tmp_path):
    log = tmp_path / "piper-args.json"
    piper = write_script(tmp_path / "piper", f"""
import json, sys
args = sys.argv[1:]
out = args[args.index("--output_file") + 1]
json.dump({{"args": args, "text": sys.stdin.read()}}, open({str(log)!r}, "w"))
open(out, "wb").write({WAV!r})
""")
    model = tmp_path / "en_US-test.onnx"
    model.write_bytes(b"onnx")
    result = tts.synthesize({"engine": "piper", "text": "Hello there.", "options": {
        "voiceTtsPiperBinary": piper, "voiceTtsPiperModel": str(model), "voiceTtsPiperSpeed": 2, "voiceTtsPiperSpeaker": 3}})
    assert result["ok"], result
    assert open(result["path"], "rb").read() == WAV
    seen = json.loads(log.read_text())
    assert seen["text"] == "Hello there."
    args = seen["args"]
    assert args[args.index("--model") + 1] == str(model)
    assert args[args.index("--length_scale") + 1] == "0.500"
    assert args[args.index("--speaker") + 1] == "3"


def test_piper_missing_binary_or_voice_is_a_clear_error(tmp_path, monkeypatch):
    monkeypatch.setenv("PATH", str(tmp_path))
    result = tts.synthesize({"engine": "piper", "text": "Hi", "options": {"voiceTtsPiperModel": str(tmp_path / "x.onnx")}})
    assert result == {"ok": False, "error": "Piper is not installed (no piper program found)"}
    piper = write_script(tmp_path / "piper", "pass\n")
    result = tts.synthesize({"engine": "piper", "text": "Hi", "options": {"voiceTtsPiperModel": str(tmp_path / "x.onnx")}})
    assert result == {"ok": False, "error": "the Piper voice file was not found"}
    assert tts.find_piper() == piper
    assert not os.listdir(tts.out_dir()), "a failed run leaves no file behind"


def test_probe_reports_piper(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("PATH", str(tmp_path))
    monkeypatch.setenv("HOME", str(tmp_path))
    tts.cmd_tts_probe({})
    assert json.loads(capsys.readouterr().out) == {"ok": True, "piper": ""}
    piper = write_script(tmp_path / "piper", "pass\n")
    tts.cmd_tts_probe({})
    assert json.loads(capsys.readouterr().out) == {"ok": True, "piper": piper}


def test_custom_command_wav_on_stdout_or_to_output(tmp_path):
    to_stdout = write_script(tmp_path / "say-stdout", f"""
import sys
assert sys.stdin.read() == "Read me"
sys.stdout.buffer.write({WAV!r})
""")
    result = tts.synthesize({"engine": "command", "text": "Read me", "options": {"voiceTtsCommand": to_stdout + " --fast"}})
    assert result["ok"], result
    assert open(result["path"], "rb").read() == WAV

    to_file = write_script(tmp_path / "say file", f"""
import sys
open(sys.argv[sys.argv.index("-w") + 1], "wb").write({WAV!r})
""")
    result = tts.synthesize({"engine": "command", "text": "Read me", "options": {"voiceTtsCommand": "'" + to_file + "' -w {output}"}})
    assert result["ok"], result


def test_custom_command_runs_without_a_shell(tmp_path):
    marker = tmp_path / "injected"
    result = tts.synthesize({"engine": "command", "text": "x", "options": {"voiceTtsCommand": f"true; touch {marker}"}})
    assert not result["ok"]
    assert not marker.exists()


def test_custom_command_errors(tmp_path):
    assert tts.synthesize({"engine": "command", "text": "x", "options": {"voiceTtsCommand": ""}})["error"] == "no command is set"
    bad = write_script(tmp_path / "bad", "import sys\nsys.stderr.write('voice not found\\n')\nsys.exit(2)\n")
    assert tts.synthesize({"engine": "command", "text": "x", "options": {"voiceTtsCommand": bad}})["error"] == "voice not found"
    silent = write_script(tmp_path / "silent", "print('not audio')\n")
    assert tts.synthesize({"engine": "command", "text": "x", "options": {"voiceTtsCommand": silent}})["error"] \
        == "the engine did not write a WAV file"
    assert tts.synthesize({"engine": "nope", "text": "x"})["error"] == "unknown read-aloud engine"
    assert tts.synthesize({"engine": "command", "text": "  "})["error"] == "nothing to read"


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


def test_helper_runs_the_commands(tmp_path):
    payload = base64.b64encode(json.dumps({"engine": "command", "text": "hi",
                                           "options": {"voiceTtsCommand": "printf RIFF0000WAVE"}}).encode()).decode()
    env = dict(os.environ, KDEAICHAT_TTS_DIR=str(tmp_path / "out"))
    out = subprocess.run([sys.executable, os.path.join(UI, "kde_ai_helper.py"), "tts_synthesize", payload],
                         capture_output=True, text=True, env=env, timeout=30)
    result = json.loads(out.stdout)
    assert result["ok"] and result["path"].startswith(str(tmp_path / "out"))


def test_old_tts_service_is_removed_once(tmp_path, monkeypatch):
    units = tmp_path / "units"
    units.mkdir()
    (units / "kde-ai-tts.service").write_text("[Service]\n")
    (units / "kde-ai-stt.service").write_text("[Service]\n")
    monkeypatch.setenv("KDEAICHAT_UNIT_DIR", str(units))
    calls = []
    done = voice_legacy.cleanup_legacy_tts(run=lambda args: calls.append(args) or 0)
    assert done["unit"] and done["changed"]
    assert calls == [["disable", "--now", "kde-ai-tts.service"], ["daemon-reload"], ["reset-failed", "kde-ai-tts.service"]]
    assert not (units / "kde-ai-tts.service").exists()
    assert (units / "kde-ai-stt.service").exists(), "the speech-to-text unit is not ours to remove"
    calls.clear()
    again = voice_legacy.cleanup_legacy_tts(run=lambda args: calls.append(args) or 0)
    assert calls == [] and not again["unit"]


def test_old_tts_server_process_is_stopped(tmp_path, monkeypatch):
    monkeypatch.setenv("KDEAICHAT_UNIT_DIR", str(tmp_path))
    fake = tmp_path / "voice_helper.py"
    fake.write_text("import time\ntime.sleep(60)\n")
    proc = subprocess.Popen([sys.executable, str(fake), "--tts-server", "--token-file", "x"])
    other = subprocess.Popen([sys.executable, str(fake), "--stt-server"])
    try:
        for _ in range(50):
            if proc.pid in voice_legacy._tts_server_pids():
                break
            threading.Event().wait(0.05)
        done = voice_legacy.cleanup_legacy_tts(run=lambda args: 0, allow_kill=True)
        assert done["killed"] == 1
        assert proc.wait(timeout=5) != 0
        assert other.poll() is None
    finally:
        for p in (proc, other):
            if p.poll() is None:
                p.kill()
                p.wait()


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
    assert "kde-ai-tts" not in voice and "9016" not in voice
    assert 'lang_code: "a"' not in voice
