"""Setup checks for the parts around the chat: attachments, voice and schedules.

Rows as in diag_agents.row. Voice is only checked when its switch is on, and
reuses what Settings → Voice already asks (stt_engines.available,
stt_record.recorder_name, stt_setup.cached_model, tts.find_piper) instead of
probing again. Schedules are read without migrating or syncing anything;
the fix for missing timers is the existing ``schedules_sync``. Stdlib only.
"""
import datetime as dt
import os
import shlex
import shutil
from typing import Any, Dict, List

from kdeaichat import schedule_store, schedule_units, stt_engines, stt_record, stt_setup
from kdeaichat.diag_agents import row, valid_http_url
from kdeaichat.schedule_calendar import timer_name
from kdeaichat.schedule_model import normalize_schedule
from kdeaichat.schedule_runs import load_run_state
from kdeaichat.stt_settings import SettingsError, from_payload
from kdeaichat.tts import find_piper


def check_attachments() -> List[Dict[str, Any]]:
    """doc_extractor.py reads PDFs with pdftotext and Word files with pandoc (or a simpler built-in reader)."""
    rows = []
    rows.append(row("attach-pdf", "attachments", "ok", "pdf-ok") if shutil.which("pdftotext")
                else row("attach-pdf", "attachments", "warn", "pdf-missing"))
    rows.append(row("attach-docx", "attachments", "ok", "docx-ok") if shutil.which("pandoc")
                else row("attach-docx", "attachments", "warn", "docx-basic"))
    return rows


ENGINE_NAMES = {"faster-whisper": "faster-whisper", "whisper-cpp": "whisper.cpp", "remote": "speech server",
                "command": "custom command"}


def check_dictation(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Dictation (only called when sttEnabled): recorder, engine, model."""
    try:
        settings = from_payload(payload)
    except SettingsError as e:
        return [row("stt-engine", "voice", "error", "stt-bad-settings", str(e))]
    rows = []
    recorder = stt_record.recorder_name()
    rows.append(row("stt-recorder", "voice", "ok", "stt-recorder-ok", recorder) if recorder
                else row("stt-recorder", "voice", "error", "stt-no-recorder"))
    engine = settings["engine"]
    found = next((r for r in stt_engines.available(settings) if r["id"] == engine), {})
    if engine == "faster-whisper":
        if not found.get("installed"):
            code = "stt-fw-missing" if found.get("selectable") else "stt-no-venv"
            rows.append(row("stt-engine", "voice", "error", code))
            return rows
        model = settings["model"]
        if os.sep in model:
            if not os.path.isdir(model):
                rows.append(row("stt-model", "voice", "error", "stt-model-folder-missing", model))
                return rows
        elif not stt_setup.cached_model(model):
            rows.append(row("stt-model", "voice", "warn", "stt-model-missing", model))
            return rows
    elif engine == "whisper-cpp" and not found.get("available"):
        binary = found.get("binary") or ""
        rows.append(row("stt-engine", "voice", "error", "stt-whispercpp-model" if binary else "stt-whispercpp-missing",
                        settings["whisper_cpp_model"]))
        return rows
    elif engine == "remote" and not settings["remote_url"]:
        rows.append(row("stt-engine", "voice", "error", "stt-remote-url"))
        return rows
    elif engine == "command" and not found.get("available"):
        rows.append(row("stt-engine", "voice", "error", "stt-command-bad", found.get("reason") or ""))
        return rows
    rows.append(row("stt-engine", "voice", "ok", "stt-ready", ENGINE_NAMES.get(engine, engine)))
    return rows


def check_read_aloud(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Read aloud (only called when voiceTtsEnabled): what the chosen engine needs."""
    engine = str(payload.get("voiceTtsEngine") or "system")
    if engine == "piper":
        if not find_piper(str(payload.get("voiceTtsPiperBinary") or "")):
            return [row("tts-engine", "voice", "error", "tts-piper-missing")]
        model = os.path.expanduser(str(payload.get("voiceTtsPiperModel") or ""))
        if not model or not os.path.isfile(model):
            return [row("tts-engine", "voice", "error", "tts-piper-voice", model)]
    elif engine == "remote":
        if not valid_http_url(str(payload.get("voiceTtsRemoteUrl") or "")):
            return [row("tts-engine", "voice", "error", "tts-remote-url")]
    elif engine == "command":
        try:
            words = shlex.split(str(payload.get("voiceTtsCommand") or ""))
        except ValueError:
            words = []
        program = os.path.expanduser(words[0]) if words else ""
        if not program or not (shutil.which(program) or (os.sep in program and os.access(program, os.X_OK))):
            return [row("tts-engine", "voice", "error", "tts-command-bad")]
    elif engine == "system":
        if not shutil.which("speech-dispatcher"):
            return [row("tts-engine", "voice", "warn", "tts-speechd-missing")]
    else:
        # Kokoro and Flite are Qt speech plugins: only the widget can load them (Settings → Voice lists their voices).
        return [row("tts-engine", "voice", "ok", "tts-qt-engine", engine)]
    return [row("tts-engine", "voice", "ok", "tts-ready", engine)]


def check_schedules(now: dt.datetime = None) -> List[Dict[str, Any]]:
    """Each schedule that can still fire needs its systemd timer; read only."""
    now = now or dt.datetime.now().replace(microsecond=0)
    try:
        store = schedule_store.read_store()
    except (OSError, ValueError):
        return [row("schedules", "scheduler", "error", "sched-unreadable")]
    wanted = []
    for s in (store or {}).get("schedules") or []:
        try:
            s = normalize_schedule(s, now=now)
        except ValueError:
            continue
        if schedule_units.wants_timer(s, load_run_state(s["id"]), now):
            wanted.append(s["id"])
    if not wanted:
        return [row("schedules", "scheduler", "ok", "sched-none")]
    if schedule_units.systemctl(["show-environment"]) != 0:
        return [row("schedules", "scheduler", "error", "sched-no-systemd")]
    folder = schedule_units.unit_dir()
    missing = [sid for sid in wanted
               if not os.path.isfile(os.path.join(folder, timer_name(sid)))
               or schedule_units.systemctl(["is-enabled", "--quiet", timer_name(sid)]) != 0]
    if missing:
        return [row("schedules", "scheduler", "error", "sched-timers-missing", len(missing))]
    return [row("schedules", "scheduler", "ok", "sched-ok", len(wanted))]
