"""Installing and removing the KRunner runner and the Dolphin menu (kdeaichat/desktop_integration.py).
Every folder is a temp folder: the real ~/.local/share/{krunner,kio,dbus-1} is never touched."""
import configparser
import json
import os
import stat
import subprocess
import sys

import pytest

from kdeaichat import desktop_integration as di

UI = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui")
HELPER = os.path.join(UI, "kde_ai_helper.py")


@pytest.fixture
def dirs(tmp_path, monkeypatch):
    out = {"KDEAICHAT_KRUNNER_DIR": tmp_path / "krunner", "KDEAICHAT_DBUS_SERVICE_DIR": tmp_path / "dbus",
           "KDEAICHAT_SERVICEMENU_DIR": tmp_path / "menus", "KDEAICHAT_APPLICATIONS_DIR": tmp_path / "apps", "KDEAICHAT_DESKTOP_STATE": tmp_path / "data" / "state.json"}
    for key, value in out.items():
        monkeypatch.setenv(key, str(value))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "xdg"))
    return {k: v for k, v in out.items()}


def names(folder):
    return sorted(os.listdir(folder)) if os.path.isdir(folder) else []


def test_off_by_default_writes_nothing(dirs, tmp_path):
    status = di.status()
    assert status == {"type": "desktop_status", "krunner": False, "dolphin": False, "selection": False, "prefix": "ai", "errors": []}
    assert di.sync(False, False)["krunner"] is False
    assert not (tmp_path / "krunner").exists() and not (tmp_path / "menus").exists() and not (tmp_path / "xdg").exists()
    assert not (tmp_path / "apps").exists()


def test_krunner_files(dirs, tmp_path):
    status = di.sync(True, False, "chat")
    assert status["krunner"] is True and status["dolphin"] is False and status["prefix"] == "chat" and status["errors"] == []
    assert names(tmp_path / "krunner") == ["kdeaichat-runner.desktop"]
    assert names(tmp_path / "dbus") == ["org.kde.kdeaichat.runner.service"]
    assert names(tmp_path / "menus") == []
    desktop = configparser.ConfigParser(interpolation=None)
    desktop.optionxform = str
    desktop.read(tmp_path / "krunner" / "kdeaichat-runner.desktop")
    entry = desktop["Desktop Entry"]
    assert entry["X-Plasma-API"] == "DBus" and entry["X-Plasma-DBusRunner-Service"] == "org.kde.kdeaichat.runner"
    assert entry["X-Plasma-DBusRunner-Path"] == "/runner" and entry["X-KDE-ServiceTypes"] == "Plasma/Runner"
    assert entry["X-KDE-PluginInfo-EnabledByDefault"] == "true", "KRunner skips a runner that is off by default"
    service = configparser.ConfigParser(interpolation=None)
    service.optionxform = str
    service.read(tmp_path / "dbus" / "org.kde.kdeaichat.runner.service")
    assert service["D-BUS Service"]["Name"] == "org.kde.kdeaichat.runner"
    exe, script = service["D-BUS Service"]["Exec"].split(" ", 1)
    assert os.path.isabs(exe) and script.endswith("scripts/kdeaichat-runner") and os.path.isfile(script)
    assert json.loads((tmp_path / "data" / "state.json").read_text())["prefix"] == "chat"
    assert stat.S_IMODE(os.stat(tmp_path / "data" / "state.json").st_mode) == 0o600


def test_dolphin_menu_is_executable_and_kde6_shaped(dirs, tmp_path):
    assert di.sync(False, True)["dolphin"] is True
    path = tmp_path / "menus" / "kdeaichat-ask.desktop"
    assert os.stat(path).st_mode & stat.S_IXUSR
    desktop = configparser.ConfigParser(interpolation=None)
    desktop.optionxform = str
    desktop.read(path)
    entry = desktop["Desktop Entry"]
    mimes = entry["MimeType"].split(";")
    assert entry["Type"] == "Service" and entry["Actions"] == "askKdeAiChat"
    assert {"application/pdf", "text/plain", "image/png"} <= set(mimes)
    action = desktop["Desktop Action askKdeAiChat"]
    assert action["Name"] == "Ask KDE AI Chat about this file"
    assert action["Exec"].endswith("scripts/kdeaichat-ask --files %F")
    assert names(tmp_path / "krunner") == []


def test_selection_shortcut_entry(dirs, tmp_path):
    status = di.sync(False, False, selection=True)
    assert status["selection"] is True and status["errors"] == [] and status["krunner"] is False
    assert names(tmp_path / "apps") == ["kdeaichat-ask-selection.desktop"]
    path = tmp_path / "apps" / "kdeaichat-ask-selection.desktop"
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o755
    desktop = configparser.ConfigParser(interpolation=None)
    desktop.optionxform = str
    desktop.read(path)
    entry = desktop["Desktop Entry"]
    assert entry["Type"] == "Application" and entry["X-KDE-Shortcuts"] == "Meta+Alt+A"
    assert entry["Exec"].endswith("scripts/kdeaichat-ask --selection") and entry["X-KDEAIChat-Managed"] == "true"
    assert "NoDisplay" not in entry, "stays listed so System Settings can show and change its shortcut"
    assert json.loads((tmp_path / "data" / "state.json").read_text())["selection"] is True
    assert di.sync(False, False, selection=True)["errors"] == []   # again: replaced in place
    assert names(tmp_path / "apps") == ["kdeaichat-ask-selection.desktop"]
    assert di.sync(False, False)["selection"] is False
    assert names(tmp_path / "apps") == []


