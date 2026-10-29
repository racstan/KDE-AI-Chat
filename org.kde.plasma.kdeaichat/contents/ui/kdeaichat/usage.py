"""The spending log: what each finished reply cost, as its provider reported it, and the budget alerts.

chat/SpendingLog.qml sends one ``usage_add`` for each reply that reported its token counts (direct, OpenCode
and Pi mode). Each reply is one line of ``<data>/kdeaichat/usage/<YYYY-MM>.jsonl``; the folder is 0700 and the
files 0600 (kdeaichat/common.py):

  {"at": ms since the epoch, "provider": id, "model": id, "mode": "direct" | "opencode" | "pi",
   "input": n, "output": n, "cacheRead": n, "cost": dollars or null}

``input`` includes ``cacheRead`` (the part of the prompt the provider served from its cache). ``cost`` is the
provider's own figure in dollars, or null when it gave none; a reported 0 is a known cost. Nothing else is
written: no chat text, no titles, no chat ids. Fields the caller adds are dropped.

  usage_add     {entry, budgets, alertPercent}  -> {"type": "usage_added", "alerts": [...]}
  usage_month   {month: "YYYY-MM"}              -> {"type": "usage_month", "month", "providers", "models", "days", "skipped"}
  usage_months  {}                              -> {"type": "usage_months", "months": [...]}, newest first

Totals are {count, input, output, cacheRead, cost (known costs only), costCount}. Lines that do not parse
(or are not valid entries) are skipped and counted in "skipped".

Budget alerts: ``budgets`` maps a provider id to its monthly limit in dollars. When a reply's known cost takes
that provider's month total across ``alertPercent`` percent or across 100 percent of its limit, one alert is
returned. Each provider, month and level alerts once: the levels already shown are kept in
``alerts-<YYYY-MM>.json`` beside the log. Nothing here blocks a reply.

``KDEAICHAT_USAGE_DIR`` replaces the folder (tests, dev runs).
"""
import fcntl
import json
import math
import os
import re
import time
from contextlib import contextmanager
from typing import Any, Dict, Iterator, List, Optional, Tuple

from kdeaichat import chats
from kdeaichat.common import atomic_write_json, ensure_private_dir

MODES = ("direct", "opencode", "pi")
MAX_NUMBER = 1e12
MAX_LINE = 65536
EPS = 1e-9
MONTH_RE = re.compile(r"(\d{4})-(0[1-9]|1[0-2])")
FILE_RE = re.compile(r"(\d{4}-(?:0[1-9]|1[0-2]))\.jsonl")


def usage_dir() -> str:
    return os.environ.get("KDEAICHAT_USAGE_DIR") or os.path.join(chats.data_root(), "usage")


def month_of(at_ms: float) -> str:
    return time.strftime("%Y-%m", time.localtime(at_ms / 1000.0))


def day_of(at_ms: float) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(at_ms / 1000.0))


