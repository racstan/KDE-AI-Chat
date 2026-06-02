#!/usr/bin/env python3
"""
kde-ai-scheduler.py — KDE AI Chat Scheduling Daemon (Simplified Message Injector)
================================================================================
Runs as a systemd user service. Reads ~/.local/share/kdeaichat/schedules.json,
and when a cron rule is due, writes a pending trigger JSON file to:
~/.local/share/kdeaichat/pending/sched-{id}-{timestamp}.json

This is picked up by the KDE AI Chat front-end widget, which injects it
directly into the active chat session.

Reload schedules without restart: kill -HUP <pid>
"""

import argparse
import fcntl
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timedelta

parser = argparse.ArgumentParser(
    description="KDE AI Chat scheduling daemon — reads schedule files and triggers pending jobs via cron rules."
)
parser.add_argument("--debug", action="store_true", help="Enable debug-level logging")
parser.add_argument("--dry-run", action="store_true", help="Simulate without creating trigger files")
args, _ = parser.parse_known_args()

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.DEBUG if args.debug else logging.INFO,
)
log = logging.getLogger(__name__)

# ── Paths ──────────────────────────────────────────────────────────────────────
HOME = os.path.expanduser("~")
DATA_DIR = os.path.join(HOME, ".local", "share", "kdeaichat")
SCHEDULES_FILE = os.path.join(DATA_DIR, "schedules.json")
LOCK_FILE = os.path.join(DATA_DIR, "scheduler.lock")
LOCK_FD = None

# Tick interval in seconds
TICK_SECONDS = 5

# ── Globals ────────────────────────────────────────────────────────────────────
schedules = []
history = []
reload_requested = False


# ── Signal handlers ────────────────────────────────────────────────────────────
def handle_sighup(signum, frame):
    global reload_requested
    reload_requested = True
    log.info("SIGHUP received — will reload schedules.json on next tick")


def handle_sigterm(signum, frame):
    log.info("SIGTERM received — shutting down gracefully")
    cleanup()
    sys.exit(0)


signal.signal(signal.SIGHUP, handle_sighup)
signal.signal(signal.SIGTERM, handle_sigterm)


# ── Filesystem helpers ─────────────────────────────────────────────────────────
def ensure_dirs():
    os.makedirs(DATA_DIR, mode=0o700, exist_ok=True)
    os.makedirs(os.path.join(DATA_DIR, "pending"), mode=0o700, exist_ok=True)


