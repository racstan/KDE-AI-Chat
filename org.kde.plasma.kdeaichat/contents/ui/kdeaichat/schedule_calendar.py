"""Compile schedule rules into systemd ``OnCalendar=`` lines and unit files.

One timer per schedule, one or more ``OnCalendar=`` lines per rule: systemd
fires the timer at the union of the lines (systemd.timer(5)). The lines may
be a superset of the real times: every-N-days/weeks/months fire on every
candidate day and the engine (``schedule_rules.should_run``) filters.

Traps handled here (docs/plan/05-scheduling-design.md section 3):
- commas in the clock part apply per field, so times are only merged into
  one line when they share the minute ("08,12:00:00");
- weekday ranges must not wrap ("Sat..Mon" does not parse): ranges only in
  Mon..Sun order;
- "last day of the month" is ``*-*~01``;
- cron's day-of-month OR day-of-week becomes two lines.
"""
import os
import re
import shutil
import subprocess
from typing import Any, Dict, List, Optional, Tuple

from kdeaichat import schedule_cron

SYSTEMD_DAYS = schedule_cron.SYSTEMD_DAYS
MON_FIRST = [1, 2, 3, 4, 5, 6, 0]
TIMER_PREFIX = "kdeaichat-sched-"
SERVICE_TEMPLATE = "kdeaichat-run@.service"
ACCURACY = "30s"
HEADER = "# Written by KDE AI Chat. Do not edit: the widget rewrites this file.\n"


def _clock_lines(times: List[str]) -> List[str]:
    """``HH:MM`` list -> clock parts, merging only times that share the minute."""
    by_minute: Dict[str, List[str]] = {}
    for t in sorted(times):
        hour, minute = t.split(":")
        by_minute.setdefault(minute, []).append(hour)
    return [f"{','.join(hours)}:{minute}:00" for minute, hours in sorted(by_minute.items())]


def days_spec(days: List[int]) -> str:
    """systemd weekday list, Mon-first, runs of 3+ as non-wrapping ranges."""
    positions = sorted(MON_FIRST.index(d) for d in set(days))
    groups: List[List[int]] = []
    for pos in positions:
        if groups and pos == groups[-1][-1] + 1:
            groups[-1].append(pos)
        else:
            groups.append([pos])
    parts = []
    for group in groups:
        names = [SYSTEMD_DAYS[MON_FIRST[p]] for p in group]
        parts.append(f"{names[0]}..{names[-1]}" if len(names) >= 3 else ",".join(names))
    return ",".join(parts)


def rule_lines(rule: Dict[str, Any]) -> List[str]:
    """``OnCalendar=`` values for one (already validated) rule."""
    kind = rule["kind"]
    if kind == "once":
        return [rule["at"].replace("T", " ") + ":00"]
    if kind == "daily":
        return [f"*-*-* {clock}" for clock in _clock_lines(rule["times"])]
    if kind == "weekly":
        prefix = "" if len(set(rule["days"])) == 7 else days_spec(rule["days"]) + " "
        return [f"{prefix}*-*-* {clock}" for clock in _clock_lines(rule["times"])]
    if kind == "monthly":
        date = "*-*~01" if rule["day"] == "last" else f"*-*-{rule['day']:02d}"
        return [f"{date} {clock}" for clock in _clock_lines(rule["times"])]
    if kind == "hourly":
        hours = range(rule.get("from", 0), rule.get("to", 23) + 1, rule.get("everyHours", 1))
        hour_list = "*" if len(hours) == 24 else ",".join(f"{h:02d}" for h in hours)
        return [f"*-*-* {hour_list}:{rule.get('minute', 0):02d}:00"]
    if kind == "minutes":
        return [f"*-*-* *:00/{rule['everyMinutes']}:00"]
    if kind == "cron":
        return schedule_cron.on_calendar(rule["expr"])
    raise ValueError(f"unknown rule kind {kind!r}")


