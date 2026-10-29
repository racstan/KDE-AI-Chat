"""1.5 local hardening: one Pi bridge at a time (C4), private files and folders the helper creates (S10).

The OpenCode password (S4) is tested in test_opencode_server.py, the ask inbox into agent chats (S5) in
tests/qml/tst_ask_inbox.qml. Everything runs in temp dirs with the Pi mock; no real OpenCode or Pi starts.
"""
import contextlib
import io
import json
import os
import stat
import sys
import tempfile
import threading

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui"))
from kdeaichat import common, pi_bridge, schedule_migrate, schedule_runs  # noqa: E402

FIXTURES = os.path.join(ROOT, "tests", "fixtures")


def mode(path):
    return stat.S_IMODE(os.stat(path).st_mode)


@pytest.fixture
def pi_env(monkeypatch):
    with tempfile.TemporaryDirectory() as tmp:
        bindir = os.path.join(tmp, "bin")
        os.makedirs(bindir)
        os.symlink(os.path.join(ROOT, "scripts", "dev-pi-mock.py"), os.path.join(bindir, "pi"))
        monkeypatch.setenv("PATH", bindir + os.pathsep + os.environ["PATH"])
        monkeypatch.setenv("XDG_DATA_HOME", os.path.join(tmp, "data"))
        monkeypatch.setenv("PI_CODING_AGENT_DIR", os.path.join(tmp, "pi-agent"))
        monkeypatch.setenv("KDEAICHAT_PI_MOCK_LOG", os.path.join(tmp, "pi.log"))
        monkeypatch.setenv("KDEAICHAT_PI_MOCK_FIXTURE", os.path.join(FIXTURES, "pi-0.84-ollama-write.jsonl"))
        yield tmp
        with contextlib.redirect_stdout(io.StringIO()):
            pi_bridge.cmd_pi_bridge_stop({})


def test_two_starts_at_once_give_one_bridge(pi_env):
    results = []

    def start():
        results.append(pi_bridge.ensure_bridge())

    threads = [threading.Thread(target=start) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(30)
    assert len(results) == 4 and all(r["status"] in ("started", "running") for r in results), results
    assert sum(1 for r in results if r["status"] == "started") == 1, results
    assert len({(r["port"], r["token"]) for r in results}) == 1, "every caller got the same bridge"


def test_the_bridge_log_is_private_and_rotates(pi_env):
    root = os.path.join(pi_env, "data", "kdeaichat")
    os.makedirs(root, mode=0o755)
    os.chmod(root, 0o755)
    log = os.path.join(root, "pi-bridge.log")
    with open(log, "wb") as f:
        f.write(b"x" * (pi_bridge.LOG_MAX_BYTES + 10))
    os.chmod(log, 0o644)
    old = os.umask(0)
    try:
        assert pi_bridge.ensure_bridge()["status"] == "started"
    finally:
        os.umask(old)
    assert os.path.getsize(log + ".1") > pi_bridge.LOG_MAX_BYTES, "the big log was kept as the previous file"
    assert os.path.getsize(log) < 10000
    assert mode(log) == 0o600 and mode(log + ".1") == 0o600
    assert mode(root) == 0o700
    assert mode(os.path.join(root, "pi-bridge.lock")) == 0o600
    assert mode(os.path.join(root, "pi-bridge.json")) == 0o600


def test_private_log_and_folder_helpers(tmp_path):
    old = os.umask(0)
    try:
        folder = tmp_path / "a" / "b"
        os.makedirs(folder, mode=0o755)
        os.chmod(folder, 0o755)
        common.ensure_private_dir(str(folder))
        assert mode(folder) == 0o700
        log = str(folder / "x.log")
        with open(log, "wb") as f:
            f.write(b"old")
        os.chmod(log, 0o666)
        with common.private_log(log) as f:
            f.write(b"new")
        assert mode(log) == 0o600
        with open(log, "rb") as f:
            assert f.read() == b"oldnew"
    finally:
        os.umask(old)


def test_schedule_state_and_backup_are_private(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    os.makedirs(tmp_path / "data" / "kdeaichat" / "schedule-runs", mode=0o755)
    os.chmod(tmp_path / "data" / "kdeaichat" / "schedule-runs", 0o755)
    old = os.umask(0)
    try:
        schedule_runs.save_run_state("abc", schedule_runs.empty_state())
        source = tmp_path / "schedules.json"
        source.write_text("{}")
        os.chmod(source, 0o644)
        backup = tmp_path / "schedules.json.bak"
        schedule_migrate.backup_v1(str(source), str(backup))
    finally:
        os.umask(old)
    assert mode(schedule_runs.runs_dir()) == 0o700
    assert mode(schedule_runs.run_state_path("abc")) == 0o600
    assert mode(backup) == 0o600
    assert json.loads(backup.read_text()) == {}
