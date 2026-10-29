"""Schedule definitions (schedules.v2.json): validation and normalisation.

A schedule fires at the union of its ``rules``. Times are local wall-clock
``HH:MM`` and dates are local ``YYYY-MM-DD`` (naive, no time zone). Weekdays
are 0=Sun..6=Sat like JavaScript's ``getDay()``. See
docs/plan/05-scheduling-design.md section 2 for the format.

``normalize_schedule`` is the single gate: everything the widget sends goes
through it and comes out with only known keys and valid values, or raises
``ValueError`` with a message that can be shown to the user.
"""
import datetime as dt
import re
import uuid
from typing import Any, Dict, List, Optional

from kdeaichat import schedule_cron

ID_RE = re.compile(r"^[A-Za-z0-9-]{1,64}\Z")
CHAT_ID_RE = re.compile(r"^[A-Za-z0-9._:%-]{1,128}\Z")
TIME_RE = re.compile(r"^([01][0-9]|2[0-3]):([0-5][0-9])\Z")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}\Z")
DATETIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?\Z")

KINDS = ("once", "daily", "weekly", "monthly", "hourly", "minutes", "cron")
HOUR_STEPS = (1, 2, 3, 4, 6, 8, 12)
MIN_EVERY_MINUTES = 15
MAX_RULES = 20
MAX_TIMES = 24
MAX_MESSAGE = 100000
DEFAULT_CATCHUP_HOURS = 12
DEFAULT_HISTORY_LIMIT = 50


def new_id() -> str:
    return str(uuid.uuid4())


def now_local() -> dt.datetime:
    return dt.datetime.now().replace(microsecond=0)


def iso(value: dt.datetime) -> str:
    return value.replace(microsecond=0).isoformat()


def parse_date(value: Any, what: str) -> dt.date:
    if not isinstance(value, str) or not DATE_RE.match(value):
        raise ValueError(f"{what} must be a date like 2026-11-03")
    try:
        return dt.date.fromisoformat(value)
    except ValueError:
        raise ValueError(f"{what} {value} does not exist") from None


def parse_local(value: Any, what: str) -> dt.datetime:
    """A naive local date-time ``YYYY-MM-DDTHH:MM[:SS]``."""
    if not isinstance(value, str) or not DATETIME_RE.match(value):
        raise ValueError(f"{what} must be a date and time like 2026-11-03T14:30")
    try:
        return dt.datetime.fromisoformat(value)
    except ValueError:
        raise ValueError(f"{what} {value} does not exist") from None


def parse_time(value: Any) -> str:
    if not isinstance(value, str) or not TIME_RE.match(value):
        raise ValueError(f"time {value!r} must be HH:MM (00:00-23:59)")
    return value


def _int(value: Any, what: str, lo: int, hi: int, default: Optional[int] = None) -> int:
    if value is None and default is not None:
        return default
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError(f"{what} must be a number")
    try:
        number = int(str(value).strip())
    except ValueError:
        raise ValueError(f"{what} must be a whole number") from None
    if number < lo or number > hi:
        raise ValueError(f"{what} must be between {lo} and {hi}")
    return number


def _bool(value: Any, default: bool) -> bool:
    return value if isinstance(value, bool) else default


def _times(rule: Dict[str, Any]) -> List[str]:
    times = rule.get("times")
    if not isinstance(times, list) or not times:
        raise ValueError("add at least one time")
    if len(times) > MAX_TIMES:
        raise ValueError(f"a rule can have at most {MAX_TIMES} times")
    return sorted({parse_time(t) for t in times})


def _days(rule: Dict[str, Any]) -> List[int]:
    days = rule.get("days")
    if not isinstance(days, list) or not days:
        raise ValueError("pick at least one weekday")
    return sorted({_int(d, "weekday", 0, 6) for d in days})


def normalize_rule(rule: Any) -> Dict[str, Any]:
    """Validate one rule and return it with only its kind's keys."""
    if not isinstance(rule, dict):
        raise ValueError("a rule must be an object")
    kind = rule.get("kind")
    if kind not in KINDS:
        raise ValueError(f"unknown rule kind {kind!r}")
    if kind == "once":
        at = parse_local(rule.get("at"), "the date and time")
        return {"kind": "once", "at": at.strftime("%Y-%m-%dT%H:%M")}
    if kind == "daily":
        return {"kind": "daily", "times": _times(rule),
                "everyDays": _int(rule.get("everyDays"), "every N days", 1, 365, 1)}
    if kind == "weekly":
        return {"kind": "weekly", "days": _days(rule), "times": _times(rule),
                "everyWeeks": _int(rule.get("everyWeeks"), "every N weeks", 1, 52, 1)}
    if kind == "monthly":
        day = rule.get("day")
        day = "last" if day == "last" else _int(day, "day of the month", 1, 31)
        return {"kind": "monthly", "day": day, "times": _times(rule),
                "everyMonths": _int(rule.get("everyMonths"), "every N months", 1, 12, 1)}
    if kind == "hourly":
        every = _int(rule.get("everyHours"), "every N hours", 1, 12, 1)
        if every not in HOUR_STEPS:
            raise ValueError("every N hours must be 1, 2, 3, 4, 6, 8 or 12")
        start = _int(rule.get("from"), "first hour", 0, 23, 0)
        end = _int(rule.get("to"), "last hour", 0, 23, 23)
        if end < start:
            raise ValueError("the last hour must not be before the first hour")
        return {"kind": "hourly", "everyHours": every, "minute": _int(rule.get("minute"), "minute", 0, 59, 0),
                "from": start, "to": end}
    if kind == "minutes":
        every = _int(rule.get("everyMinutes"), "every N minutes", 1, 59)
        if every < MIN_EVERY_MINUTES:
            raise ValueError(f"schedules can run at most every {MIN_EVERY_MINUTES} minutes")
        return {"kind": "minutes", "everyMinutes": every}
    expr = " ".join(str(rule.get("expr", "")).split())
    schedule_cron.parse(expr)
    return {"kind": "cron", "expr": expr}


