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
           "KDEAICHAT_SERVICEMENU_DIR": tmp_path / "menus", "KDEAICHAT_DESKTOP_STATE": tmp_path / "data" / "state.json"}
    for key, value in out.items():
        monkeypatch.setenv(key, str(value))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "xdg"))
    return {k: v for k, v in out.items()}


def names(folder):
    return sorted(os.listdir(folder)) if os.path.isdir(folder) else []


def test_off_by_default_writes_nothing(dirs, tmp_path):
    status = di.status()
    assert status == {"type": "desktop_status", "krunner": False, "dolphin": False, "prefix": "ai", "errors": []}
    assert di.sync(False, False)["krunner"] is False
    assert not (tmp_path / "krunner").exists() and not (tmp_path / "menus").exists() and not (tmp_path / "xdg").exists()


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