def schedule_lines(schedule: Dict[str, Any]) -> List[str]:
    """De-duplicated ``OnCalendar=`` values for all rules, in rule order."""
    lines: List[str] = []
    for rule in schedule.get("rules") or []:
        for line in rule_lines(rule):
            if line not in lines:
                lines.append(line)
    return lines


def timer_name(sid: str) -> str:
    return f"{TIMER_PREFIX}{sid}.timer"


def timer_text(schedule: Dict[str, Any], persistent: Optional[bool] = None) -> str:
    """The ``kdeaichat-sched-<id>.timer`` file for an enabled schedule.

    ``Persistent=`` follows the schedule's catch-up option: with catch-up off
    a time missed while powered off or logged out is not woken up for.
    """
    sid = schedule["id"]
    if persistent is None:
        persistent = bool((schedule.get("catchUp") or {}).get("enabled"))
    body = [HEADER.rstrip("\n"), "[Unit]", f"Description=KDE AI Chat schedule {sid}", "", "[Timer]"]
    body += [f"OnCalendar={line}" for line in schedule_lines(schedule)]
    body += [f"Persistent={'true' if persistent else 'false'}", f"AccuracySec={ACCURACY}",
             f"Unit=kdeaichat-run@{sid}.service", "", "[Install]", "WantedBy=timers.target", ""]
    return "\n".join(body)


def _exec_quote(arg: str) -> str:
    if any(ord(c) < 32 for c in arg):
        raise ValueError("unit paths must not contain control characters")
    return '"' + arg.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%") + '"'


def helper_path() -> str:
    """The installed kde_ai_helper.py next to this package (user or system install)."""
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "kde_ai_helper.py")


def python_path() -> str:
    return shutil.which("python3") or "/usr/bin/python3"


def service_text(helper: Optional[str] = None, python: Optional[str] = None) -> str:
    """The shared ``kdeaichat-run@.service`` template (one place for the helper path)."""
    exec_start = f"{_exec_quote(python or python_path())} {_exec_quote(helper or helper_path())} run_schedule %i"
    return "\n".join([HEADER.rstrip("\n"), "[Unit]", "Description=KDE AI Chat scheduled prompt %i", "",
                      "[Service]", "Type=oneshot", f"ExecStart={exec_start}", "TimeoutStartSec=30min", ""])


_ELAPSE = re.compile(r"^\s*(?:Next elapse|Iteration #\d+|Iter\. #\d+):\s+\S+\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")


def analyze_binary() -> Optional[str]:
    return os.environ.get("KDEAICHAT_SYSTEMD_ANALYZE") or shutil.which("systemd-analyze")


def analyze(line: str, iterations: int = 1, base_time: Optional[str] = None) -> Tuple[bool, List[str]]:
    """Run ``systemd-analyze calendar`` on one line (argv list, no shell).

    Returns ``(parsed, elapses)`` with local ``YYYY-MM-DD HH:MM:SS`` strings;
    an empty list means "never". Raises ``FileNotFoundError`` without the binary.
    """
    binary = analyze_binary()
    if not binary:
        raise FileNotFoundError("systemd-analyze")
    argv = [binary, "calendar", f"--iterations={iterations}"]
    if base_time:
        argv.append(f"--base-time={base_time}")
    proc = subprocess.run(argv + ["--", line], capture_output=True, text=True, timeout=20)
    if proc.returncode != 0 and "never" not in proc.stdout:
        return False, []
    return True, [m.group(1) for m in map(_ELAPSE.match, proc.stdout.splitlines()) if m]


def check_lines(lines: List[str]) -> List[str]:
    """Problems systemd itself finds with the lines (empty if fine or unavailable)."""
    problems = []
    for line in lines:
        try:
            parsed, elapses = analyze(line)
        except (FileNotFoundError, OSError, subprocess.SubprocessError):
            return []
        if not parsed:
            problems.append(f"systemd cannot read the time rule {line!r}")
        elif not elapses:
            problems.append(f"the time rule {line!r} never fires again")
    return problems
