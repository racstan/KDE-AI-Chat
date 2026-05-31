#!/usr/bin/env python3
"""
kde-ai-scheduler.py — KDE AI Chat Scheduling Daemon
====================================================
Runs as a systemd user service. Reads ~/.local/share/kdeaichat/schedules.json,
fires cron-triggered prompts at any OpenAI-compatible provider REST API,
writes results to ~/.local/share/kdeaichat/results/, and sends KDE desktop
notifications. Zero external Python dependencies — stdlib only.

Reload schedules without restart: kill -HUP <pid>
"""

import json
import os
import re
import signal
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

# ── Paths ──────────────────────────────────────────────────────────────────────
HOME = os.path.expanduser("~")
DATA_DIR = os.path.join(HOME, ".local", "share", "kdeaichat")
SCHEDULES_FILE = os.path.join(DATA_DIR, "schedules.json")
RESULTS_DIR = os.path.join(DATA_DIR, "results")
LOCK_FILE = os.path.join(DATA_DIR, "scheduler.lock")

# Tick interval in seconds — how often we check for due schedules
TICK_SECONDS = 30

# ── Globals ────────────────────────────────────────────────────────────────────
schedules = []
reload_requested = False
debug = "--debug" in sys.argv


def log(msg, level="INFO"):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] [{level}] {msg}", flush=True)


def dlog(msg):
    if debug:
        log(msg, "DEBUG")


# ── Signal handlers ────────────────────────────────────────────────────────────
def handle_sighup(signum, frame):
    global reload_requested
    reload_requested = True
    log("SIGHUP received — will reload schedules.json on next tick")


def handle_sigterm(signum, frame):
    log("SIGTERM received — shutting down gracefully")
    cleanup()
    sys.exit(0)


signal.signal(signal.SIGHUP, handle_sighup)
signal.signal(signal.SIGTERM, handle_sigterm)


# ── Filesystem helpers ─────────────────────────────────────────────────────────
def ensure_dirs():
    os.makedirs(DATA_DIR, mode=0o700, exist_ok=True)
    os.makedirs(RESULTS_DIR, mode=0o700, exist_ok=True)


def write_lock():
    try:
        with open(LOCK_FILE, "w") as f:
            f.write(str(os.getpid()))
        os.chmod(LOCK_FILE, 0o600)
    except OSError as e:
        log(f"Could not write lock file: {e}", "WARN")


def cleanup():
    try:
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)
    except OSError:
        pass


