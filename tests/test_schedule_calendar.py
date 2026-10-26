"""Rules -> systemd OnCalendar lines and unit files, cross-checked with systemd-analyze."""
import datetime as dt
import shutil

import pytest

from kdeaichat import schedule_calendar as cal
from kdeaichat.schedule_model import normalize_schedule
from kdeaichat.schedule_rules import next_occurrences

NOW = dt.datetime(2026, 10, 26, 8, 22)
BASE = "2026-10-26 08:22:00"
HAS_ANALYZE = shutil.which("systemd-analyze") is not None


def sched(rules, **over):
    raw = {"id": "8c1f-news", "chatId": "c", "message": "m", "rules": rules,
           "createdAt": "2026-10-01T00:00:00", "editedAt": "2026-10-01T00:00:00"}
    raw.update(over)
    return normalize_schedule(raw, now=NOW)


LINES = [
    ({"kind": "weekly", "days": [1], "times": ["16:00"]}, ["Mon *-*-* 16:00:00"]),
    ({"kind": "weekly", "days": [2, 3, 4, 5, 6, 0], "times": ["15:00"]}, ["Tue..Sun *-*-* 15:00:00"]),
    ({"kind": "weekly", "days": [6, 0, 1], "times": ["09:00"]}, ["Mon,Sat,Sun *-*-* 09:00:00"]),  # no wrap
    ({"kind": "weekly", "days": [1, 3], "times": ["08:00", "12:00"]}, ["Mon,Wed *-*-* 08,12:00:00"]),
    ({"kind": "weekly", "days": [1, 3], "times": ["08:00", "12:30"]},
     ["Mon,Wed *-*-* 08:00:00", "Mon,Wed *-*-* 12:30:00"]),                                     # comma trap
    ({"kind": "weekly", "days": list(range(7)), "times": ["07:05"]}, ["*-*-* 07:05:00"]),
    ({"kind": "daily", "times": ["15:00"]}, ["*-*-* 15:00:00"]),
    ({"kind": "daily", "times": ["15:00"], "everyDays": 2}, ["*-*-* 15:00:00"]),               # engine guard
    ({"kind": "monthly", "day": 1, "times": ["09:00"]}, ["*-*-01 09:00:00"]),
    ({"kind": "monthly", "day": "last", "times": ["18:00"]}, ["*-*~01 18:00:00"]),
    ({"kind": "hourly", "everyHours": 3, "minute": 30, "from": 9, "to": 18}, ["*-*-* 09,12,15,18:30:00"]),
    ({"kind": "hourly", "everyHours": 1, "minute": 0}, ["*-*-* *:00:00"]),
    ({"kind": "minutes", "everyMinutes": 15}, ["*-*-* *:00/15:00"]),
    ({"kind": "once", "at": "2026-11-03T14:30"}, ["2026-11-03 14:30:00"]),
    ({"kind": "cron", "expr": "0 9 1 * 1"}, ["*-*-01 09:00:00", "Mon *-*-* 09:00:00"]),          # OR -> 2 lines
    ({"kind": "cron", "expr": "*/20 8-17 * * 1-5"},
     ["Mon,Tue,Wed,Thu,Fri *-*-* 08,09,10,11,12,13,14,15,16,17:00,20,40:00"]),
    ({"kind": "cron", "expr": "30 6 * 1,7 *"}, ["*-01,07-* 06:30:00"]),
]


@pytest.mark.parametrize("rule,lines", LINES)
def test_rule_lines(rule, lines):
    assert cal.rule_lines(sched([rule])["rules"][0]) == lines


def test_owner_timer_golden():
    s = sched([{"kind": "weekly", "days": [1], "times": ["16:00"]},
               {"kind": "weekly", "days": [2, 3, 4, 5, 6, 0], "times": ["15:00"]}], catchUp=True)
    assert cal.timer_text(s) == (
        "# Written by KDE AI Chat. Do not edit: the widget rewrites this file.\n"
        "[Unit]\n"
        "Description=KDE AI Chat schedule 8c1f-news\n"
        "\n"
        "[Timer]\n"
        "OnCalendar=Mon *-*-* 16:00:00\n"
        "OnCalendar=Tue..Sun *-*-* 15:00:00\n"
        "Persistent=true\n"
        "AccuracySec=30s\n"
        "Unit=kdeaichat-run@8c1f-news.service\n"
        "\n"
        "[Install]\n"
        "WantedBy=timers.target\n")
    # Always persistent: with catch-up off the job records the missed time.
    assert "Persistent=true" in cal.timer_text(dict(s, catchUp={"enabled": False, "withinHours": 12}))


