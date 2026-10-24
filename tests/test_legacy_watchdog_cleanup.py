"""The removed plasmashell watchdog must be stopped on upgrade.

A monitor started by an older version keeps running after the widget is
upgraded and restarts plasmashell once its heartbeat goes stale, so
stop_legacy_watchdog has to find it, stop it, and leave other processes
alone.
"""
import contextlib
import io
import os
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

import kde_ai_helper  # noqa: E402

SLEEPER = "import time\ntime.sleep(60)\n"


def _spawn(script_dir, script_name, *args):
    path = os.path.join(script_dir, script_name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(SLEEPER)
    return subprocess.Popen([sys.executable, path, *args])


def _wait_exit(proc, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return True
        time.sleep(0.05)
    return False


def test_stops_only_the_legacy_monitor_and_removes_its_files():
    with tempfile.TemporaryDirectory() as home, tempfile.TemporaryDirectory() as scripts:
        monitor = _spawn(scripts, "kde_ai_helper.py", "plasmashell_watchdog", "e30=")
        # Same helper, different command: must survive.
        other_helper = subprocess.Popen(
            [sys.executable, os.path.join(scripts, "kde_ai_helper.py"), "poll_pending_triggers"])
        # Unrelated process mentioning the word: must survive.
        unrelated = _spawn(scripts, "unrelated.py", "plasmashell_watchdog")

        data = os.path.join(home, ".local", "share", "kdeaichat")
        os.makedirs(data)
        names = ("plasmashell-heartbeat", "plasmashell-watchdog.pid", "plasmashell-watchdog.last-restart")
        for name in names:
            with open(os.path.join(data, name), "w", encoding="utf-8") as f:
                f.write(str(monitor.pid))
        try:
            time.sleep(0.2)
            out = io.StringIO()
            with patch.dict(os.environ, {"HOME": home}), contextlib.redirect_stdout(out):
                kde_ai_helper.cmd_stop_legacy_watchdog({})

            assert _wait_exit(monitor), "legacy monitor was not stopped"
            assert other_helper.poll() is None, "another helper command was stopped"
            assert unrelated.poll() is None, "an unrelated process was stopped"
            assert str(monitor.pid) in out.getvalue()
            for name in names:
                assert not os.path.exists(os.path.join(data, name)), name
        finally:
            for proc in (monitor, other_helper, unrelated):
                if proc.poll() is None:
                    proc.kill()
                proc.wait()


def test_no_monitor_and_no_files_is_fine():
    with tempfile.TemporaryDirectory() as home:
        out = io.StringIO()
        with patch.dict(os.environ, {"HOME": home}), contextlib.redirect_stdout(out):
            kde_ai_helper.cmd_stop_legacy_watchdog({})
        assert '"status": "ok"' in out.getvalue()


def test_helper_no_longer_offers_the_watchdog():
    with open(kde_ai_helper.__file__, encoding="utf-8") as f:
        source = f.read()
    assert '"plasmashell_watchdog": cmd_' not in source
    assert "plasma-plasmashell.service" not in source