def _catch_up(value: Any) -> Dict[str, Any]:
    if isinstance(value, bool):
        return {"enabled": value, "withinHours": DEFAULT_CATCHUP_HOURS}
    if value is None:
        value = {}
    if not isinstance(value, dict):
        raise ValueError("catchUp must be an object")
    return {"enabled": _bool(value.get("enabled"), False),
            "withinHours": _int(value.get("withinHours"), "catch-up window (hours)", 1, 168, DEFAULT_CATCHUP_HOURS)}


def _text(value: Any, what: str, limit: int) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        raise ValueError(f"{what} must be text")
    if len(value) > limit or "\x00" in value:
        raise ValueError(f"{what} is too long")
    return value


def normalize_schedule(raw: Any, *, now: Optional[dt.datetime] = None) -> Dict[str, Any]:
    """Validate a schedule definition; returns a clean copy (raises ``ValueError``)."""
    if not isinstance(raw, dict):
        raise ValueError("a schedule must be an object")
    sid = raw.get("id") or new_id()
    if not isinstance(sid, str) or not ID_RE.match(sid):
        raise ValueError("schedule id must be 1-64 letters, digits or dashes")
    enabled = _bool(raw.get("enabled"), True)
    archived = _bool(raw.get("archived"), False)
    rules_raw = raw.get("rules") if raw.get("rules") is not None else []
    if not isinstance(rules_raw, list) or len(rules_raw) > MAX_RULES:
        raise ValueError(f"a schedule can have at most {MAX_RULES} rules")
    rules = [normalize_rule(r) for r in rules_raw]
    chat_id = _text(raw.get("chatId"), "chat id", 128)
    if chat_id and not CHAT_ID_RE.match(chat_id):
        raise ValueError("invalid chat id")
    message = _text(raw.get("message"), "message", MAX_MESSAGE)
    if enabled and not archived:
        if not rules:
            raise ValueError("add at least one rule")
        if not chat_id:
            raise ValueError("pick a chat for this schedule")
        if not message.strip():
            raise ValueError("write the message to send")
    start = raw.get("startDate") or None
    end = raw.get("endDate") or None
    if start is not None:
        parse_date(start, "start date")
    if end is not None:
        parse_date(end, "end date")
    if start and end and end < start:
        raise ValueError("the end date must not be before the start date")
    limit = raw.get("limitCount")
    stamp = iso(now or now_local())
    out = {
        "id": sid,
        "name": _text(raw.get("name"), "name", 200),
        "enabled": enabled,
        "archived": archived,
        "chatId": chat_id,
        "message": message,
        "notify": _bool(raw.get("notify"), True),
        "rules": rules,
        "startDate": start,
        "endDate": end,
        "limitCount": None if limit in (None, "", 0) else _int(limit, "run limit", 1, 100000),
        "catchUp": _catch_up(raw.get("catchUp")),
        "createdAt": _stamp(raw.get("createdAt")) or stamp,
        "editedAt": _stamp(raw.get("editedAt")) or stamp,
    }
    if _bool(raw.get("needsReview"), False):
        out["needsReview"] = True
    return out


def _stamp(value: Any) -> Optional[str]:
    if not value:
        return None
    try:
        return iso(parse_local(value, "timestamp"))
    except ValueError:
        return None


TIMING_KEYS = ("enabled", "archived", "rules", "startDate", "endDate", "catchUp", "limitCount")


def timing_changed(old: Optional[Dict[str, Any]], new: Dict[str, Any]) -> bool:
    """True when an edit changes when the schedule fires (so ``editedAt`` moves)."""
    return old is None or any(old.get(k) != new.get(k) for k in TIMING_KEYS)


def anchor_date(schedule: Dict[str, Any]) -> dt.date:
    """The day every-N-days/weeks/months counts from: startDate, else createdAt."""
    if schedule.get("startDate"):
        return dt.date.fromisoformat(schedule["startDate"])
    created = schedule.get("createdAt") or schedule.get("editedAt")
    if created:
        return dt.datetime.fromisoformat(created).date()
    return now_local().date()