# ── Schedules I/O ──────────────────────────────────────────────────────────────
def load_schedules():
    if not os.path.exists(SCHEDULES_FILE):
        dlog(f"Schedules file not found: {SCHEDULES_FILE}")
        return []
    try:
        with open(SCHEDULES_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        items = data.get("schedules", [])
        log(f"Loaded {len(items)} schedule(s) from {SCHEDULES_FILE}")
        return items
    except (json.JSONDecodeError, OSError) as e:
        log(f"Failed to load schedules: {e}", "ERROR")
        return []


def save_schedules(items):
    try:
        payload = {"version": 1, "schedules": items}
        tmp = SCHEDULES_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
        os.replace(tmp, SCHEDULES_FILE)
        os.chmod(SCHEDULES_FILE, 0o600)
        dlog("Schedules saved")
    except OSError as e:
        log(f"Failed to save schedules: {e}", "ERROR")


def save_result(schedule_id, schedule_name, prompt, response, provider, model,
                status, error_msg, duration_ms):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%S")
    filename = f"{schedule_id}-{ts}.json"
    path = os.path.join(RESULTS_DIR, filename)
    result = {
        "scheduleId": schedule_id,
        "scheduleName": schedule_name,
        "ranAt": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "prompt": prompt,
        "response": response,
        "provider": provider,
        "model": model,
        "durationMs": duration_ms,
        "error": error_msg,
    }
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        os.chmod(path, 0o600)
        dlog(f"Result saved: {path}")
    except OSError as e:
        log(f"Failed to save result: {e}", "ERROR")
    # Cleanup old results
    cleanup_old_results(schedule_id, keep_days=schedule_get(schedule_id, "keepResultDays", 30))


def schedule_get(schedule_id, key, default=None):
    for s in schedules:
        if s.get("id") == schedule_id:
            return s.get(key, default)
    return default


def cleanup_old_results(schedule_id, keep_days=30):
    if keep_days <= 0:
        return
    cutoff = time.time() - (keep_days * 86400)
    prefix = schedule_id + "-"
    try:
        for fname in os.listdir(RESULTS_DIR):
            if fname.startswith(prefix) and fname.endswith(".json"):
                fpath = os.path.join(RESULTS_DIR, fname)
                if os.path.getmtime(fpath) < cutoff:
                    os.remove(fpath)
                    dlog(f"Cleaned up old result: {fname}")
    except OSError:
        pass


# ── Cron parser ────────────────────────────────────────────────────────────────
WEEKDAY_NAMES = {
    "sun": 0, "mon": 1, "tue": 2, "wed": 3,
    "thu": 4, "fri": 5, "sat": 6,
}


def parse_cron_field(field_str, min_val, max_val):
    """Parse a single cron field into a sorted set of matching integers."""
    field_str = field_str.strip().lower()
    # Replace named weekdays
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
    """Return True if dt matches the 5-field cron expression."""
    parts = cron_expr.strip().split()
    if len(parts) != 5:
        return False
    try:
        minutes = parse_cron_field(parts[0], 0, 59)
        hours = parse_cron_field(parts[1], 0, 23)
        mdays = parse_cron_field(parts[2], 1, 31)
        months = parse_cron_field(parts[3], 1, 12)
        wdays = parse_cron_field(parts[4], 0, 6)  # 0=Sun
    except (ValueError, IndexError):
        return False

    # Convert Python weekday (Mon=0) to cron weekday (Sun=0)
    py_wd = dt.weekday()  # Mon=0..Sun=6
    cron_wd = (py_wd + 1) % 7  # Mon=1..Sun=0

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


# ── KDE notification ───────────────────────────────────────────────────────────
def notify(title, body, urgency="normal"):
    try:
        import subprocess
        subprocess.run(
            [
                "notify-send",
                "--app-name=KDE AI Chat",
                "--icon=dialog-information",
                f"--urgency={urgency}",
                str(title)[:80],
                str(body)[:240],
            ],
            check=False,
            timeout=5,
        )
    except Exception as e:
        dlog(f"notify-send failed: {e}")


# ── AI API call ────────────────────────────────────────────────────────────────
DEFAULT_SYSTEM_PROMPT = (
    "You are KDE AI Chat, a precise and helpful assistant. "
    "Give accurate answers and clearly state uncertainty instead of inventing facts."
)


def call_ai(base_url, api_key, model, system_prompt, user_prompt, max_tokens=1000):
    """
    Call any OpenAI-compatible /chat/completions endpoint.
    Uses only stdlib urllib — no external packages required.
    """
    url = base_url.rstrip("/") + "/chat/completions"
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": user_prompt})

    payload = json.dumps({
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "stream": False,
    }).encode("utf-8")

    headers = {"Content-Type": "application/json"}
    if api_key and api_key.strip() and api_key.strip() != "__FROM_WALLET__":
        headers["Authorization"] = f"Bearer {api_key.strip()}"

    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=90) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    choices = data.get("choices", [])
    if not choices:
        raise ValueError("API returned no choices")
    content = choices[0].get("message", {}).get("content", "")
    return content


