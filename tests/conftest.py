"""Shared fixtures. ``sched_env`` isolates the schedule code from the real system."""
import json
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


FAKE_RECORDER = """#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_RECORDER_LOG"], "a") as f:
    f.write(json.dumps([os.path.basename(sys.argv[0])] + sys.argv[1:]) + "\\n")
"""


class SchedEnv:
    def __init__(self, root):
        self.root = str(root)
        self.data = os.path.join(self.root, "data", "kdeaichat")
        self.units = os.path.join(self.root, "units")
        self.log = os.path.join(self.root, "systemctl.log")

    def recorded(self, program=None):
        """Calls of the fake notify-send / busctl: [[program, arg, ...], ...]."""
        try:
            with open(os.path.join(self.root, "recorder.log")) as f:
                rows = [json.loads(line) for line in f]
        except FileNotFoundError:
            return []
        return [r for r in rows if program is None or r[0] == program]

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
    # Notifications, D-Bus and KWallet are fakes too (tests that need a wallet replace KDEAICHAT_BUSCTL).
    for name in ("notify-send", "busctl"):
        path = tmp_path / ("fake-" + name)
        path.write_text(FAKE_RECORDER + ("sys.exit(1)\n" if name == "busctl" else ""))
        path.chmod(0o755)
    monkeypatch.setenv("FAKE_RECORDER_LOG", os.path.join(env.root, "recorder.log"))
    monkeypatch.setenv("KDEAICHAT_NOTIFY_SEND", str(tmp_path / "fake-notify-send"))
    monkeypatch.setenv("KDEAICHAT_BUSCTL", str(tmp_path / "fake-busctl"))
    monkeypatch.setenv("KDEAICHAT_WIDGET_RUNNING", "0")
    return env


FAKE_BUSCTL = """#!/usr/bin/env python3
# A fake `busctl --user --json=short call ...` for kwalletd6 (and NameHasOwner).
import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_RECORDER_LOG"], "a") as f:
    f.write(json.dumps(["fake-busctl"] + args) + "\\n")
call = args[args.index("call") + 1:]
method, params = call[3], call[5:]
keys = json.loads(os.environ.get("FAKE_WALLET_KEYS", "{}"))
state = os.environ.get("FAKE_WALLET", "open")
if state == "down":
    sys.exit(1)
def out(kind, value):
    print(json.dumps({"type": kind, "data": [value]}))
if method == "networkWallet":
    out("s", "kdewallet")
elif method == "isOpen":
    out("b", state == "open")
elif method == "open":
    out("i", 7 if state == "open" else -1)
elif method == "hasEntry":
    out("b", params[1] in keys and params[2] in keys[params[1]])
elif method == "readPassword":
    out("s", keys.get(params[1], {}).get(params[2], ""))
elif method == "close":
    out("i", 0)
elif method == "NameHasOwner":
    out("b", False)
else:
    sys.exit(1)
"""


class ChatEnv:
    """A widget instance (applet 7) with chats on disk and its settings, in the temp folders."""

    APPLET = "7"

    def __init__(self, sched_env, tmp_path, monkeypatch):
        from kdeaichat import qsettings_ini
        self.ini = qsettings_ini
        self.sched = sched_env
        self.dir = os.path.join(sched_env.data, "chats", "applet-" + self.APPLET)
        os.makedirs(os.path.join(self.dir, "inbox"), exist_ok=True)
        self.metas = []
        fake = tmp_path / "fake-busctl-wallet"
        fake.write_text(FAKE_BUSCTL)
        fake.chmod(0o755)
        monkeypatch.setenv("KDEAICHAT_BUSCTL", str(fake))
        self.monkeypatch = monkeypatch
        self.wallet("open", {"KDEAIChat": {}})

    def wallet(self, state, keys=None):
        self.monkeypatch.setenv("FAKE_WALLET", state)
        if keys is not None:
            self.monkeypatch.setenv("FAKE_WALLET_KEYS", json.dumps(keys))

    def add_chat(self, chat_id, messages=(), **meta):
        from kdeaichat import schedule_chat
        self.metas.append(dict({"value": chat_id, "text": "Chat " + chat_id, "source": "provider",
                                "createdAt": 1, "updatedAt": 1}, **meta))
        self.ini.write_values(os.path.join(self.dir, "index.ini"),
                              {"version": "1", "sessions": json.dumps(self.metas, separators=(",", ":"))})
        self.ini.write_values(os.path.join(self.dir, schedule_chat.file_name_for_id(chat_id)),
                              {"messages": json.dumps(list(messages), separators=(",", ":"))})

    def messages(self, chat_id):
        from kdeaichat import schedule_chat
        raw = self.ini.read_value(os.path.join(self.dir, schedule_chat.file_name_for_id(chat_id)), "messages", "[]")
        return json.loads(raw)

    def inbox(self):
        folder = os.path.join(self.dir, "inbox")
        return sorted(n for n in os.listdir(folder) if n.endswith(".ini"))

    def inbox_entry(self, name):
        return json.loads(self.ini.read_value(os.path.join(self.dir, "inbox", name), "entry"))

    def config(self, **values):
        config_home = os.environ["XDG_CONFIG_HOME"]
        os.makedirs(config_home, exist_ok=True)
        lines = ["[Containments][1][Applets][%s]" % self.APPLET, "plugin=org.kde.plasma.kdeaichat", "",
                 "[Containments][1][Applets][%s][Configuration][General]" % self.APPLET]
        for key, value in values.items():
            text = json.dumps(value, separators=(",", ":")) if isinstance(value, (list, dict)) else (
                str(value).lower() if isinstance(value, bool) else str(value))
            lines.append(f"{key}={text}")
        with open(os.path.join(config_home, "plasma-org.kde.plasma.desktop-appletsrc"), "w") as f:
            f.write("\n".join(lines) + "\n")


@pytest.fixture
def chat_env(sched_env, tmp_path, monkeypatch):
    return ChatEnv(sched_env, tmp_path, monkeypatch)
