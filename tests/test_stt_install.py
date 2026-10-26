"""stt_install runs the setup script without a terminal and reports one line; engine rows say what can be picked."""
import os
import sys

UI = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)
from kdeaichat import stt_engines, stt_install  # noqa: E402
from kdeaichat.stt_settings import from_payload  # noqa: E402


def _script(tmp_path, body):
    path = tmp_path / "setup.sh"
    path.write_text("#!/bin/bash\n" + body)
    return str(path)


def test_install_reports_success_and_mode(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    log = tmp_path / "args"
    monkeypatch.setenv("KDEAICHAT_STT_SETUP", _script(tmp_path, 'echo "$@ $NON_INTERACTIVE" > %s\n'
                       'echo \'{"type":"setup_status","status":"installing_gpu","percent":70}\'\n'
                       'echo \'{"type":"setup_status","status":"done","percent":100}\'\n' % log))
    reply = stt_install.install("gpu")
    assert reply == {"type": "stt_installed", "ok": True, "venv": str(tmp_path / "data" / "kdeaichat" / "venv"), "mode": "gpu"}
    assert log.read_text().split() == [str(tmp_path / "data" / "kdeaichat" / "venv"), "gpu", "1"]


def test_install_failure_gives_the_error_and_log_tail(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    monkeypatch.setenv("KDEAICHAT_STT_SETUP", _script(tmp_path, 'echo "pip: no network"\n'
                       'echo \'{"type":"setup_error","error":"Installing failed."}\'\nexit 1\n'))
    reply = stt_install.install("weird-mode")
    assert reply["ok"] is False and reply["error"] == "Installing failed." and "pip: no network" in reply["log"]


def test_engine_rows_say_what_can_be_picked(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path))
    monkeypatch.setenv("PATH", str(tmp_path / "empty"))
    rows = {r["id"]: r for r in stt_engines.available(from_payload({}))}
    assert rows["faster-whisper"]["available"] is False
    assert rows["faster-whisper"]["selectable"] is stt_engines.can_make_venv()
    assert rows["whisper-cpp"]["selectable"] is False and rows["whisper-cpp"]["reason"] == "whisper-cli not found"
    assert rows["remote"]["selectable"] is True and rows["remote"]["available"] is False
    assert rows["command"]["selectable"] is True
    rows = {r["id"]: r for r in stt_engines.available(from_payload({"sttWhisperCppServer": "http://127.0.0.1:8080"}))}
    assert rows["whisper-cpp"]["available"] and rows["whisper-cpp"]["selectable"]