# ── Schedule runner ────────────────────────────────────────────────────────────
def run_schedule(s):
    sid = s.get("id", "unknown")
    name = s.get("name", "Unnamed")
    prompt = s.get("prompt", "").strip()
    system_prompt = s.get("systemPrompt", "").strip() or DEFAULT_SYSTEM_PROMPT
    base_url = s.get("baseUrl", "https://api.openai.com/v1").rstrip("/")
    api_key = s.get("apiKey", "")
    model = s.get("model", "gpt-4o-mini")
    max_tokens = int(s.get("maxTokens", 1000))
    should_notify = s.get("notify", True)
    notify_title = s.get("notifyTitle", "") or name
    save_results = s.get("saveResults", True)
    provider = s.get("provider", "unknown")

    if not prompt:
        log(f"[{name}] Skipping — no prompt configured", "WARN")
        return

    log(f"[{name}] Running scheduled task (provider={provider}, model={model})")
    t0 = time.time()
    status = "success"
    error_msg = None
    response = ""

    try:
        response = call_ai(base_url, api_key, model, system_prompt, prompt, max_tokens)
        log(f"[{name}] Completed in {int((time.time()-t0)*1000)}ms")
        if should_notify:
            preview = response[:180].replace("\n", " ") + ("…" if len(response) > 180 else "")
            notify(notify_title, preview)
    except urllib.error.HTTPError as e:
        status = "error"
        try:
            body = e.read().decode("utf-8", errors="replace")[:300]
        except Exception:
            body = str(e)
        error_msg = f"HTTP {e.code}: {body}"
        log(f"[{name}] HTTP error: {error_msg}", "ERROR")
        if should_notify:
            notify(f"Schedule failed: {name}", error_msg[:120], urgency="critical")
    except Exception as e:
        status = "error"
        error_msg = str(e)
        log(f"[{name}] Error: {error_msg}", "ERROR")
        if should_notify:
            notify(f"Schedule failed: {name}", error_msg[:120], urgency="critical")

    duration_ms = int((time.time() - t0) * 1000)

    if save_results:
        save_result(sid, name, prompt, response, provider, model,
                    status, error_msg, duration_ms)

    return status


# ── Main loop ──────────────────────────────────────────────────────────────────
def update_schedule_timestamps(items, sid, now_iso, status, next_iso):
    """Return a new list with the given schedule's timestamps updated."""
    updated = []
    for s in items:
        if s.get("id") == sid:
            s = dict(s)
            s["lastRunAt"] = now_iso
            s["lastRunStatus"] = status
            s["nextRunAt"] = next_iso
            # Clear one-shot triggerNow flag
            s.pop("triggerNow", None)
        updated.append(s)
    return updated


def next_run_iso(cron_expr):
    """Return an ISO8601 string for the next cron trigger from now."""
    now = datetime.now()
    # Step forward minute by minute for up to 1 year
    for _ in range(525600):
        now = now.replace(second=0, microsecond=0)
        # Advance by one minute
        mins = now.minute + 1
        now = now.replace(minute=mins % 60)
        if mins >= 60:
            hrs = now.hour + 1
            now = now.replace(hour=hrs % 24)
            if hrs >= 24:
                # Crude day advance — datetime handles month/year rollover
                import datetime as dt_mod
                now = (now + dt_mod.timedelta(days=1)).replace(hour=0, minute=0)
        if cron_matches(cron_expr, now):
            return now.isoformat(timespec="seconds")
    return ""


def main():
    global schedules, reload_requested

    log("KDE AI Chat Scheduler starting up")
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

    log(f"Tick interval: {TICK_SECONDS}s — monitoring {len(schedules)} schedule(s)")

    while True:
        if reload_requested:
            reload_requested = False
            schedules = load_schedules()
            log(f"Schedules reloaded — {len(schedules)} schedule(s) active")

        now = datetime.now()
        now_iso = now.isoformat(timespec="seconds")
        changed = False

        for s in schedules:
            if not s.get("enabled", True):
                continue

            sid = s.get("id", "")
            cron = s.get("cron", "").strip()
            trigger_now = s.get("triggerNow", False)

            should_run = trigger_now
            if not should_run and cron:
                should_run = cron_matches(cron, now)

            if should_run:
                status = run_schedule(s)
                next_iso = next_run_iso(cron) if cron else ""
                schedules = update_schedule_timestamps(schedules, sid, now_iso,
                                                       status or "success", next_iso)
                changed = True

        if changed:
            save_schedules(schedules)

        time.sleep(TICK_SECONDS)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("Interrupted — shutting down")
        cleanup()
        sys.exit(0)
    except Exception as e:
        log(f"Fatal error: {e}", "ERROR")
        cleanup()
        sys.exit(1)
