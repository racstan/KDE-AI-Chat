"""Dictation: record the microphone to a private WAV, then hand it to the chosen engine.

``stt_dictate`` records with PipeWire's ``pw-record`` (or ``parecord`` /
``arecord``) at 16 kHz mono into a 0700 folder under ``$XDG_RUNTIME_DIR``,
until ``stt_stop`` (SIGINT to the recorder) or five minutes, then
transcribes and prints one result line: the widget gets it when the command
ends, so nothing polls. ``stt_stop`` with ``cancel`` drops the recording.
The recording is deleted as soon as it is transcribed.

``KDEAICHAT_STT_RECORDER`` (tests) replaces the recorder: a program that
gets the WAV path as its last argument and stops on SIGINT.
"""
import json
import os
import shutil
import signal
import struct
import subprocess
import tempfile
from typing import Any, Callable, Dict, List, Optional

from kdeaichat.stt_settings import runtime_dir

MAX_SECONDS = 300
MIN_SECONDS = 0.3
STATE_NAME = "stt-dictation.json"


def recorder_argv(wav: str) -> List[str]:
    override = os.environ.get("KDEAICHAT_STT_RECORDER")
    if override:
        return [override, wav]
    if shutil.which("pw-record"):
        return ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", wav]
    if shutil.which("parecord"):
        return ["parecord", "--rate=16000", "--channels=1", "--format=s16le", "--file-format=wav", wav]
    if shutil.which("arecord"):
        return ["arecord", "-q", "-f", "S16_LE", "-r", "16000", "-c", "1", "-t", "wav", wav]
    return []


def recorder_name() -> str:
    argv = recorder_argv("x.wav")
    return os.path.basename(argv[0]) if argv else ""


def _state_path() -> str:
    return os.path.join(runtime_dir(), STATE_NAME)


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except (OSError, OverflowError):
        return False


def read_state() -> Optional[Dict[str, Any]]:
    try:
        with open(_state_path(), encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(state, dict) or not isinstance(state.get("pid"), int) or not _alive(state["pid"]):
        return None
    return state


def _write_state(state: Dict[str, Any]) -> None:
    path = _state_path()
    fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(state, f)
    os.replace(path + ".tmp", path)


def _clear_state(pid: int) -> None:
    try:
        with open(_state_path(), encoding="utf-8") as f:
            if json.load(f).get("pid") != pid:
                return
        os.unlink(_state_path())
    except (OSError, ValueError, AttributeError):
        pass


def fix_wav(path: str) -> float:
    """Repair the RIFF/data sizes of a recording cut short and return its length in seconds."""
    try:
        size = os.path.getsize(path)
        with open(path, "r+b") as f:
            head = f.read(12)
            if len(head) < 12 or head[:4] != b"RIFF" or head[8:12] != b"WAVE":
                return 0.0
            byte_rate, pos = 0, 12
            while pos + 8 <= size:
                f.seek(pos)
                chunk_id, chunk_size = struct.unpack("<4sI", f.read(8))
                if chunk_id == b"fmt ":
                    fmt = f.read(min(chunk_size, 16))
                    if len(fmt) >= 12:
                        byte_rate = struct.unpack("<I", fmt[8:12])[0]
                elif chunk_id == b"data":
                    data_size = size - pos - 8
                    if chunk_size != data_size:
                        f.seek(pos + 4)
                        f.write(struct.pack("<I", data_size))
                        f.seek(4)
                        f.write(struct.pack("<I", size - 8))
                    return data_size / byte_rate if byte_rate else 0.0
                pos += 8 + chunk_size + (chunk_size & 1)
    except (OSError, struct.error):
        pass
    return 0.0


def _wait(proc: subprocess.Popen, seconds: float) -> None:
    try:
        proc.wait(timeout=seconds)
        return
    except subprocess.TimeoutExpired:
        proc.send_signal(signal.SIGINT)  # the limit: finish the file as a stop would
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def dictate(settings: Dict[str, Any], transcribe: Callable[[str, Dict[str, Any]], Dict[str, Any]],
            max_seconds: float = MAX_SECONDS) -> Dict[str, Any]:
    if read_state():
        return {"type": "stt_error", "error": "Already recording", "code": "busy"}
    folder = tempfile.mkdtemp(prefix="stt-", dir=runtime_dir())
    wav = os.path.join(folder, "speech.wav")
    try:
        argv = recorder_argv(wav)
        if not argv:
            return {"type": "stt_error", "error": "No recorder found (pw-record, parecord or arecord)", "code": "no_recorder"}
        log_path = os.path.join(folder, "recorder.log")
        try:
            with os.fdopen(os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as log:
                proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=log)
        except OSError as e:
            return {"type": "stt_error", "error": "Can't start %s: %s" % (argv[0], e.strerror or e), "code": "no_recorder"}
        _write_state({"pid": proc.pid, "owner": os.getpid(), "folder": folder, "wav": wav})
        try:
            _wait(proc, max_seconds)
        finally:
            _clear_state(proc.pid)
        with open(log_path, "rb") as log:
            stderr = log.read(8192).decode("utf-8", "replace").strip()
        if os.path.exists(os.path.join(folder, "cancel")):
            return {"type": "stt_stopped", "cancelled": True}
        seconds = fix_wav(wav) if os.path.exists(wav) else 0.0
        if seconds <= 0 and proc.returncode not in (0, None, -signal.SIGINT):
            detail = stderr.splitlines()[-1][:200] if stderr else "exit %s" % proc.returncode
            return {"type": "stt_error", "error": "Recording failed (%s)" % detail, "code": "record_failed"}
        if seconds < MIN_SECONDS:
            return {"type": "stt_result", "text": "", "duration": round(seconds, 2), "engine": settings["engine"]}
        reply = transcribe(wav, settings)
        reply["duration"] = round(seconds, 2)
        return reply
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def stop(cancel: bool = False) -> Dict[str, Any]:
    state = read_state()
    if not state:
        return {"type": "stt_stopped", "recording": False}
    pid, wav, folder = state["pid"], str(state.get("wav", "")), str(state.get("folder", ""))
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            ours = wav.encode() in f.read().split(b"\0")
    except OSError:
        ours = False
    if not ours or not folder.startswith(runtime_dir() + os.sep):
        return {"type": "stt_stopped", "recording": False}
    if cancel:
        os.close(os.open(os.path.join(folder, "cancel"), os.O_WRONLY | os.O_CREAT, 0o600))
    try:
        os.kill(pid, signal.SIGINT)
    except OSError:
        pass
    return {"type": "stt_stopping", "cancelled": cancel}
