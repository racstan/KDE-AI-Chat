"""Five-field cron expressions for the ``cron`` schedule rule kind.

Only used for imported or advanced rules. Parsing follows vixie cron:
``*``, lists, ranges, ``/`` steps and English month and weekday names; day
of week 0 and 7 are both Sunday. When both day-of-month and day-of-week are
restricted, a day matches if EITHER matches (the classic OR rule), which
systemd cannot express in one ``OnCalendar=`` line, so ``on_calendar`` emits
two lines for it.
"""
import datetime as dt
from typing import Dict, List, Set, Tuple

_MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
_DOWS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
# systemd weekday names, indexed 0=Sun like the schedule rules.
SYSTEMD_DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
MIN_GAP_MINUTES = 15


def _value(text: str, lo: int, hi: int, names: List[str]) -> int:
    low = text.lower()
    if names and low in names:
        return names.index(low) + (1 if names is _MONTHS else 0)
    if not text.isdigit():
        raise ValueError(f"invalid cron value {text!r}")
    value = int(text)
    if value < lo or value > hi:
        raise ValueError(f"cron value {value} is out of range {lo}-{hi}")
    return value


def parse_field(field: str, lo: int, hi: int, names: List[str] = ()) -> Set[int]:  # type: ignore[assignment]
    """Return the set of values a cron field selects (raises ``ValueError``)."""
    if not field or len(field) > 200:
        raise ValueError("empty cron field")
    values: Set[int] = set()
    for part in field.split(","):
        step = 1
        if "/" in part:
            part, step_text = part.split("/", 1)
            if not step_text.isdigit() or int(step_text) < 1:
                raise ValueError(f"invalid cron step {step_text!r}")
            step = int(step_text)
        if part == "*":
            start, end = lo, hi
        elif "-" in part:
            a, b = part.split("-", 1)
            start, end = _value(a, lo, hi, names), _value(b, lo, hi, names)
            if start > end:
                raise ValueError("cron ranges must not wrap")
        else:
            start = _value(part, lo, hi, names)
            end = hi if step > 1 else start
        values.update(range(start, end + 1, step))
    return values


def parse(expr: str) -> Dict[str, object]:
    """Parse ``m h dom mon dow`` into value sets plus the OR flags."""
    if not isinstance(expr, str) or len(expr) > 300 or any(ord(c) < 32 for c in expr):
        raise ValueError("invalid cron expression")
    fields = expr.split()
    if len(fields) != 5:
        raise ValueError("a cron rule needs 5 fields: minute hour day month weekday")
    dow = parse_field(fields[4], 0, 7, _DOWS)
    if 7 in dow:
        dow = (dow - {7}) | {0}
    parsed = {
        "minutes": parse_field(fields[0], 0, 59),
        "hours": parse_field(fields[1], 0, 23),
        "doms": parse_field(fields[2], 1, 31),
        "months": parse_field(fields[3], 1, 12, _MONTHS),
        "dows": dow,
        "domStar": fields[2].startswith("*"),
        "dowStar": fields[4].startswith("*"),
    }
    _check_gap(parsed)
    return parsed


def _check_gap(parsed: Dict[str, object]) -> None:
    """Reject rules that fire more often than every 15 minutes."""
    minutes = sorted(parsed["minutes"])  # type: ignore[arg-type]
    hours: Set[int] = parsed["hours"]  # type: ignore[assignment]
    gaps = [b - a for a, b in zip(minutes, minutes[1:])]
    if any(((h + 1) % 24) in hours for h in hours):
        gaps.append(minutes[0] + 60 - minutes[-1])
    if gaps and min(gaps) < MIN_GAP_MINUTES:
        raise ValueError("cron rules may not run more often than every 15 minutes")


def day_matches(parsed: Dict[str, object], day: dt.date) -> bool:
    if day.month not in parsed["months"]:  # type: ignore[operator]
        return False
    dom_ok = day.day in parsed["doms"]  # type: ignore[operator]
    dow_ok = ((day.weekday() + 1) % 7) in parsed["dows"]  # type: ignore[operator]
    if parsed["domStar"] or parsed["dowStar"]:
        return dom_ok and dow_ok
    return dom_ok or dow_ok


def times(parsed: Dict[str, object]) -> List[Tuple[int, int]]:
    return [(h, m) for h in sorted(parsed["hours"]) for m in sorted(parsed["minutes"])]  # type: ignore[arg-type]


def _list(values: Set[int], full: int, width: int = 2) -> str:
    if len(values) == full:
        return "*"
    return ",".join(str(v).zfill(width) for v in sorted(values))


def on_calendar(expr: str) -> List[str]:
    """systemd ``OnCalendar=`` values matching the cron expression."""
    p = parse(expr)
    clock = f"{_list(p['hours'], 24)}:{_list(p['minutes'], 60)}:00"  # type: ignore[arg-type]
    months = _list(p["months"], 12)  # type: ignore[arg-type]
    doms = _list(p["doms"], 31)  # type: ignore[arg-type]
    dows = ",".join(SYSTEMD_DAYS[d] for d in sorted(p["dows"], key=lambda d: (d + 6) % 7))  # type: ignore[arg-type]
    if p["domStar"] and p["dowStar"]:
        return [f"*-{months}-* {clock}"]
    if p["dowStar"]:
        return [f"*-{months}-{doms} {clock}"]
    if p["domStar"]:
        return [f"{dows} *-{months}-* {clock}"]
    return [f"*-{months}-{doms} {clock}", f"{dows} *-{months}-* {clock}"]
