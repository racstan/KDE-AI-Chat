"""Schedule definitions (``schedules.v2.json``) and the widget's schedule commands.

Only the widget writes definitions (through these commands); the job only
writes run state (schedule_runs). Every mutation holds the schedule-store
lock around its read/modify/write, then syncs the systemd units.

Commands (payload -> one JSON object on stdout):
- ``schedules_list {}`` -> ``{ok, schedules: [def + summary, nextRuns, runState]}, settings}``
- ``schedule_preview {schedule, count?}`` -> ``{ok, error?, summary, rules, nextRuns, warnings}``
- ``schedule_save {schedule}`` -> ``{ok, error?, schedule, units}``
- ``schedule_delete {id}`` -> ``{ok, units}``
- ``schedule_history {id}`` -> ``{ok, runState}``
- ``schedules_sync {}`` -> ``{ok, units}`` (units match definitions; stray timers removed)
"""
import datetime as dt
import json
import os
from typing import Any, Dict, List, Optional

from kdeaichat import chats, schedule_migrate, schedule_units
from kdeaichat.common import MAX_SCHEDULE_STORE_BYTES, atomic_write_json, schedule_store_lock, schedules_path
from kdeaichat.schedule_calendar import check_lines, schedule_lines
from kdeaichat.schedule_model import (DEFAULT_HISTORY_LIMIT, ID_RE, iso, normalize_schedule, now_local,
                                      timing_changed)
from kdeaichat.schedule_rules import next_occurrences
from kdeaichat.schedule_runs import (history_limit, load_run_state, remove_run_state, run_state_lock,
                                     run_state_path, save_run_state)
from kdeaichat.schedule_text import rule_summary, summary, warnings

MAX_SCHEDULES = 500


def store_path() -> str:
    return os.path.join(chats.data_root(), "schedules.v2.json")


def backup_path() -> str:
    return os.path.join(chats.data_root(), "schedules.v1.json")


class LegacyScheduleError(Exception):
    """The old schedules.json could not be migrated; it was left untouched (message: the short reason)."""


def empty_store() -> Dict[str, Any]:
    return {"version": 2, "settings": {"historyLimit": DEFAULT_HISTORY_LIMIT}, "schedules": []}


def read_store() -> Optional[Dict[str, Any]]:
    path = store_path()
    if not os.path.exists(path):
        return None
    if os.path.getsize(path) > MAX_SCHEDULE_STORE_BYTES:
        raise ValueError("the schedule file is too large")
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict) or data.get("version") != 2:
        raise ValueError("the schedule file is not a version 2 schedule file")
    store = empty_store()
    store.update({k: v for k, v in data.items() if k in ("settings", "migratedFrom", "migratedAt")})
    if not isinstance(store["settings"], dict):
        store["settings"] = {"historyLimit": DEFAULT_HISTORY_LIMIT}
    store["schedules"] = [s for s in data.get("schedules") or []
                          if isinstance(s, dict) and isinstance(s.get("id"), str) and ID_RE.match(s["id"])]
    return store


def _migrate_locked(now: dt.datetime) -> Dict[str, Any]:
    """Create schedules.v2.json (from schedules.json when there is one). Caller holds the lock."""
    legacy = schedules_path()
    if not os.path.exists(legacy):
        store = empty_store()
        atomic_write_json(store_path(), store)
        return store
    try:
        store, states = schedule_migrate.migrate_data(
            schedule_migrate.read_v1(legacy, MAX_SCHEDULE_STORE_BYTES), now)
    except Exception as e:   # malformed old file: report it, leave it alone, try again next time
        raise LegacyScheduleError(str(e)[:200] or type(e).__name__) from e
    schedule_migrate.backup_v1(legacy, backup_path())
    limit = history_limit(store["settings"])
    for sid, state in states.items():
        with run_state_lock(sid):
            if not os.path.exists(run_state_path(sid)):
                save_run_state(sid, state, limit)
    atomic_write_json(store_path(), store)
    return store


def load_store(now: Optional[dt.datetime] = None) -> Dict[str, Any]:
    """The definitions; migrates the old file the first time (idempotent)."""
    store = read_store()
    if store is not None:
        return store
    with schedule_store_lock():
        store = read_store()
        return store if store is not None else _migrate_locked(now or now_local())


def find(store: Dict[str, Any], sid: str) -> Optional[Dict[str, Any]]:
    return next((s for s in store["schedules"] if s.get("id") == sid), None)


def _sync(store: Dict[str, Any], now: dt.datetime, ensure_enabled: bool = False) -> Dict[str, Any]:
    valid = []
    for s in store["schedules"]:
        try:
            valid.append(normalize_schedule(s, now=now))
        except ValueError:
            continue
    states = {s["id"]: load_run_state(s["id"]) for s in valid}
    return schedule_units.sync_units(valid, states, now=now, ensure_enabled=ensure_enabled)


def _out(data: Dict[str, Any]) -> None:
    print(json.dumps(data, ensure_ascii=False))


def _describe(schedule: Dict[str, Any], now: dt.datetime, count: int = 3) -> Dict[str, Any]:
    return {"summary": summary(schedule), "rules": [rule_summary(r) for r in schedule["rules"]],
            "nextRuns": [iso(m) for m in next_occurrences(schedule, now, count)],
            "warnings": warnings(schedule, now)}


