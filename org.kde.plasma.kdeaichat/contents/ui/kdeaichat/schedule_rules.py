"""The schedule occurrence engine: when does a schedule fire?

One engine serves the editor preview ("next 3 runs") and the background
job's decision. systemd only wakes the job (its ``OnCalendar=`` lines are a
superset of the real times: every-N-days/weeks/months are filtered here),
and ``should_run`` decides whether that wake-up is a run, a skip or a missed
run. Rules work on naive local wall-clock time. A local time that does not
exist (the spring daylight-saving gap) is skipped, as systemd does.

Pure stdlib, no I/O: tests drive it with fixed ``now`` values.
"""
import calendar
import datetime as dt
import time
from typing import Any, Dict, List, Optional

from kdeaichat import schedule_cron
from kdeaichat.schedule_model import anchor_date, parse_local

# A wake-up later than this after its occurrence counts as late (catch-up rules apply).
ON_TIME_GRACE = dt.timedelta(minutes=10)
LOOKBACK_DAYS = 800
HORIZON_DAYS = 5 * 366 + 1


def _hm(text: str) -> dt.time:
    hours, minutes = text.split(":")
    return dt.time(int(hours), int(minutes))


def exists_locally(moment: dt.datetime) -> bool:
    """False for wall-clock times skipped by a daylight-saving change."""
    stamp = time.mktime(moment.timetuple()[:8] + (-1,))
    return dt.datetime.fromtimestamp(stamp).replace(microsecond=0) == moment


def _monday(day: dt.date) -> dt.date:
    return day - dt.timedelta(days=day.weekday())