def test_service_template_golden_and_quoting():
    text = cal.service_text("/home/u/.local/share/plasma/plasmoids/org.kde.plasma.kdeaichat/contents/ui/kde_ai_helper.py",
                            "/usr/bin/python3")
    assert text == (
        "# Written by KDE AI Chat. Do not edit: the widget rewrites this file.\n"
        "[Unit]\n"
        "Description=KDE AI Chat scheduled prompt %i\n"
        "\n"
        "[Service]\n"
        "Type=oneshot\n"
        'ExecStart="/usr/bin/python3" "/home/u/.local/share/plasma/plasmoids/org.kde.plasma.kdeaichat/contents/ui/'
        'kde_ai_helper.py" run_schedule %i\n'
        "TimeoutStartSec=30min\n")
    odd = cal.service_text('/home/a b/100%/"x"/kde_ai_helper.py', "/usr/bin/python3")
    assert '"/home/a b/100%%/\\"x\\"/kde_ai_helper.py"' in odd
    with pytest.raises(ValueError):
        cal.service_text("/home/a\nExecStartPost=/bin/evil", "/usr/bin/python3")


def test_helper_path_points_at_the_installed_helper():
    assert cal.helper_path().endswith("/contents/ui/kde_ai_helper.py")


# ---- cross-check against systemd itself ----------------------------------------------

CROSS = [rule for rule, _ in LINES if rule.get("everyDays", 1) == 1] + [
    {"kind": "weekly", "days": [1, 3, 5], "times": ["08:00", "12:30", "20:15"]},
    {"kind": "monthly", "day": 31, "times": ["09:00"]},
    {"kind": "monthly", "day": 29, "times": ["23:59"]},
    {"kind": "hourly", "everyHours": 8, "minute": 5},
    {"kind": "minutes", "everyMinutes": 25},
    {"kind": "daily", "times": ["02:30"]},       # DST gap 2027-03-28 when iterated far enough
    {"kind": "cron", "expr": "15 10 13 * 5"},    # Friday OR the 13th
    {"kind": "cron", "expr": "0 12 * * sun"},
]


def systemd_next(lines, base, count):
    found = set()
    for line in lines:
        ok, elapses = cal.analyze(line, count, base)
        assert ok, line
        found.update(elapses)
    return sorted(found)[:count]


@pytest.mark.skipif(not HAS_ANALYZE, reason="systemd-analyze is not installed")
@pytest.mark.parametrize("rule", CROSS)
@pytest.mark.parametrize("base", [BASE, "2027-03-20 00:00:00"])
def test_engine_matches_systemd(berlin, rule, base):
    s = sched([rule])
    after = dt.datetime.fromisoformat(base)
    count = 12
    engine = [m.strftime("%Y-%m-%d %H:%M:%S") for m in next_occurrences(s, after, count)]
    assert engine == systemd_next(cal.schedule_lines(s), base, count)


@pytest.mark.skipif(not HAS_ANALYZE, reason="systemd-analyze is not installed")
def test_owner_schedule_matches_systemd(berlin):
    s = sched([{"kind": "weekly", "days": [1], "times": ["16:00"]},
               {"kind": "weekly", "days": [2, 3, 4, 5, 6, 0], "times": ["15:00"]}])
    engine = [m.strftime("%Y-%m-%d %H:%M:%S") for m in next_occurrences(s, NOW, 14)]
    assert engine == systemd_next(cal.schedule_lines(s), BASE, 14)


@pytest.mark.skipif(not HAS_ANALYZE, reason="systemd-analyze is not installed")
@pytest.mark.parametrize("rule,start", [
    ({"kind": "daily", "times": ["15:00"], "everyDays": 2}, "2026-10-29"),
    ({"kind": "weekly", "days": [1, 4], "times": ["09:00"], "everyWeeks": 3}, "2026-10-26"),
    ({"kind": "monthly", "day": "last", "times": ["18:00"], "everyMonths": 2}, "2026-10-01"),
])
def test_every_n_is_a_subset_of_systemd(berlin, rule, start):
    """OnCalendar fires on every candidate; the engine keeps only every N-th."""
    s = sched([rule], startDate=start)
    engine = [m.strftime("%Y-%m-%d %H:%M:%S") for m in next_occurrences(s, NOW, 6)]
    wakes = systemd_next(cal.schedule_lines(s), BASE, 60)
    assert set(engine) <= set(wakes)
    assert len(engine) == 6 and engine[-1] < wakes[-1]
    skipped = [w for w in wakes if engine[0] <= w <= engine[-1] and w not in engine]
    assert skipped, "the guard must filter some wake-ups"


@pytest.mark.skipif(not HAS_ANALYZE, reason="systemd-analyze is not installed")
def test_check_lines_rejects_never_and_garbage(berlin):
    assert cal.check_lines(["Mon *-*-* 16:00:00"]) == []
    assert "never" in cal.check_lines(["2020-01-01 10:00:00"])[0]
    assert "cannot read" in cal.check_lines(["*-02-30 nonsense"])[0]
    assert "never" in cal.check_lines(["*-02-30 10:00:00"])[0]


def test_check_lines_without_systemd_analyze(monkeypatch):
    monkeypatch.setenv("KDEAICHAT_SYSTEMD_ANALYZE", "/nonexistent/systemd-analyze")
    assert cal.check_lines(["whatever"]) == []
