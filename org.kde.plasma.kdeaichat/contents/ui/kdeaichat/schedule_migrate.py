"""One-time migration of the old single-cron schedules (schedules.json, v1).

The new definitions go to a NEW file, ``schedules.v2.json``, and the old
``schedules.json`` is left untouched (plus a backup copy,
``schedules.v1.json``), so the old 5-second daemon keeps working until it is
removed (plan step 4). The migration runs once: it only happens while
``schedules.v2.json`` does not exist, under the schedule-store lock.

Rules are rebuilt from the fields the user picked, not from the stored cron
(docs/plan/05-scheduling-design.md section 4). That fixes the old cron bugs
on purpose: "every N weeks" gets ``everyWeeks``, hourly keeps its minute.
Only a cron that differs from what the old dialog would have built (a
hand-edited file) is kept as a ``cron`` rule. ``editedAt`` is the migration
time, so nothing fires for a time before the upgrade.
"""
import datetime as dt
import json
import os
import shutil
from typing import Any, Dict, List, Optional, Tuple

from kdeaichat import schedule_cron
from kdeaichat.schedule_model import (CHAT_ID_RE, DEFAULT_CATCHUP_HOURS, HOUR_STEPS, ID_RE, iso, new_id,
                                      normalize_schedule)
from kdeaichat.schedule_runs import MAX_HISTORY_LIMIT, empty_state

V1_TYPES = ("minutes", "hours", "days", "weeks", "months")


def _local(value: Any) -> Optional[dt.datetime]:
    """An ISO stamp (UTC "Z" from JS toISOString, or naive local) as naive local time."""
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone().replace(tzinfo=None)
    return parsed.replace(microsecond=0)


def _int(value: Any, default: int) -> int:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def build_cron_v1(s: Dict[str, Any]) -> str:
    """Python copy of the old ScheduleDialog.buildCron (time from startDate)."""
    if s.get("taskType") == "single":
        return ""
    start = _local(s.get("startDate"))
    if start is None:
        return ""
    kind, n = s.get("schedType") or "days", _int(s.get("schedEvery"), 0) or 1
    hr, mn = start.hour, start.minute
    if kind == "minutes":
        return f"*/{n} * * * *"
    if kind == "hours":
        return f"0 */{n} * * *"
    if kind == "days":
        return f"{mn} {hr} * * *" if n == 1 else f"{mn} {hr} */{n} * *"
    if kind == "weeks":
        days = s.get("schedDays") or []
        ds = ",".join(sorted(str(d) for d in days)) if days else "1"
        return f"{mn} {hr} * * {ds}"
    if kind == "months":
        dom = s.get("schedDayOfMonth") or 1
        return f"{mn} {hr} {dom} * *" if n == 1 else f"{mn} {hr} {dom} */{n} *"
    return "0 9 * * *"


def _rule_from_fields(s: Dict[str, Any], start: dt.datetime) -> Tuple[Dict[str, Any], bool]:
    """The rule the user picked; the flag asks for a review (value changed)."""
    kind, n = s.get("schedType") or "days", max(1, _int(s.get("schedEvery"), 1))
    hm = f"{start:%H:%M}"
    if kind == "minutes":
        if n >= 60:   # "*/60" and up only ever matched minute 0
            return {"kind": "hourly", "everyHours": 1, "minute": 0}, False
        return {"kind": "minutes", "everyMinutes": max(15, n)}, n < 15
    if kind == "hours":
        if n in HOUR_STEPS:
            return {"kind": "hourly", "everyHours": n, "minute": start.minute}, False
        return {"kind": "cron", "expr": f"{start.minute} */{min(n, 23)} * * *"}, n > 23
    if kind == "weeks":
        days = sorted({d for d in (_int(x, -1) for x in s.get("schedDays") or []) if 0 <= d <= 6}) or [1]
        return {"kind": "weekly", "days": days, "times": [hm], "everyWeeks": min(n, 52)}, n > 52
    if kind == "months":
        dom = min(31, max(1, _int(s.get("schedDayOfMonth"), 1)))
        return {"kind": "monthly", "day": dom, "times": [hm], "everyMonths": min(n, 12)}, n > 12
    return {"kind": "daily", "times": [hm], "everyDays": min(n, 365)}, n > 365 or kind not in V1_TYPES


