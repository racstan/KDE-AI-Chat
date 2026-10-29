"""The spending log (kdeaichat/usage.py) and its helper commands: appends, totals, months, budget alerts."""
import base64
import json
import math
import os
import stat
import subprocess
import sys
import time

import pytest

from kdeaichat import usage

UI = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui")
HELPER = os.path.join(UI, "kde_ai_helper.py")
KEYS = {"at", "provider", "model", "mode", "input", "output", "cacheRead", "cost"}


@pytest.fixture
def folder(tmp_path, monkeypatch):
    path = tmp_path / "usage"
    monkeypatch.setenv("KDEAICHAT_USAGE_DIR", str(path))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    return path


def local_ms(year, month, day, hour=12, minute=0):
    """A local time as milliseconds since the epoch (the widget's Date.now() unit)."""
    return time.mktime((year, month, day, hour, minute, 0, 0, 0, -1)) * 1000


def reply(at=None, provider="openrouter", model="openai/gpt-4o", mode="direct", input=100, output=20,
          cache=0, cost=None):
    entry = {"provider": provider, "model": model, "mode": mode, "input": input, "output": output,
             "cacheRead": cache, "cost": cost}
    if at is not None:
        entry["at"] = at
    return entry


def lines(folder_path, month):
    with open(folder_path / (month + ".jsonl"), encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def test_append_writes_one_private_line_with_only_the_known_fields(folder):
    usage.add_entry(dict(reply(at=local_ms(2026, 10, 3), cost=0.25), title="A secret title", chatId="s-1",
                         text="hello there"), now_ms=0)
    month = usage.month_of(local_ms(2026, 10, 3))
    rows = lines(folder, month)
    assert len(rows) == 1
    assert set(rows[0]) == KEYS
    assert rows[0]["cost"] == 0.25 and rows[0]["mode"] == "direct"
    assert stat.S_IMODE(os.stat(folder).st_mode) == 0o700
    assert stat.S_IMODE(os.stat(folder / (month + ".jsonl")).st_mode) == 0o600


def test_existing_folder_and_file_are_tightened(tmp_path, monkeypatch):
    path = tmp_path / "usage"
    path.mkdir(mode=0o755)
    os.chmod(path, 0o755)
    monkeypatch.setenv("KDEAICHAT_USAGE_DIR", str(path))
    month = usage.month_of(local_ms(2026, 10, 3))
    file = path / (month + ".jsonl")
    file.write_text("")
    os.chmod(file, 0o644)
    usage.add_entry(reply(at=local_ms(2026, 10, 3), cost=1.0))
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o700
    assert stat.S_IMODE(os.stat(file).st_mode) == 0o600
    assert len(lines(path, month)) == 1


def test_a_missing_time_means_now(folder):
    usage.add_entry(reply(cost=0.5), now_ms=local_ms(2026, 10, 3))
    assert lines(folder, "2026-10")[0]["at"] == int(local_ms(2026, 10, 3))


@pytest.mark.parametrize("bad", [
    {"mode": "chat"},
    {"input": -1},
    {"input": float("nan")},
    {"output": True},
    {"cacheRead": "many"},
    {"cost": True},
    {"cost": -0.1},
    {"cost": float("inf")},
    {"provider": ""},
    {"provider": "x" * 129},
    {"model": "line\nbreak"},
    {"at": 0},
    {"at": "yesterday"},
])
def test_bad_entries_are_refused_and_nothing_is_written(folder, bad):
    entry = reply(at=local_ms(2026, 10, 3), cost=0.1)
    entry.update(bad)
    with pytest.raises(ValueError):
        usage.add_entry(entry)
    assert not folder.exists() or not os.listdir(folder)


def test_null_cost_and_zero_cost_are_kept_apart(folder):
    usage.add_entry(reply(at=local_ms(2026, 10, 3), cost=None))
    usage.add_entry(reply(at=local_ms(2026, 10, 3), cost=0))
    usage.add_entry(reply(at=local_ms(2026, 10, 3), cost=0.5))
    totals = usage.month_totals("2026-10")["providers"]["openrouter"]
    assert totals["count"] == 3
    assert totals["costCount"] == 2
    assert totals["cost"] == 0.5


def test_totals_per_provider_model_and_day(folder):
    day1, day2 = local_ms(2026, 10, 1), local_ms(2026, 10, 2)
    usage.add_entry(reply(at=day1, provider="openrouter", model="a", input=100, output=10, cache=40, cost=0.1))
    usage.add_entry(reply(at=day1, provider="openrouter", model="b", input=200, output=20, cost=0.2))
    usage.add_entry(reply(at=day2, provider="ollama", model="llama", mode="opencode", input=5, output=1, cost=None))
    usage.add_entry(reply(at=day2, provider="openrouter", model="a", mode="pi", input=50, output=5, cache=10, cost=0.3))
    out = usage.month_totals("2026-10")
    assert out["type"] == "usage_month" and out["month"] == "2026-10" and out["skipped"] == 0
    openrouter = out["providers"]["openrouter"]
    assert openrouter == {"count": 3, "input": 350, "output": 35, "cacheRead": 50, "cost": 0.6, "costCount": 3}
    ollama = out["providers"]["ollama"]
    assert ollama == {"count": 1, "input": 5, "output": 1, "cacheRead": 0, "cost": 0.0, "costCount": 0}
    by_model = {(m["provider"], m["model"]): m for m in out["models"]}
    assert by_model[("openrouter", "a")]["count"] == 2
    assert by_model[("openrouter", "a")]["cost"] == pytest.approx(0.4)
    assert by_model[("openrouter", "b")]["input"] == 200
    assert [(m["provider"], m["model"]) for m in out["models"]] == sorted(by_model)
    assert set(out["days"]) == {"2026-10-01", "2026-10-02"}
    assert out["days"]["2026-10-01"]["count"] == 2
    assert out["days"]["2026-10-02"]["costCount"] == 1


def test_days_and_months_use_local_time(folder, berlin):
    usage.add_entry(reply(at=local_ms(2026, 10, 31, 23, 30), cost=0.1))
    usage.add_entry(reply(at=local_ms(2026, 11, 1, 0, 30), cost=0.2))
    assert usage.months() == ["2026-11", "2026-10"]
    assert list(usage.month_totals("2026-10")["days"]) == ["2026-10-31"]
    assert list(usage.month_totals("2026-11")["days"]) == ["2026-11-01"]


def test_months_lists_logs_newest_first_and_ignores_other_files(folder):
    folder.mkdir(mode=0o700)
    for name in ("2026-08.jsonl", "2026-10.jsonl", "2026-13.jsonl", "alerts-2026-10.json", "notes.txt",
                 "2026-09.jsonl.bak"):
        (folder / name).write_text("")
    assert usage.months() == ["2026-10", "2026-08"]
    assert usage.months(str(folder / "missing")) == []


def test_bad_lines_are_skipped_and_counted(folder):
    folder.mkdir(mode=0o700)
    good = {"at": int(local_ms(2026, 10, 3)), "provider": "p", "model": "m", "mode": "direct",
            "input": 1, "output": 1, "cacheRead": 0, "cost": 0.5}
    bad = [
        "not json",
        "[1, 2]",
        '{"provider": "x"}',
        '{"at": 1, "provider": "p", "mode": "direct", "input": -1, "output": 0, "cost": null}',
        '{"at": 1, "provider": "p", "mode": "direct", "input": 1, "output": 1, "cost": "abc"}',
        '{"at": 1, "provider": "p", "mode": "direct", "input": 1, "output": 1, "cost": null}\xff',
        "x" * (usage.MAX_LINE + 1),
    ]
    text = "\n".join([json.dumps(good)] + bad) + "\n\n"
    (folder / "2026-10.jsonl").write_bytes(text.encode("utf-8", errors="surrogateescape"))
    out = usage.month_totals("2026-10")
    assert out["providers"]["p"]["count"] == 1
    assert out["skipped"] == len(bad)


def test_bad_month_names_are_refused(folder):
    for month in ("2026-1", "2026-13", "../2026-10", "2026-10\n", "", None):
        with pytest.raises(ValueError):
            usage.month_totals(month)


def test_a_symlinked_log_is_refused(folder, tmp_path):
    folder.mkdir(mode=0o700)
    target = tmp_path / "elsewhere.jsonl"
    target.write_text("")
    os.symlink(target, folder / "2026-10.jsonl")
    with pytest.raises(OSError):
        usage.add_entry(reply(at=local_ms(2026, 10, 3), cost=0.1))
    assert target.read_text() == ""


def test_budget_alerts_at_80_and_100_percent_are_shown_once(folder):
    budgets = {"openrouter": 10}
    at = local_ms(2026, 10, 3)
    alerts = []
    for cost in (7.0, 1.5, 0.5, 1.0, 1.0):
        alerts.append(usage.add_entry(reply(at=at, cost=cost), budgets, 80))
    assert alerts == [[], [{"provider": "openrouter", "percent": 80, "spent": 8.5, "budget": 10.0}], [],
                      [{"provider": "openrouter", "percent": 100, "spent": 10.0, "budget": 10.0}], []]
    assert json.loads((folder / "alerts-2026-10.json").read_text()) == {"openrouter": [80, 100]}
    assert stat.S_IMODE(os.stat(folder / "alerts-2026-10.json").st_mode) == 0o600


def test_one_reply_crossing_both_levels_alerts_once_at_100(folder):
    at = local_ms(2026, 10, 3)
    alerts = usage.add_entry(reply(at=at, cost=12.0), {"openrouter": 10}, 80)
    assert alerts == [{"provider": "openrouter", "percent": 100, "spent": 12.0, "budget": 10.0}]
    assert usage.add_entry(reply(at=at, cost=1.0), {"openrouter": 10}, 80) == []
    assert json.loads((folder / "alerts-2026-10.json").read_text()) == {"openrouter": [80, 100]}


def test_no_alert_without_a_budget_or_a_known_cost(folder):
    at = local_ms(2026, 10, 3)
    assert usage.add_entry(reply(at=at, cost=50.0), {}, 80) == []
    assert usage.add_entry(reply(at=at, cost=None), {"openrouter": 1}, 80) == []
    for budget in (0, -5, "10", None, True, float("nan")):
        assert usage.add_entry(reply(at=at, cost=50.0), {"openrouter": budget}, 80) == []
    assert not (folder / "alerts-2026-10.json").exists()


def test_alert_percent_outside_1_to_99_leaves_only_the_full_budget_level(folder):
    at = local_ms(2026, 10, 3)
    assert usage.add_entry(reply(at=at, cost=9.0), {"openrouter": 10}, 100) == []
    alerts = usage.add_entry(reply(at=at, cost=1.0), {"openrouter": 10}, 100)
    assert alerts[0]["percent"] == 100
    assert usage.thresholds(0) == [100] and usage.thresholds(None) == [80, 100]
    assert usage.thresholds(95) == [95, 100] and usage.thresholds(150) == [100]


def test_alerts_are_per_provider_and_per_month(folder):
    budgets = {"openrouter": 10, "anthropic": 10}
    oct_at = local_ms(2026, 10, 3)
    nov_at = local_ms(2026, 11, 3)
    assert usage.add_entry(reply(at=oct_at, provider="openrouter", cost=9.0), budgets, 80)[0]["provider"] == "openrouter"
    assert usage.add_entry(reply(at=oct_at, provider="anthropic", cost=9.0), budgets, 80)[0]["provider"] == "anthropic"
    assert usage.add_entry(reply(at=oct_at, provider="openrouter", cost=0.1), budgets, 80) == []
    assert usage.add_entry(reply(at=nov_at, provider="openrouter", cost=9.0), budgets, 80)[0]["provider"] == "openrouter"


def test_a_broken_alerts_file_counts_as_nothing_shown(folder):
    folder.mkdir(mode=0o700)
    (folder / "alerts-2026-10.json").write_text("{not json")
    alerts = usage.add_entry(reply(at=local_ms(2026, 10, 3), cost=9.0), {"openrouter": 10}, 80)
    assert alerts[0]["percent"] == 80


def test_concurrent_appends_never_interleave(folder):
    code = (
        "import sys; sys.path.insert(0, %r)\n"
        "from kdeaichat import usage\n"
        "tag = sys.argv[1]\n"
        "for i in range(40):\n"
        "    usage.add_entry({'at': 1790000000000 + i, 'provider': 'p' + tag, 'model': 'm', 'mode': 'direct',\n"
        "                     'input': i, 'output': 1, 'cacheRead': 0, 'cost': 0.01})\n"
    ) % os.path.abspath(UI)
    env = dict(os.environ, KDEAICHAT_USAGE_DIR=str(folder))
    procs = [subprocess.Popen([sys.executable, "-I", "-c", code, str(n)], env=env) for n in range(4)]
    assert all(p.wait(timeout=120) == 0 for p in procs)
    month = usage.month_of(1790000000000)
    rows = lines(folder, month)
    assert len(rows) == 160
    per_provider = {}
    for row in rows:
        per_provider[row["provider"]] = per_provider.get(row["provider"], 0) + 1
    assert per_provider == {"p0": 40, "p1": 40, "p2": 40, "p3": 40}
    assert math.isclose(usage.month_totals(month)["providers"]["p0"]["cost"], 0.4)


def run_helper(command, payload=None, env=None):
    arg = base64.b64encode(json.dumps(payload or {}).encode()).decode()
    args = [sys.executable, HELPER, command] + ([arg] if payload is not None else [])
    return subprocess.run(args, capture_output=True, text=True, timeout=60, env=env)


def test_helper_commands_round_trip(folder):
    env = dict(os.environ, KDEAICHAT_USAGE_DIR=str(folder))
    at = int(local_ms(2026, 10, 3))
    entry = {"at": at, "provider": "openrouter", "model": "openai/gpt-4o", "mode": "direct",
             "input": 120, "output": 30, "cacheRead": 0, "cost": 9.0}
    added = run_helper("usage_add", {"entry": entry, "budgets": {"openrouter": 10}, "alertPercent": 80}, env)
    assert added.returncode == 0, added.stdout + added.stderr
    result = json.loads(added.stdout)
    assert result["type"] == "usage_added"
    assert result["alerts"][0]["percent"] == 80
    # 9 + 9 is past the full budget of 10 (80% was already shown): the 100% alert, once.
    again = json.loads(run_helper("usage_add", {"entry": entry, "budgets": {"openrouter": 10}}, env).stdout)
    assert again["alerts"][0]["percent"] == 100
    third = json.loads(run_helper("usage_add", {"entry": entry, "budgets": {"openrouter": 10}}, env).stdout)
    assert third["alerts"] == []
    month = json.loads(run_helper("usage_month", {"month": "2026-10"}, env).stdout)
    assert month["providers"]["openrouter"]["count"] == 3
    months = json.loads(run_helper("usage_months", {}, env).stdout)
    assert months == {"type": "usage_months", "months": ["2026-10"]}


def test_helper_refuses_a_bad_entry_with_an_error_exit(folder):
    env = dict(os.environ, KDEAICHAT_USAGE_DIR=str(folder))
    bad = run_helper("usage_add", {"entry": {"provider": "p", "mode": "web", "input": 1, "output": 1}}, env)
    assert bad.returncode == 1
    assert "Error executing usage_add" in bad.stdout
    assert not folder.exists() or not os.listdir(folder)


def test_usage_commands_are_registered_in_the_helper():
    assert set(usage.COMMANDS) == {"usage_add", "usage_month", "usage_months"}
    out = subprocess.run([sys.executable, HELPER, "not_a_command"], capture_output=True, text=True, timeout=60)
    assert out.returncode == 1 and "Unknown command" in out.stdout
