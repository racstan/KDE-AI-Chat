"""Plain-language one-line summaries and editor warnings for schedule rules.

Examples: "Mon 16:00", "Tue–Sun 15:00", "Every 2 days at 09:00",
"Monthly on the last day at 18:00". English only for now: the widget shows
these as-is (the UI task may move them to a translated JS module).
"""
import calendar
import datetime as dt
from typing import Any, Dict, List

from kdeaichat import schedule_cron
from kdeaichat.schedule_rules import next_occurrences

DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
MON_FIRST = [1, 2, 3, 4, 5, 6, 0]
DASH = "–"


def days_text(days: List[int]) -> str:
    """Mon-first weekday list with runs of 3+ as ranges: "Mon–Fri", "Mon, Wed"."""
    if len(set(days)) == 7:
        return "Every day"
    if sorted(days) == [0, 6]:
        return "Weekends"
    positions = sorted(MON_FIRST.index(d) for d in set(days))
    groups: List[List[int]] = []
    for pos in positions:
        if groups and pos == groups[-1][-1] + 1:
            groups[-1].append(pos)
        else:
            groups.append([pos])
    parts = []
    for group in groups:
        names = [DAY_NAMES[MON_FIRST[p]] for p in group]
        parts.append(f"{names[0]}{DASH}{names[-1]}" if len(names) >= 3 else ", ".join(names))
    return ", ".join(parts)


def _every(n: int, unit: str) -> str:
    return f"Every {unit}" if n == 1 else f"Every {n} {unit}s"


def _ordinal(n: int) -> str:
    suffix = "th" if 10 <= n % 100 <= 20 else {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suffix}"


def rule_summary(rule: Dict[str, Any]) -> str:
    kind = rule["kind"]
    times = ", ".join(rule.get("times") or [])
    if kind == "once":
        at = dt.datetime.fromisoformat(rule["at"])
        return f"Once on {DAY_NAMES[(at.weekday() + 1) % 7]} {at.day} {calendar.month_abbr[at.month]} {at.year} at {at:%H:%M}"
    if kind == "daily":
        return f"{_every(rule.get('everyDays', 1), 'day')} at {times}"
    if kind == "weekly":
        text = f"{days_text(rule['days'])} {times}"
        every = rule.get("everyWeeks", 1)
        return text if every == 1 else f"Every {every} weeks: {text}"
    if kind == "monthly":
        day = "the last day" if rule["day"] == "last" else f"the {_ordinal(rule['day'])}"
        every = rule.get("everyMonths", 1)
        prefix = "Monthly" if every == 1 else f"Every {every} months"
        return f"{prefix} on {day} at {times}"
    if kind == "hourly":
        text = f"{_every(rule.get('everyHours', 1), 'hour')} at :{rule.get('minute', 0):02d}"
        start, end = rule.get("from", 0), rule.get("to", 23)
        if (start, end) != (0, 23):
            text += f" ({start:02d}:00{DASH}{end:02d}:59)"
        return text
    if kind == "minutes":
        return _every(rule["everyMinutes"], "minute")
    return f"Cron: {rule['expr']}"


def summary(schedule: Dict[str, Any]) -> str:
    return "; ".join(rule_summary(r) for r in schedule.get("rules") or []) or "No rules"


def _rule_hm(rule: Dict[str, Any]) -> List[str]:
    if rule["kind"] == "once":
        return [rule["at"][11:16]]
    if rule["kind"] == "hourly":
        return [f"{h:02d}:{rule.get('minute', 0):02d}" for h in range(rule.get("from", 0), rule.get("to", 23) + 1,
                                                                         rule.get("everyHours", 1))]
    if rule["kind"] == "cron":
        parsed = schedule_cron.parse(rule["expr"])
        return [f"{h:02d}:{m:02d}" for h, m in schedule_cron.times(parsed)]
    return list(rule.get("times") or [])


def warnings(schedule: Dict[str, Any], now: dt.datetime) -> List[str]:
    """Things the editor should point out; none of them block saving."""
    out: List[str] = []
    rules = schedule.get("rules") or []
    if any(r["kind"] != "minutes" and any("02:00" <= t <= "02:59" for t in _rule_hm(r)) for r in rules):
        out.append("Times between 02:00 and 03:00 are skipped or repeated once a year when the clocks change.")
    for rule in rules:
        if rule["kind"] == "monthly" and rule["day"] != "last" and rule["day"] >= 29:
            out.append(f"Months without a day {rule['day']} are skipped; use \"Last day\" to run every month.")
        if rule["kind"] == "minutes" and 60 % rule["everyMinutes"]:
            out.append(f"Every {rule['everyMinutes']} minutes restarts at :00 each hour.")
    if rules and not next_occurrences(schedule, now, 1):
        out.append("This schedule never runs.")
    return out