def _rules(s: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], bool]:
    start = _local(s.get("startDate"))
    cron = " ".join(str(s.get("cron") or "").split())
    if s.get("taskType") == "single":
        return ([{"kind": "once", "at": f"{start:%Y-%m-%dT%H:%M}"}], False) if start else ([], True)
    if cron and cron != build_cron_v1(s):
        try:
            schedule_cron.parse(cron)
            return [{"kind": "cron", "expr": cron}], False
        except ValueError:
            return [], True
    if start is None or (not cron and s.get("schedType") is None):
        return [], True    # no timing at all (e.g. a bare {id, name, message} entry)
    rule, review = _rule_from_fields(s, start)
    return [rule], review


def migrate_schedule(s: Dict[str, Any], settings: Dict[str, Any], now: dt.datetime) -> Dict[str, Any]:
    """One v1 schedule -> a valid v2 definition (disabled + needsReview if incomplete)."""
    rules, review = _rules(s)
    start = _local(s.get("startDate"))
    sid = str(s.get("id") or "")
    chat_id = str(s.get("chatId") or "")
    raw = {
        "id": sid if ID_RE.match(sid) else new_id(),
        "name": str(s.get("name") or "")[:200],
        "enabled": s.get("enabled", True) is not False and not s.get("archived"),
        "archived": bool(s.get("archived")),
        "chatId": chat_id if CHAT_ID_RE.match(chat_id) else "",
        "message": str(s.get("message") or "")[:100000],
        "notify": s.get("notify", True) is not False,
        "rules": rules,
        "startDate": f"{start:%Y-%m-%d}" if start and s.get("taskType") != "single" else None,
        "limitCount": _int(s.get("limitCount"), 0) or None if s.get("limitEnabled") is True else None,
        "catchUp": {"enabled": settings.get("executeMissedSchedules") is True, "withinHours": DEFAULT_CATCHUP_HOURS},
        "createdAt": iso(_local(s.get("createdAt")) or now),
        "editedAt": iso(now),
    }
    if raw["limitCount"] is not None:
        raw["limitCount"] = min(100000, raw["limitCount"])
    if review:
        raw.update(needsReview=True, enabled=False)
    try:
        return normalize_schedule(raw, now=now)
    except ValueError:
        raw.update(needsReview=True, enabled=False)
        return normalize_schedule(raw, now=now)


def migrate_run_state(s: Dict[str, Any], history: List[Any], now: dt.datetime) -> Dict[str, Any]:
    state = empty_state()
    last = _local(s.get("lastRunAt"))
    state["lastRunAt"] = iso(last) if last else None
    state["runCount"] = max(0, _int(s.get("runCount"), 0))
    state["lastStatus"] = str(s["lastRunStatus"])[:200] if s.get("lastRunStatus") else None
    state["finished"] = s.get("taskType") == "single" and last is not None
    state["finishedAt"] = iso(now) if state["finished"] else None
    for entry in history:
        if isinstance(entry, dict) and entry.get("scheduleId") == s.get("id"):
            at = _local(entry.get("timestamp"))
            state["history"].append({"at": iso(at) if at else None, "scheduledFor": None,
                                     "status": str(entry.get("status") or "success")[:200], "reason": "migrated"})
    return state


def migrate_data(data: Any, now: dt.datetime) -> Tuple[Dict[str, Any], Dict[str, Dict[str, Any]]]:
    """The whole v1 file -> (v2 store, run states by schedule id)."""
    if isinstance(data, list):
        data = {"schedules": data}
    data = data if isinstance(data, dict) else {}
    settings = data.get("settings") if isinstance(data.get("settings"), dict) else {}
    history = data.get("history") if isinstance(data.get("history"), list) else []
    limit = min(MAX_HISTORY_LIMIT, max(1, _int(settings.get("historyLimit"), 50)))
    schedules, states, seen = [], {}, set()
    for s in data.get("schedules") or []:
        if not isinstance(s, dict):
            continue
        new = migrate_schedule(s, settings, now)
        if new["id"] in seen:
            new["id"] = new_id()
        seen.add(new["id"])
        schedules.append(new)
        states[new["id"]] = migrate_run_state(s, history, now)
    store = {"version": 2, "settings": {"historyLimit": limit}, "schedules": schedules,
             "migratedFrom": "schedules.json", "migratedAt": iso(now)}
    return store, states


def read_v1(path: str, max_bytes: int) -> Any:
    if os.path.getsize(path) > max_bytes:
        raise ValueError("the old schedule file is too large to migrate")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def backup_v1(path: str, backup: str) -> None:
    """Copy (not move) the old file: the old daemon still reads it until it is removed."""
    if not os.path.exists(backup):
        with open(path, "rb") as src:
            data = src.read()
        fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as dst:
            dst.write(data)
