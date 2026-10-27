"""Dictation recording (the speech server engine): the recorder, stop, cancel and the time limit."""
import json
import os
import struct
import sys
import threading
import time

import pytest

from kdeaichat import stt_record
from kdeaichat.stt_settings import from_payload

# Streams 16 kHz mono PCM like pw-record, with the header sizes left at 0
# (as a recorder killed mid-file leaves them), until SIGINT.
FAKE_RECORDER = r'''#!%s
import os, signal, struct, sys, time
if os.environ.get("FAKE_RECORDER_FAIL"):
    sys.stderr.write("no input device\n"); sys.exit(1)
stop = []
signal.signal(signal.SIGINT, lambda *a: stop.append(1))
with open(sys.argv[-1], "wb") as f:
    f.write(b"RIFF" + struct.pack("<I", 0) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, 16000, 32000, 2, 16)
            + b"data" + struct.pack("<I", 0))
    while not stop:
        f.write(b"\x01\x00" * 1600)  # 0.1 s
        f.flush()
        if os.environ.get("FAKE_RECORDER_SHORT"):
            break
        time.sleep(0.02)
'''


@pytest.fixture
def run_dir(tmp_path, monkeypatch):
    run = tmp_path / "run"
    run.mkdir(mode=0o700)
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(run))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    recorder = tmp_path / "fake-record"
    recorder.write_text(FAKE_RECORDER % sys.executable)
    recorder.chmod(0o755)
    monkeypatch.setenv("KDEAICHAT_STT_RECORDER", str(recorder))
    return run


def _dictate_in_thread(settings, transcribe, **kw):
    out = {}
    thread = threading.Thread(target=lambda: out.update(stt_record.dictate(settings, transcribe, **kw)))
    thread.start()
    for _ in range(200):
        if stt_record.read_state():
            break
        time.sleep(0.02)
    return thread, out


def test_dictate_until_stop_then_transcribe_and_delete(run_dir):
    seen = {}

    def transcribe(wav, settings):
        seen["wav"] = wav
        with open(wav, "rb") as f:
            head = f.read(44)
        seen["sizes"] = struct.unpack("<I", head[4:8])[0], struct.unpack("<I", head[40:44])[0]
        seen["size"] = os.path.getsize(wav)
        seen["mode"] = os.stat(os.path.dirname(wav)).st_mode & 0o777
        return {"type": "stt_result", "text": "dictated", "engine": settings["engine"]}

    thread, out = _dictate_in_thread(from_payload({}), transcribe)
    assert stt_record.dictate(from_payload({}), transcribe)["code"] == "busy"  # one at a time
    time.sleep(0.6)
    assert stt_record.stop() == {"type": "stt_stopping", "cancelled": False}
    thread.join(10)
    assert out["type"] == "stt_result" and out["text"] == "dictated" and out["duration"] >= 0.3
    # The header was repaired, the folder private, and everything is gone afterwards.
    assert seen["sizes"] == (seen["size"] - 8, seen["size"] - 44) and seen["mode"] == 0o700
    assert seen["wav"].startswith(str(run_dir / "kdeaichat") + os.sep) and not os.path.exists(seen["wav"])
    assert stt_record.read_state() is None and stt_record.stop() == {"type": "stt_stopped", "recording": False}


def test_cancel_drops_the_recording(run_dir):
    called = []
    thread, out = _dictate_in_thread(from_payload({}), lambda wav, s: called.append(wav) or {})
    time.sleep(0.4)
    assert stt_record.stop(cancel=True)["cancelled"] is True
    thread.join(10)
    assert out == {"type": "stt_stopped", "cancelled": True} and called == []
    assert os.listdir(run_dir / "kdeaichat") == []


def test_time_limit_and_too_short(run_dir, monkeypatch):
    out = stt_record.dictate(from_payload({}), lambda wav, s: {"type": "stt_result", "text": "x"}, max_seconds=0.5)
    assert out["type"] == "stt_result" and out["text"] == "x"
    monkeypatch.setenv("FAKE_RECORDER_SHORT", "1")
    out = stt_record.dictate(from_payload({}), lambda wav, s: {"type": "stt_result", "text": "never"})
    assert out["text"] == ""  # under 0.3 s: nothing is transcribed


def test_recorder_failure(run_dir, monkeypatch):
    monkeypatch.setenv("FAKE_RECORDER_FAIL", "1")
    out = stt_record.dictate(from_payload({}), lambda wav, s: {})
    assert out["type"] == "stt_error" and out["code"] == "record_failed" and "no input device" in out["error"]


def test_stop_never_signals_a_foreign_process(run_dir):
    os.makedirs(run_dir / "kdeaichat", mode=0o700, exist_ok=True)
    with open(run_dir / "kdeaichat" / stt_record.STATE_NAME, "w") as f:
        json.dump({"pid": os.getpid(), "wav": "/elsewhere/speech.wav", "folder": str(run_dir / "kdeaichat" / "x")}, f)
    assert stt_record.stop() == {"type": "stt_stopped", "recording": False}  # we are alive and were not signalled


def test_recorder_choice(monkeypatch, tmp_path):
    monkeypatch.delenv("KDEAICHAT_STT_RECORDER", raising=False)
    bindir = tmp_path / "bin"
    bindir.mkdir()
    monkeypatch.setenv("PATH", str(bindir))
    assert stt_record.recorder_argv("/x.wav") == []
    for name in ("arecord", "parecord", "pw-record"):
        (bindir / name).write_text("#!/bin/sh\n")
        (bindir / name).chmod(0o755)
        assert stt_record.recorder_argv("/x.wav")[0] == name
    assert stt_record.recorder_argv("/x.wav")[-1] == "/x.wav" and "16000" in stt_record.recorder_argv("/x.wav")


# --- setup size ---------------------------------------------------------------------------------