def rule_times(rule: Dict[str, Any], day: dt.date, anchor: dt.date) -> List[dt.time]:
    """Wall-clock times on ``day`` selected by one rule, including every-N guards."""
    kind = rule["kind"]
    if kind == "once":
        at = parse_local(rule["at"], "the date and time")
        return [at.time()] if at.date() == day else []
    if kind == "daily":
        if (day - anchor).days % rule.get("everyDays", 1):
            return []
        return [_hm(t) for t in rule["times"]]
    if kind == "weekly":
        if (day.weekday() + 1) % 7 not in rule["days"]:
            return []
        if ((_monday(day) - _monday(anchor)).days // 7) % rule.get("everyWeeks", 1):
            return []
        return [_hm(t) for t in rule["times"]]
    if kind == "monthly":
        last = calendar.monthrange(day.year, day.month)[1]
        wanted = last if rule["day"] == "last" else rule["day"]
        if day.day != wanted:
            return []
        if ((day.year * 12 + day.month) - (anchor.year * 12 + anchor.month)) % rule.get("everyMonths", 1):
            return []
        return [_hm(t) for t in rule["times"]]
    if kind == "hourly":
        start, step = rule.get("from", 0), rule.get("everyHours", 1)
        return [dt.time(h, rule.get("minute", 0)) for h in range(start, rule.get("to", 23) + 1, step)]
    if kind == "minutes":
        return [dt.time(h, m) for h in range(24) for m in range(0, 60, rule["everyMinutes"])]
    if kind == "cron":
        parsed = schedule_cron.parse(rule["expr"])
        if not schedule_cron.day_matches(parsed, day):
            return []
        return [dt.time(h, m) for h, m in schedule_cron.times(parsed)]
    raise ValueError(f"unknown rule kind {kind!r}")


def _bounds(schedule: Dict[str, Any]):
    start = schedule.get("startDate")
    end = schedule.get("endDate")
    return (dt.date.fromisoformat(start) if start else None,
            dt.date.fromisoformat(end) if end else None)


def day_occurrences(schedule: Dict[str, Any], day: dt.date, *, bounded: bool = True) -> List[dt.datetime]:
    """Sorted, de-duplicated instants of all rules on one day."""
    start, end = _bounds(schedule)
    if bounded and ((start and day < start) or (end and day > end)):
        return []
    anchor = anchor_date(schedule)
    found = set()
    for rule in schedule.get("rules") or []:
        for moment in rule_times(rule, day, anchor):
            found.add(dt.datetime.combine(day, moment))
    return sorted(m for m in found if exists_locally(m))


def next_occurrences(schedule: Dict[str, Any], after: dt.datetime, count: int = 3,
                     horizon_days: int = HORIZON_DAYS) -> List[dt.datetime]:
    """The next ``count`` instants strictly after ``after`` (within the horizon)."""
    result: List[dt.datetime] = []
    _, end = _bounds(schedule)
    day = after.date()
    for _ in range(horizon_days):
        if end and day > end:
            break
        result.extend(m for m in day_occurrences(schedule, day) if m > after)
        if len(result) >= count:
            break
        day += dt.timedelta(days=1)
    return result[:count]


def latest_occurrence(schedule: Dict[str, Any], now: dt.datetime, *, bounded: bool = True,
                      lookback_days: int = LOOKBACK_DAYS) -> Optional[dt.datetime]:
    """The latest instant at or before ``now`` (``bounded=False`` ignores start/end dates)."""
    day = now.date()
    for _ in range(lookback_days):
        past = [m for m in day_occurrences(schedule, day, bounded=bounded) if m <= now]
        if past:
            return past[-1]
        day -= dt.timedelta(days=1)
    return None


def _stamp(value: Any) -> Optional[dt.datetime]:
    try:
        return dt.datetime.fromisoformat(value) if value else None
    except (TypeError, ValueError):
        return None


def is_finished(schedule: Dict[str, Any], run_state: Dict[str, Any]) -> bool:
    """Finished (no more runs) unless the schedule was edited after it finished."""
    if not run_state.get("finished"):
        return False
    finished_at, edited = _stamp(run_state.get("finishedAt")), _stamp(schedule.get("editedAt"))
    return finished_at is None or edited is None or finished_at >= edited


SKIP_REASONS = ("disabled", "finished", "limit-reached", "not-due", "before-start", "after-end",
                "already-ran", "edited-after", "missed-no-catchup", "outside-catchup-window")


def should_run(schedule: Dict[str, Any], run_state: Dict[str, Any], now: dt.datetime) -> Dict[str, Any]:
    """Decide what a timer wake-up at ``now`` means.

    Returns ``{"action": "run"|"skip", "reason": ..., "occurrence": iso|None,
    "late": bool}``. ``reason`` is ``"due"`` or ``"catch-up"`` for a run, else
    one of ``SKIP_REASONS``. Missed occurrences collapse into the latest one.
    """
    def decide(action: str, reason: str, occ: Optional[dt.datetime] = None, late: bool = False):
        return {"action": action, "reason": reason, "occurrence": occ.isoformat() if occ else None, "late": late}

    if not schedule.get("enabled", True) or schedule.get("archived"):
        return decide("skip", "disabled")
    if is_finished(schedule, run_state):
        return decide("skip", "finished")
    limit = schedule.get("limitCount")
    if limit and int(run_state.get("runCount") or 0) >= int(limit):
        return decide("skip", "limit-reached")
    start, end = _bounds(schedule)
    if start and now.date() < start:
        return decide("skip", "before-start", latest_occurrence(schedule, now, bounded=False))
    occ = latest_occurrence(schedule, now)
    if end and now.date() > end and (occ is None or now - occ > ON_TIME_GRACE):
        return decide("skip", "after-end", latest_occurrence(schedule, now, bounded=False))
    if occ is None:
        return decide("skip", "not-due")
    last = _stamp(run_state.get("lastScheduledFor"))
    if last is not None and occ <= last:
        return decide("skip", "already-ran", occ)
    edited = _stamp(schedule.get("editedAt"))
    if edited is not None and occ <= edited:
        return decide("skip", "edited-after", occ)
    lateness = now - occ
    if lateness <= ON_TIME_GRACE:
        return decide("run", "due", occ)
    catch_up = schedule.get("catchUp") or {}
    if not catch_up.get("enabled"):
        return decide("skip", "missed-no-catchup", occ, True)
    if lateness > dt.timedelta(hours=int(catch_up.get("withinHours") or 12)):
        return decide("skip", "outside-catchup-window", occ, True)
    return decide("run", "catch-up", occ, True)


def has_future(schedule: Dict[str, Any], now: dt.datetime) -> bool:
    return bool(next_occurrences(schedule, now, 1))
