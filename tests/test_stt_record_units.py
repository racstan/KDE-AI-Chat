"""Dictation recording, the setup size estimate, and the STT systemd units / old-unit cleanup."""
import json
import os
import struct
import sys
import threading
import time

import pytest

from kdeaichat import stt_record, stt_setup, stt_units
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

def test_setup_size(tmp_path):
    venv, cache = tmp_path / "venv", tmp_path / "hub"
    fresh = stt_setup.estimate("small", str(venv), "auto", has_gpu=False, cache=str(cache))
    assert fresh["gpu"] is False and fresh["model_mb"] == 484
    assert fresh["total_mb"] == fresh["packages_mb"] + 484 and 100 < fresh["packages_mb"] < 300
    assert not any("torch" in i["name"] or "spacy" in i["name"] or "transformers" in i["name"] for i in fresh["items"])
    gpu = stt_setup.estimate("small", str(venv), "auto", has_gpu=True, cache=str(cache))
    assert gpu["gpu"] is True and gpu["packages_mb"] > fresh["packages_mb"] + 1000
    assert stt_setup.estimate("small", str(venv), False, has_gpu=True, cache=str(cache))["gpu"] is False
    # Installed packages and a cached model are not counted again.
    site = venv / "lib" / "python3.12" / "site-packages"
    for name in ("faster_whisper", "ctranslate2", "onnxruntime", "av", "tokenizers", "huggingface_hub", "hf_xet",
                 "numpy", "tqdm"):
        (site / name).mkdir(parents=True)
    snapshot = cache / "models--Systran--faster-whisper-small" / "snapshots" / "abc"
    snapshot.mkdir(parents=True)
    (snapshot / "model.bin").write_bytes(b"x")
    done = stt_setup.estimate("small", str(venv), "auto", has_gpu=False, cache=str(cache))
    assert done["total_mb"] == 0 and done["items"] == [] and str(snapshot) in done["model_note"]
    assert stt_setup.cached_models(str(cache)) == ["small"]
    assert stt_setup.estimate("/my/ct2", str(venv), "auto", cache=str(cache))["model_mb"] == 0


# --- units --------------------------------------------------------------------------------------

LEGACY = """[Unit]
Description=KDE AI Chat STT-SERVER Daemon
[Service]
ExecStart="/home/u/.local/share/kdeaichat/venv/bin/python3" "/x/voice/voice_helper.py" --stt-server --token-file "/t"
Restart=always
[Install]
WantedBy=default.target
"""


@pytest.fixture
def units(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    directory = tmp_path / "units"
    directory.mkdir()
    venv = tmp_path / "venv"
    (venv / "bin").mkdir(parents=True)
    (venv / "bin" / "python3").write_text("")
    calls = []

    def run(args):
        calls.append(" ".join(args))
        if args[:2] == ["enable", "--now"]:  # like systemctl: link the socket into sockets.target.wants
            wants = directory / "sockets.target.wants"
            wants.mkdir(exist_ok=True)
            if not (wants / args[2]).exists():
                (wants / args[2]).symlink_to(directory / args[2])
        return 0

    def sync(**payload):
        return stt_units.sync(dict({"venv": str(venv)}, **payload), str(directory), run)

    return directory, calls, sync


def test_legacy_unit_is_removed_in_every_case_and_cleanup_is_idempotent(units):
    directory, calls, sync = units
    (directory / "kde-ai-stt.service").write_text(LEGACY)
    (directory / "default.target.wants").mkdir()
    (directory / "default.target.wants" / "kde-ai-stt.service").symlink_to(directory / "kde-ai-stt.service")
    result = sync(sttEnabled=False)
    assert result["legacy_removed"] and calls == ["disable --now kde-ai-stt.service", "daemon-reload"]
    assert os.listdir(directory) == ["default.target.wants"] and not os.listdir(directory / "default.target.wants")
    calls.clear()
    assert sync(sttEnabled=False)["changed"] is False and calls == []


def test_socket_unit_only_while_dictation_is_on_with_faster_whisper(units):
    directory, calls, sync = units
    (directory / "kde-ai-stt.service").write_text(LEGACY)
    result = sync(sttEnabled=True, sttEngine="faster-whisper")
    assert result["installed"] and result["legacy_removed"]
    assert calls == ["disable --now kde-ai-stt.service", "daemon-reload", "stop kde-ai-stt.service",
                     "enable --now kde-ai-stt.socket"]
    socket_text = (directory / "kde-ai-stt.socket").read_text()
    service_text = (directory / "kde-ai-stt.service").read_text()
    assert "ListenStream=127.0.0.1:9015" in socket_text and "WantedBy=sockets.target" in socket_text
    assert "stt_service.py" in service_text and "--idle-timeout 300" in service_text and "Restart=no" in service_text
    assert "Restart=always" not in service_text and "[Install]" not in service_text and "--stt-server" not in service_text
    assert os.stat(stt_units.token_path()).st_mode & 0o777 == 0o600
    # Again: nothing to do.
    calls.clear()
    assert sync(sttEnabled=True, sttEngine="faster-whisper")["changed"] is False and calls == []
    # Another engine, then dictation off: the units go away.
    result = sync(sttEnabled=True, sttEngine="remote")
    assert result["removed"] and result["reason"] == "another engine is chosen"
    assert calls == ["disable --now kde-ai-stt.socket kde-ai-stt.service", "daemon-reload"]
    assert not (directory / "kde-ai-stt.socket").exists() and not (directory / "kde-ai-stt.service").exists()
    assert not os.path.lexists(directory / "sockets.target.wants" / "kde-ai-stt.socket")
    calls.clear()
    assert sync(sttEnabled=False)["reason"] == "dictation is off" and calls == []


def test_no_unit_without_the_venv(units, tmp_path):
    directory, calls, sync = units
    result = stt_units.sync({"sttEnabled": True, "venv": str(tmp_path / "missing")}, str(directory), lambda a: 0)
    assert result["installed"] is False and result["reason"] == "parakeet is not installed"
    assert os.listdir(directory) == []


def test_systemd_accepts_the_units(units, tmp_path):
    import shutil
    import subprocess
    if not shutil.which("systemd-analyze"):
        pytest.skip("systemd-analyze not installed")
    directory, calls, sync = units
    sync(sttEnabled=True)
    service = (directory / "kde-ai-stt.service").read_text().replace(str(tmp_path / "venv" / "bin" / "python3"),
                                                                    sys.executable)
    (directory / "kde-ai-stt.service").write_text(service)
    out = subprocess.run(["systemd-analyze", "--user", "verify", str(directory / "kde-ai-stt.socket"),
                          str(directory / "kde-ai-stt.service")], capture_output=True, text=True, timeout=60)
    problems = [line for line in out.stderr.splitlines() if "kde-ai-stt" in line]
    assert problems == [], out.stderr