def write_lock():
    global LOCK_FD
    try:
        LOCK_FD = os.open(LOCK_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        fcntl.lockf(LOCK_FD, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.write(LOCK_FD, str(os.getpid()).encode())
    except (OSError, IOError) as e:
        log.error("Lock file %s: %s — another instance may be running", LOCK_FILE, e)
        sys.exit(1)


def cleanup():
    global LOCK_FD
    if LOCK_FD is not None:
        try:
            os.close(LOCK_FD)
        except OSError:
            pass
        LOCK_FD = None
    try:
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)
    except OSError:
        pass


# ── Schedules I/O ──────────────────────────────────────────────────────────────
def load_schedules():
    global history
    if not os.path.exists(SCHEDULES_FILE):
        log.debug(f"Schedules file not found: {SCHEDULES_FILE}")
        history = []
        return []
    try:
        with open(SCHEDULES_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            items = data
            history = []
        elif isinstance(data, dict):
            items = data.get("schedules", [])
            history = data.get("history", [])
        else:
            items = []
            history = []
        log.info(f"Loaded {len(items)} schedule(s) and {len(history)} history entry(s) from {SCHEDULES_FILE}")
        return items
    except (json.JSONDecodeError, OSError) as e:
        log.error("Failed to load schedules: %s", e)
        history = []
        return []


def save_schedules(items):
    global history
    try:
        payload = {
            "version": 1,
            "schedules": items,
            "history": history
        }
        tmp = SCHEDULES_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
        os.replace(tmp, SCHEDULES_FILE)
        os.chmod(SCHEDULES_FILE, 0o600)
        log.debug("Schedules and history saved")
    except OSError as e:
        log.error("Failed to save schedules: %s", e)


# ── Cron parser ────────────────────────────────────────────────────────────────
WEEKDAY_NAMES = {
    "sun": 0, "mon": 1, "tue": 2, "wed": 3,
    "thu": 4, "fri": 5, "sat": 6,
}


def parse_cron_field(field_str, min_val, max_val):
    field_str = field_str.strip().lower()
    for name, num in WEEKDAY_NAMES.items():
        field_str = field_str.replace(name, str(num))

    result = set()

    for part in field_str.split(","):
        part = part.strip()
        step = 1
        if "/" in part:
            part, step_str = part.split("/", 1)
            step = int(step_str)

        if part == "*":
            start, end = min_val, max_val
        elif "-" in part:
            start_str, end_str = part.split("-", 1)
            start, end = int(start_str), int(end_str)
        else:
            val = int(part)
            result.add(val)
            continue

        for v in range(start, end + 1, step):
            result.add(v)

    return sorted(result)


def cron_matches(cron_expr, dt):
    parts = cron_expr.strip().split()
    if len(parts) != 5:
        return False
    try:
        minutes = parse_cron_field(parts[0], 0, 59)
        hours = parse_cron_field(parts[1], 0, 23)
        mdays = parse_cron_field(parts[2], 1, 31)
        months = parse_cron_field(parts[3], 1, 12)
        wdays = parse_cron_field(parts[4], 0, 6)
    except (ValueError, IndexError):
        return False

    py_wd = dt.weekday()
    cron_wd = (py_wd + 1) % 7

    dom_star = parts[2].strip() == "*"
    dow_star = parts[4].strip() == "*"

    if dom_star and dow_star:
        day_match = True
    elif dom_star:
        day_match = cron_wd in wdays
    elif dow_star:
        day_match = dt.day in mdays
    else:
        day_match = (dt.day in mdays) or (cron_wd in wdays)

    return (
        dt.minute in minutes
        and dt.hour in hours
        and day_match
        and dt.month in months
    )


# ── Schedule runner ────────────────────────────────────────────────────────────
def run_schedule(s):
    sid = s.get("id", "unknown")
    name = s.get("name", "Unnamed")
    chat_id = s.get("chatId", "")
    message = s.get("message", "").strip()
    should_notify = s.get("notify", True)

    if not chat_id or not message:
        log.warning("[%s] Skipping — missing chatId or message", name)
        return "error"

    log.info(f"[{name}] Triggering schedule message injection to chat {chat_id}")
    
    pending_dir = os.path.join(DATA_DIR, "pending")
    ts = int(time.time() * 1000)
    filename = f"sched-{sid}-{ts}.json"
    path = os.path.join(pending_dir, filename)

    payload = {
        "id": sid,
        "chatId": chat_id,
        "message": message,
        "notify": should_notify,
        "name": name,
        "timestamp": ts
    }

    if args.dry_run:
        log.info("[%s] DRY-RUN: would write trigger to %s", name, path)
        return "success"  # pretend it worked

    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
        os.chmod(path, 0o600)
        log.info(f"[{name}] Wrote pending trigger file successfully: {path}")
        return "success"
    except Exception as e:
        log.error("[%s] Failed to write pending trigger: %s", name, e)
        return "error"


# ── Main loop ──────────────────────────────────────────────────────────────────
def is_start_date_passed(s, now):
    start_date_str = s.get("startDate")
    if not start_date_str:
        return True
    try:
        clean_str = start_date_str
        if clean_str.endswith("Z"):
            clean_str = clean_str[:-1]
        if "." in clean_str:
            clean_str = clean_str.split(".")[0]
        parts = clean_str.split("T")
        if len(parts) != 2:
            parts = clean_str.split(" ")
        if len(parts) == 2:
            dt_part = parts[0]
            tm_part = parts[1]
            dp = dt_part.split("-")
            tp = tm_part.split(":")
            year = int(dp[0])
            month = int(dp[1])
            day = int(dp[2])
            hour = int(tp[0])
            minute = int(tp[1])
            start_dt = datetime(year, month, day, hour, minute)
            return now >= start_dt
    except Exception as e:
        log.warning("Error parsing startDate '%s': %s", start_date_str, e)
    return True


def update_schedule_timestamps(items, sid, now_iso, status, next_iso):
    updated = []
    for s in items:
        if s.get("id") == sid:
            s = dict(s)
            s["lastRunAt"] = now_iso
            s["lastRunStatus"] = status
            s["nextRunAt"] = next_iso
            s.pop("triggerNow", None)
        updated.append(s)
    return updated


def next_run_iso(cron_expr):
    now = datetime.now()
    for _ in range(525600):
        now = now.replace(second=0, microsecond=0)
        mins = now.minute + 1
        now = now.replace(minute=mins % 60)
        if mins >= 60:
            hrs = now.hour + 1
            now = now.replace(hour=hrs % 24)
            if hrs >= 24:
                import datetime as dt_mod
                now = (now + dt_mod.timedelta(days=1)).replace(hour=0, minute=0)
        if cron_matches(cron_expr, now):
            return now.isoformat(timespec="seconds")
    return ""


def main():
    global schedules, reload_requested, history

    log.info("KDE AI Chat Scheduler daemon starting up")
    ensure_dirs()
    write_lock()

    schedules = load_schedules()

    # Pre-calculate nextRunAt for any schedule missing it
    for s in schedules:
        if s.get("enabled") and not s.get("nextRunAt"):
            cron = s.get("cron", "")
            if cron:
                s["nextRunAt"] = next_run_iso(cron)
    save_schedules(schedules)

    log.info(f"Tick interval: {TICK_SECONDS}s — monitoring {len(schedules)} schedule(s)")

    while True:
        if reload_requested:
            reload_requested = False
            schedules = load_schedules()
            log.info(f"Schedules reloaded — {len(schedules)} schedule(s) active")

        now = datetime.now()
        now_iso = now.isoformat(timespec="seconds")
        changed = False

        for s in schedules:
            if s.get("archived", False):
                continue

            if not s.get("enabled", True):
                continue

            sid = s.get("id", "")
            cron = s.get("cron", "").strip()
            trigger_now = s.get("triggerNow", False)
            task_type = s.get("taskType", "repeat")

            # Missed execution catch-up detection (backfill)
            is_missed = False
            next_run_str = s.get("nextRunAt", "")
            if next_run_str and not trigger_now:
                try:
                    clean_next = next_run_str
                    if clean_next.endswith("Z"):
                        clean_next = clean_next[:-1]
                    if "." in clean_next:
                        clean_next = clean_next.split(".")[0]
                    next_dt = datetime.fromisoformat(clean_next)
                    
                    # Trigger immediately if scheduled run is in the past by at least 1 minute
                    if next_dt < now - timedelta(minutes=1):
                        is_missed = True
                        log.info(f"[{s.get('name', 'Unnamed')}] Missed execution detected (scheduled: {next_run_str}, now: {now_iso}). Catching up now!")
                except Exception as ex:
                    log.debug(f"Failed to parse nextRunAt '{next_run_str}': {ex}")

            # Start date filter
            start_passed = is_start_date_passed(s, now)
            if not start_passed and not trigger_now:
                continue

            # Limit checking
            if task_type == "repeat" and s.get("limitEnabled", False):
                run_count = int(s.get("runCount", 0))
                limit_count = int(s.get("limitCount", 5))
                if run_count >= limit_count:
                    s["enabled"] = False
                    changed = True
                    continue

            should_run = trigger_now or is_missed
            if not should_run:
                if task_type == "single":
                    should_run = not s.get("lastRunAt")
                elif cron:
                    # Prevent multiple runs within the same minute
                    last_run = s.get("lastRunAt", "")
                    if last_run and last_run.startswith(now_iso[:16]):
                        should_run = False
                    else:
                        should_run = cron_matches(cron, now)

            if should_run:
                status = run_schedule(s)
                
                # Append to history
                try:
                    entry = {
                        "id": f"h-{int(time.time() * 1000)}",
                        "scheduleId": sid,
                        "scheduleName": s.get("name", "Unnamed"),
                        "chatId": s.get("chatId", ""),
                        "chatName": s.get("chatName", "Chat"),
                        "message": s.get("message", ""),
                        "timestamp": now_iso,
                        "status": "success (missed execution catch-up)" if (is_missed and (not status or status == "success")) else (status or "success")
                    }
                    history.append(entry)
                    if len(history) > 100:
                        history = history[-100:]
                except Exception as ex:
                    log.error("Failed to append to history: %s", ex)

                # Update run counts and limits
                new_count = int(s.get("runCount", 0)) + 1
                s["runCount"] = new_count

                disable_task = False
                if task_type == "single":
                    disable_task = True
                elif s.get("limitEnabled", False) and new_count >= int(s.get("limitCount", 5)):
                    disable_task = True

                next_iso = ""
                if not disable_task and cron:
                    next_iso = next_run_iso(cron)

                schedules = update_schedule_timestamps(schedules, sid, now_iso,
                                                       status or "success", next_iso)
                
                # Disable task in state list if done
                if disable_task:
                    for item in schedules:
                        if item.get("id") == sid:
                            item["enabled"] = False
                            item["nextRunAt"] = ""

                changed = True

        if changed:
            save_schedules(schedules)

        time.sleep(TICK_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log.info("Interrupted — shutting down")
        cleanup()
        sys.exit(0)
    except Exception as e:
        log.error("Fatal error: %s", e)
        cleanup()
        sys.exit(1)