def _text(value: Any, name: str, limit: int, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise ValueError("%s must be text" % name)
    if not value.strip() and not allow_empty:
        raise ValueError("%s is required" % name)
    if len(value) > limit or any(ord(ch) < 32 for ch in value):
        raise ValueError("%s is not valid" % name)
    return value


def _count(value: Any, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError("%s must be a number" % name)
    if value < 0 or value > MAX_NUMBER:
        raise ValueError("%s is out of range" % name)
    return int(round(value))


def _money(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError("cost must be a number or null")
    if value < 0 or value > MAX_NUMBER:
        raise ValueError("cost is out of range")
    return float(value)


def clean_entry(raw: Any, now_ms: Optional[float] = None) -> Dict[str, Any]:
    """The entry as it is written (or read back): only the known fields, each checked. ValueError otherwise.

    ``now_ms`` is used for ``at`` when the entry has none (writing); reading back requires it."""
    if not isinstance(raw, dict):
        raise ValueError("the entry must be an object")
    at = raw.get("at")
    if at is None and now_ms is not None:
        at = now_ms
    if isinstance(at, bool) or not isinstance(at, (int, float)) or not math.isfinite(at) or at <= 0:
        raise ValueError("at must be a time in milliseconds")
    mode = raw.get("mode")
    if mode not in MODES:
        raise ValueError("mode must be direct, opencode or pi")
    return {
        "at": int(at),
        "provider": _text(raw.get("provider"), "provider", 128),
        "model": _text(raw.get("model") or "", "model", 512, allow_empty=True),
        "mode": mode,
        "input": _count(raw.get("input"), "input"),
        "output": _count(raw.get("output"), "output"),
        "cacheRead": _count(raw.get("cacheRead") or 0, "cacheRead"),
        "cost": _money(raw.get("cost")),
    }


def thresholds(alert_percent: Any) -> List[int]:
    """The levels that raise an alert: alert_percent when it is 1 to 99, and 100."""
    try:
        percent = int(alert_percent)
    except (TypeError, ValueError):
        percent = 80
    return sorted({percent, 100}) if 1 <= percent < 100 else [100]


def budget_for(budgets: Any, provider: str) -> Optional[float]:
    value = budgets.get(provider) if isinstance(budgets, dict) else None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        return None
    if value <= 0 or value > MAX_NUMBER:
        return None
    return float(value)


@contextmanager
def _locked_month(path: str, write: bool) -> Iterator[Optional[int]]:
    """The month file's descriptor, locked for the whole block (exclusive to write, shared to read).

    Reading a month without a file yields None. A symlink is refused (O_NOFOLLOW)."""
    if write:
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    else:
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        except FileNotFoundError:
            yield None
            return
    try:
        if write:
            os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
        yield fd
    finally:
        os.close(fd)  # closing the descriptor also drops the lock


def _read_all(fd: int) -> bytes:
    os.lseek(fd, 0, os.SEEK_SET)
    chunks = []
    while True:
        chunk = os.read(fd, 1 << 16)
        if not chunk:
            break
        chunks.append(chunk)
    return b"".join(chunks)


def _write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        view = view[os.write(fd, view):]


def _parse(data: bytes) -> Tuple[List[Dict[str, Any]], int]:
    rows: List[Dict[str, Any]] = []
    skipped = 0
    for line in data.split(b"\n"):
        if not line.strip():
            continue
        if len(line) > MAX_LINE:
            skipped += 1
            continue
        try:
            rows.append(clean_entry(json.loads(line.decode("utf-8"))))
        except ValueError:  # bad JSON, bad UTF-8 and invalid entries alike
            skipped += 1
    return rows, skipped


def _empty_totals() -> Dict[str, Any]:
    return {"count": 0, "input": 0, "output": 0, "cacheRead": 0, "cost": 0.0, "costCount": 0}


def _add(totals: Dict[str, Any], row: Dict[str, Any]) -> None:
    totals["count"] += 1
    totals["input"] += row["input"]
    totals["output"] += row["output"]
    totals["cacheRead"] += row["cacheRead"]
    if row["cost"] is not None:
        totals["cost"] += row["cost"]
        totals["costCount"] += 1


def _finish(totals: Dict[str, Any]) -> Dict[str, Any]:
    totals["cost"] = round(totals["cost"], 10)
    return totals


def summarize(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Totals per provider, per model (provider and model) and per local day."""
    providers: Dict[str, Dict[str, Any]] = {}
    models: Dict[Tuple[str, str], Dict[str, Any]] = {}
    days: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        _add(providers.setdefault(row["provider"], _empty_totals()), row)
        _add(models.setdefault((row["provider"], row["model"]), _empty_totals()), row)
        _add(days.setdefault(day_of(row["at"]), _empty_totals()), row)
    return {
        "providers": {name: _finish(t) for name, t in sorted(providers.items())},
        "models": [dict(provider=p, model=m, **_finish(t)) for (p, m), t in sorted(models.items())],
        "days": {name: _finish(t) for name, t in sorted(days.items())},
    }


def _known_cost(rows: List[Dict[str, Any]], provider: str) -> float:
    return sum(row["cost"] for row in rows if row["provider"] == provider and row["cost"] is not None)


def _alerts_path(folder: str, month: str) -> str:
    return os.path.join(folder, "alerts-%s.json" % month)


def _read_shown(path: str) -> Dict[str, List[int]]:
    """provider -> the levels already alerted this month. A missing or broken file counts as none shown."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    shown: Dict[str, List[int]] = {}
    if isinstance(data, dict):
        for provider, levels in data.items():
            if isinstance(provider, str) and isinstance(levels, list):
                shown[provider] = [v for v in levels if isinstance(v, int) and not isinstance(v, bool)]
    return shown


def _raise_alerts(folder: str, month: str, provider: str, limit: Optional[float], before: float, after: float,
                  levels: List[int]) -> List[Dict[str, Any]]:
    """The alert for the levels this reply crossed that were not shown yet (at most one: the highest)."""
    if limit is None:
        return []
    crossed = [level for level in levels if before + EPS < limit * level / 100.0 <= after + EPS]
    if not crossed:
        return []
    path = _alerts_path(folder, month)
    shown = _read_shown(path)
    old = shown.get(provider, [])
    new = [level for level in crossed if level not in old]
    if not new:
        return []
    shown[provider] = sorted(set(old) | set(new))
    atomic_write_json(path, shown)
    return [{"provider": provider, "percent": max(new), "spent": round(after, 10), "budget": limit}]


def add_entry(raw: Any, budgets: Any = None, alert_percent: Any = 80, directory: Optional[str] = None,
              now_ms: Optional[float] = None) -> List[Dict[str, Any]]:
    """Appends one reply to its month's log and returns the budget alerts it raised (none or one)."""
    now = now_ms if now_ms is not None else time.time() * 1000.0
    entry = clean_entry(raw, now)
    folder = ensure_private_dir(directory or usage_dir())
    month = month_of(entry["at"])
    line = (json.dumps(entry, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")
    with _locked_month(os.path.join(folder, month + ".jsonl"), write=True) as fd:
        assert fd is not None
        rows, _skipped = _parse(_read_all(fd))
        before = _known_cost(rows, entry["provider"])
        _write_all(fd, line)
        after = before + (entry["cost"] or 0.0)
        if entry["cost"] is None:
            return []
        return _raise_alerts(folder, month, entry["provider"], budget_for(budgets, entry["provider"]),
                             before, after, thresholds(alert_percent))


def month_totals(month: str, directory: Optional[str] = None) -> Dict[str, Any]:
    if not MONTH_RE.fullmatch(str(month or "")):
        raise ValueError("month must look like 2026-10")
    folder = directory or usage_dir()
    with _locked_month(os.path.join(folder, month + ".jsonl"), write=False) as fd:
        data = b"" if fd is None else _read_all(fd)
    rows, skipped = _parse(data)
    out: Dict[str, Any] = {"type": "usage_month", "month": month, "skipped": skipped}
    out.update(summarize(rows))
    return out


def months(directory: Optional[str] = None) -> List[str]:
    """The months that have a log, newest first."""
    try:
        names = os.listdir(directory or usage_dir())
    except OSError:
        return []
    found = set()
    for name in names:
        match = FILE_RE.fullmatch(name)
        if match:
            found.add(match.group(1))
    return sorted(found, reverse=True)


def cmd_usage_add(payload: Dict[str, Any]) -> None:
    alerts = add_entry(payload.get("entry"), payload.get("budgets"), payload.get("alertPercent", 80))
    print(json.dumps({"type": "usage_added", "alerts": alerts}), flush=True)


def cmd_usage_month(payload: Dict[str, Any]) -> None:
    month = payload.get("month") or month_of(time.time() * 1000.0)
    print(json.dumps(month_totals(str(month))), flush=True)


def cmd_usage_months(payload: Dict[str, Any]) -> None:
    print(json.dumps({"type": "usage_months", "months": months()}), flush=True)


COMMANDS = {"usage_add": cmd_usage_add, "usage_month": cmd_usage_month, "usage_months": cmd_usage_months}