def test_selection_shortcut_never_replaces_a_foreign_file(dirs, tmp_path):
    os.makedirs(tmp_path / "apps")
    foreign = tmp_path / "apps" / "kdeaichat-ask-selection.desktop"
    foreign.write_text("[Desktop Entry]\nName=Mine\n")
    status = di.sync(False, False, selection=True)
    assert status["selection"] is False and "not from KDE AI Chat" in status["errors"][0]
    di.sync(False, False)
    assert foreign.read_text() == "[Desktop Entry]\nName=Mine\n"


def test_switching_off_removes_only_our_files(dirs, tmp_path):
    di.sync(True, True)
    (tmp_path / "menus" / "other.desktop").write_text("[Desktop Entry]\n")
    status = di.sync(False, False)
    assert (status["krunner"], status["dolphin"]) == (False, False)
    assert names(tmp_path / "krunner") == [] and names(tmp_path / "dbus") == []
    assert names(tmp_path / "menus") == ["other.desktop"]
    assert json.loads((tmp_path / "data" / "state.json").read_text())["krunner"] is False


def test_a_foreign_file_with_our_name_is_never_replaced_or_deleted(dirs, tmp_path):
    os.makedirs(tmp_path / "menus")
    foreign = tmp_path / "menus" / "kdeaichat-ask.desktop"
    foreign.write_text("[Desktop Entry]\nName=Mine\n")
    status = di.sync(False, True)
    assert status["dolphin"] is False and "not from KDE AI Chat" in status["errors"][0]
    assert foreign.read_text() == "[Desktop Entry]\nName=Mine\n"
    di.sync(False, False)
    assert foreign.exists()


def test_syncing_again_updates_in_place_and_leaves_no_temp_files(dirs, tmp_path):
    di.sync(True, True, "ai")
    di.sync(True, True, "ask")
    assert di.status()["prefix"] == "ask"
    assert names(tmp_path / "krunner") == ["kdeaichat-runner.desktop"]
    assert names(tmp_path / "menus") == ["kdeaichat-ask.desktop"]
    assert names(tmp_path / "dbus") == ["org.kde.kdeaichat.runner.service"]


def test_bus_reloaded_and_krunner_restarted_only_when_the_runner_changes(dirs, monkeypatch):
    calls = []
    monkeypatch.setattr(di, "_reload_bus", lambda: calls.append("reload"))
    monkeypatch.setattr(di, "_restart_krunner", lambda: calls.append("restart"))
    di.sync(True, False, "ai")
    assert calls == ["reload", "restart"], "new files: the bus must learn the service, KRunner the runner"
    calls.clear()
    di.sync(True, False, "ai", restart_krunner=True)
    di.sync(True, True, "ask")
    assert calls == [], "nothing about the runner changed"
    di.sync(False, True, "ask", restart_krunner=True)
    assert calls == ["reload", "restart"]


def test_no_desktop_tools_run_when_the_folders_are_redirected(dirs, monkeypatch):
    ran = []
    monkeypatch.setattr(di.subprocess, "run", lambda *a, **k: ran.append(a))
    di.sync(True, False, "ai", restart_krunner=True)
    assert ran == []


@pytest.mark.parametrize("raw,expected", [("ai", "ai"), ("  hey ", "hey"), ("", "ai"), ("two words", "ai"), ("x" * 30, "ai"), (5, "ai"), ('a"b', "ai")])
def test_prefix_is_cleaned(raw, expected):
    assert di.clean_prefix(raw) == expected


def test_paths_with_spaces_are_quoted():
    assert di._quote("/a b/c") == '"/a b/c"'
    assert di._quote("/plain/path") == "/plain/path"
    assert di._quote('/a"b$') == '"/a\\"b\\$"'


def test_helper_commands(dirs, tmp_path):
    def run(command, payload=None):
        import base64
        args = [sys.executable, HELPER, command]
        if payload is not None:
            args.append(base64.b64encode(json.dumps(payload).encode()).decode())
        return json.loads(subprocess.run(args, capture_output=True, text=True, check=True, env=os.environ).stdout)
    assert run("desktop_status")["krunner"] is False
    assert run("desktop_sync", {"krunner": True, "dolphin": True, "prefix": "ai"})["krunner"] is True
    assert run("desktop_status")["dolphin"] is True
    assert run("desktop_sync", {"krunner": False, "dolphin": False})["dolphin"] is False
    assert names(tmp_path / "krunner") == []
    assert run("desktop_sync", {"selection": True})["selection"] is True
    assert names(tmp_path / "apps") == ["kdeaichat-ask-selection.desktop"]
    assert run("desktop_sync", {})["selection"] is False
    assert names(tmp_path / "apps") == []