def cmd_schedules_list(payload: Dict[str, Any]) -> None:
    now = now_local()
    try:
        store = load_store(now)
    except LegacyScheduleError as e:
        _out({"ok": True, "schedules": [], "settings": empty_store()["settings"], "migrationError": str(e)})
        return
    out: List[Dict[str, Any]] = []
    for s in store["schedules"]:
        item = dict(s)
        try:
            info = _describe(normalize_schedule(s, now=now), now)
            item.update(summary=info["summary"], nextRuns=info["nextRuns"], warnings=info["warnings"])
        except ValueError as e:
            item.update(summary="", nextRuns=[], warnings=[str(e)])
        state = load_run_state(s["id"])
        state.pop("history", None)
        item["runState"] = state
        out.append(item)
    _out({"ok": True, "schedules": out, "settings": store["settings"]})


def cmd_schedule_preview(payload: Dict[str, Any]) -> None:
    """Summary, next runs and warnings for an unsaved draft (the editor's live line)."""
    now = now_local()
    count = payload.get("count")
    count = min(20, max(1, count)) if isinstance(count, int) and not isinstance(count, bool) else 3
    try:
        draft = dict(payload.get("schedule") or {})
        draft.setdefault("editedAt", iso(now))
        schedule = normalize_schedule({**draft, "enabled": False}, now=now)
    except (ValueError, TypeError) as e:
        _out({"ok": False, "error": str(e)})
        return
    _out({"ok": True, **_describe(schedule, now, count)})


def cmd_schedule_save(payload: Dict[str, Any]) -> None:
    now = now_local()
    raw = payload.get("schedule")
    try:
        if not isinstance(raw, dict):
            raise ValueError("schedule is required")
        with schedule_store_lock():
            store = read_store() or _migrate_locked(now)
            old = find(store, raw.get("id")) if raw.get("id") else None
            merged = dict(raw)
            merged.pop("needsReview", None)
            merged["createdAt"] = (old or {}).get("createdAt") or iso(now)
            merged["editedAt"] = (old or {}).get("editedAt") or iso(now)
            schedule = normalize_schedule(merged, now=now)
            if timing_changed(old, schedule):
                schedule["editedAt"] = iso(now)
            if schedule["enabled"] and not schedule["archived"]:
                problems = check_lines(schedule_lines(schedule))
                if not next_occurrences(schedule, now, 1):
                    problems.append("this schedule never runs again")
                if problems:
                    raise ValueError("; ".join(problems))
            if old is None and len(store["schedules"]) >= MAX_SCHEDULES:
                raise ValueError(f"at most {MAX_SCHEDULES} schedules")
            store["schedules"] = [schedule if s is old else s for s in store["schedules"]]
            if old is None:
                store["schedules"].append(schedule)
            atomic_write_json(store_path(), store)
            units = _sync(store, now)
    except ValueError as e:
        _out({"ok": False, "error": str(e)})
        return
    _out({"ok": True, "schedule": schedule, "units": units})


def delete_schedules(match, now: Optional[dt.datetime] = None) -> Dict[str, Any]:
    """Remove the definitions ``match(schedule)`` selects, their run state and timers."""
    now = now or now_local()
    with schedule_store_lock():
        store = read_store() or _migrate_locked(now)
        gone = [s["id"] for s in store["schedules"] if match(s)]
        if gone:
            store["schedules"] = [s for s in store["schedules"] if s["id"] not in gone]
            atomic_write_json(store_path(), store)
        units = _sync(store, now)
    for sid in gone:
        remove_run_state(sid)
    return {"removed": gone, "units": units}


def cmd_schedule_delete(payload: Dict[str, Any]) -> None:
    sid = payload.get("id")
    if not isinstance(sid, str) or not ID_RE.match(sid):
        _out({"ok": False, "error": "invalid schedule id"})
        return
    _out({"ok": True, **delete_schedules(lambda s: s.get("id") == sid)})


def cmd_schedule_history(payload: Dict[str, Any]) -> None:
    sid = payload.get("id")
    if not isinstance(sid, str) or not ID_RE.match(sid):
        _out({"ok": False, "error": "invalid schedule id"})
        return
    _out({"ok": True, "runState": load_run_state(sid)})


def sync_all(ensure_enabled: bool = True) -> Dict[str, Any]:
    """Units for every definition (migrating the old file first if needed); stray timers removed."""
    now = now_local()
    with schedule_store_lock():
        store = read_store() or _migrate_locked(now)
        return _sync(store, now, ensure_enabled=ensure_enabled)


def cmd_schedules_sync(payload: Dict[str, Any]) -> None:
    try:
        units = sync_all(ensure_enabled=True)
    except LegacyScheduleError as e:
        _out({"ok": False, "migrationError": str(e)})
        return
    _out({"ok": not units["errors"], "units": units})


COMMANDS = {
    "schedules_list": cmd_schedules_list,
    "schedule_preview": cmd_schedule_preview,
    "schedule_save": cmd_schedule_save,
    "schedule_delete": cmd_schedule_delete,
    "schedule_history": cmd_schedule_history,
    "schedules_sync": cmd_schedules_sync,
}
