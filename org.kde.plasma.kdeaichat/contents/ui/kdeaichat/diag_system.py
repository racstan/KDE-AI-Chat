"""Setup checks for the parts around the chat: attachments, voice and schedules.

Rows as in diag_agents.row. Voice is only checked when its switch is on, and
reuses what Settings → Voice already asks (stt_record.recorder_name,
the Speech Note checks) instead of probing again. Schedules are read without migrating or syncing anything;
the fix for missing timers is the existing ``schedules_sync``. Stdlib only.
"""
import datetime as dt
import os
import shutil
from typing import Any, Dict, List

from kdeaichat import diag_speechnote, schedule_store, schedule_units, stt_record
from kdeaichat.diag_agents import row, valid_http_url
from kdeaichat.schedule_calendar import timer_name
from kdeaichat.schedule_model import normalize_schedule
from kdeaichat.schedule_runs import load_run_state
from kdeaichat.stt_settings import SettingsError, from_payload


def check_attachments() -> List[Dict[str, Any]]:
    """doc_extractor.py reads PDFs with pdftotext and Word files with pandoc (or a simpler built-in reader)."""
    rows = []
    rows.append(row("attach-pdf", "attachments", "ok", "pdf-ok") if shutil.which("pdftotext")
                else row("attach-pdf", "attachments", "warn", "pdf-missing"))
    rows.append(row("attach-docx", "attachments", "ok", "docx-ok") if shutil.which("pandoc")
                else row("attach-docx", "attachments", "warn", "docx-basic"))
    return rows


def check_dictation(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Dictation (only called when sttEnabled): Speech Note (the default), or the speech server and its recorder."""
    if str(payload.get("sttEngine") or "speechnote") != "remote":   # Speech Note listens with its own microphone
        return diag_speechnote.check("stt")
    try:
        settings = from_payload(payload)
    except SettingsError as e:
        return [row("stt-engine", "voice", "error", "stt-bad-settings", str(e))]
    rows = []
    recorder = stt_record.recorder_name()
    rows.append(row("stt-recorder", "voice", "ok", "stt-recorder-ok", recorder) if recorder
                else row("stt-recorder", "voice", "error", "stt-no-recorder"))
    if not settings["remote_url"]:
        rows.append(row("stt-engine", "voice", "error", "stt-remote-url"))
        return rows
    rows.append(row("stt-engine", "voice", "ok", "stt-ready", "speech server"))
    return rows


def check_read_aloud(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Read aloud (only called when voiceTtsEnabled): Speech Note (the default), the system voice or the speech server."""
    engine = str(payload.get("voiceTtsEngine") or "speechnote")
    if engine == "remote":
        if not valid_http_url(str(payload.get("voiceTtsRemoteUrl") or "")):
            return [row("tts-engine", "voice", "error", "tts-remote-url")]
    elif engine == "system":
        if not shutil.which("speech-dispatcher"):
            return [row("tts-engine", "voice", "warn", "tts-speechd-missing")]
    else:
        return diag_speechnote.check("tts")
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
