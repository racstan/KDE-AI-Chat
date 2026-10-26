"""Shared fixtures. ``sched_env`` isolates the schedule code from the real system."""
import os
import sys
import time

import pytest

UI_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
if UI_DIR not in sys.path:
    sys.path.insert(0, UI_DIR)

FAKE_SYSTEMCTL = """#!/usr/bin/env python3
import os, sys
with open(os.environ["FAKE_SYSTEMCTL_LOG"], "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\\n")
sys.exit(int(os.environ.get("FAKE_SYSTEMCTL_EXIT", "0")))
"""


class SchedEnv:
    def __init__(self, root):
        self.root = str(root)
        self.data = os.path.join(self.root, "data", "kdeaichat")
        self.units = os.path.join(self.root, "units")
        self.log = os.path.join(self.root, "systemctl.log")

    def calls(self):
        try:
            with open(self.log) as f:
                return [line.rstrip("\n") for line in f]
        except FileNotFoundError:
            return []


@pytest.fixture
def berlin():
    """Run in Europe/Berlin local time (DST changes on known dates)."""
    old = os.environ.get("TZ")
    os.environ["TZ"] = "Europe/Berlin"
    time.tzset()
    yield
    if old is None:
        os.environ.pop("TZ", None)
    else:
        os.environ["TZ"] = old
    time.tzset()


@pytest.fixture
def sched_env(tmp_path, monkeypatch, berlin):
    """Temp data folder, temp unit folder and a recording fake ``systemctl``.

    The real ``systemctl --user`` and ~/.config/systemd/user are never touched.
    """
    env = SchedEnv(tmp_path)
    fake = tmp_path / "fake-systemctl"
    fake.write_text(FAKE_SYSTEMCTL)
    fake.chmod(0o755)
    monkeypatch.setenv("XDG_DATA_HOME", os.path.join(env.root, "data"))
    monkeypatch.setenv("XDG_CONFIG_HOME", os.path.join(env.root, "config"))
    monkeypatch.setenv("KDEAICHAT_UNIT_DIR", env.units)
    monkeypatch.setenv("KDEAICHAT_SYSTEMCTL", str(fake))
    monkeypatch.setenv("FAKE_SYSTEMCTL_LOG", env.log)
    return env
