"""Scheduler commands: the schedule store, pending triggers and the service.

Each mutating command takes the schedule-store lock around its complete
read/modify/write, so it never races the background scheduler daemon.
"""
import json
import os
import shutil
import sys
from typing import Any, Dict, List

from kdeaichat import schedule_store
from kdeaichat.common import (MAX_SCHEDULE_STORE_BYTES, atomic_write_json, atomic_write_text,
                              load_schedules, pending_dir, results_dir, safe_path,
                              schedule_store_lock, schedules_path)


def cmd_delete_session_schedules(payload: Dict[str, Any]) -> None:
    """Remove every schedule whose ``chatId`` matches ``sessionId`` (old and new store)."""
    session_id = str(payload.get("sessionId", ""))
    if session_id and os.path.exists(schedule_store.store_path()):
        schedule_store.delete_schedules(lambda s: s.get("chatId") == session_id)
    sp = schedules_path()
    if not os.path.exists(sp):
        return
    with schedule_store_lock():
        try:
            if os.path.getsize(sp) > MAX_SCHEDULE_STORE_BYTES:
                return
            with open(sp) as f:
                data: Any = json.load(f)
        except Exception:
            return
        if not isinstance(data, dict):
            return
        scheds: List[Dict[str, Any]] = data.get("schedules", [])
        session_id = str(payload.get("sessionId", ""))
        data["schedules"] = [s for s in scheds if isinstance(s, dict) and s.get("chatId") != session_id]
        atomic_write_json(sp, data)


def cmd_poll_pending_triggers(payload: Dict[str, Any]) -> None:
    """Drain the pending trigger directory and return its contents.

    Each file in the pending directory is read, parsed, and removed.
    Schedules are also returned for the QML side to keep its list in
    sync with the persisted store.
    """
    res: List[Dict[str, Any]] = []
    pd = pending_dir()
    if os.path.exists(pd):
        for f in sorted(os.listdir(pd))[:50]:
            if f.endswith(".json"):
                p = os.path.join(pd, f)
                try:
                    if os.path.getsize(p) > 512 * 1024:
                        raise ValueError("pending trigger is too large")
                    with open(p) as pf:
                        item = json.load(pf)
                    if isinstance(item, dict) and len(str(item.get("message", ""))) <= 200000:
                        res.append(item)
                except (OSError, ValueError, json.JSONDecodeError):
                    pass
                finally:
                    try: os.remove(p)
                    except OSError: pass
    scheds: List[Dict[str, Any]] = []
    try:
        with schedule_store_lock():
            scheds = load_schedules().get("schedules", [])
    except Exception:
        pass
    print(json.dumps({"pending": res, "schedules": scheds}))


def cmd_setup_scheduler_service(payload: Dict[str, Any]) -> None:
    """Install the scheduler service file, daemon, and schedules store.

    Copies the helper script to the user's bin directory, ensures the
    schedules store exists with restrictive permissions, and writes the
    systemd user unit. Reports whether the unit ended up enabled.
    """
    src = safe_path(payload.get("srcPath", ""))
    dest = safe_path(payload.get("destPath", ""))
    os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
    os.makedirs(results_dir(), mode=0o700, exist_ok=True)
    try: os.chmod(os.path.dirname(dest), 0o700); os.chmod(results_dir(), 0o700)
    except OSError: pass
    if os.path.exists(src):
        shutil.copy2(src, dest)
        os.chmod(dest, 0o755)
    sp = schedules_path()
    with schedule_store_lock():
        if not os.path.exists(sp):
            atomic_write_json(sp, {"version": 1, "schedules": []})
    sdir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(sdir, mode=0o700, exist_ok=True)
    sfile = sdir + "/kde-ai-scheduler.service"
    service_content = str(payload.get("serviceContent", ""))
    if not service_content or "\x00" in service_content or len(service_content) > 32768:
        raise ValueError("invalid scheduler service content")
    atomic_write_text(sfile, service_content, mode=0o600)
    os.system("systemctl --user daemon-reload")
    if os.system("systemctl --user is-enabled kde-ai-scheduler.service >/dev/null 2>&1") == 0:
        print("AUTO_ENABLED")
    else:
        print("AUTO_DISABLED")


def cmd_save_all_schedules(payload: Dict[str, Any]) -> None:
    """Persist a full schedules payload (replaces the existing file atomically)."""
    if not isinstance(payload, dict):
        raise ValueError("schedule payload must be an object")
    if len(json.dumps(payload, ensure_ascii=False).encode("utf-8")) > 1500000:
        raise ValueError("schedule payload is too large")
    p = os.path.expanduser("~/.local/share/kdeaichat")
    os.makedirs(p, mode=0o700, exist_ok=True)
    try: os.chmod(p, 0o700)
    except OSError: pass
    target = os.path.join(p, "schedules.json")
    try:
        with schedule_store_lock():
            try:
                disk = load_schedules()
            except Exception:
                disk = {"version": 1, "schedules": [], "history": []}
            merged_history = []
            seen = set()
            for history in (disk.get("history", []), payload.get("history", [])):
                for entry in history if isinstance(history, list) else []:
                    if not isinstance(entry, dict):
                        continue
                    key = entry.get("id") or json.dumps(entry, sort_keys=True, ensure_ascii=False)
                    if key not in seen:
                        seen.add(key)
                        merged_history.append(entry)
            payload_to_write = dict(payload)
            payload_to_write["schedules"] = [s for s in payload.get("schedules", []) if isinstance(s, dict)][:1000]
            payload_to_write["history"] = merged_history[-1000:]
            if not isinstance(payload_to_write.get("settings"), dict):
                payload_to_write["settings"] = disk.get("settings", {}) if isinstance(disk.get("settings", {}), dict) else {}
            atomic_write_json(target, payload_to_write)
        print("SCHED_SAVE_OK")
    except Exception as e:
        sys.stderr.write(f"Error saving schedules: {e}\n")
        print("SCHED_SAVE_ERROR")


COMMANDS = {
    "delete_session_schedules": cmd_delete_session_schedules,
    "poll_pending_triggers": cmd_poll_pending_triggers,
    "setup_scheduler_service": cmd_setup_scheduler_service,
    "save_all_schedules": cmd_save_all_schedules,
}
