"""Filesystem commands behind store/ChatStore.qml."""
import json
import os
import stat
import sys
import tempfile
from unittest.mock import patch

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kdeaichat import chats  # noqa: E402


def _mode(path):
    return stat.S_IMODE(os.stat(path).st_mode)


def test_prepare_makes_folder_private_and_tightens_files():
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        directory = os.path.join(chats.chats_root(), "applet-40")
        os.makedirs(directory, mode=0o755)
        open(os.path.join(directory, "chat-a.ini"), "w").close()
        os.chmod(os.path.join(directory, "chat-a.ini"), 0o644)

        chats.cmd_prepare_chat_dir({"directory": directory})

        assert _mode(directory) == 0o700
        assert _mode(chats.chats_root()) == 0o700
        assert _mode(os.path.join(directory, "chat-a.ini")) == 0o600
        assert _mode(os.path.join(directory, "inbox")) == 0o700  # scheduled runs land here


def test_delete_removes_only_named_chat_files():
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        directory = os.path.join(chats.chats_root(), "applet-1")
        chats.cmd_prepare_chat_dir({"directory": directory})
        for name in ("chat-a.ini", "chat-b%3Ac.ini", "index.ini"):
            open(os.path.join(directory, name), "w").close()

        chats.cmd_delete_chat_files({"directory": directory, "files": ["chat-a.ini", "chat-b%3Ac.ini", "chat-gone.ini"]})

        assert sorted(os.listdir(directory)) == ["inbox", "index.ini"]


@pytest.mark.parametrize("name", ["index.ini", "../x.ini", "chat-a/../../x.ini", "chat-.ini.bak", "x.ini"])
def test_delete_rejects_other_names(name):
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        directory = os.path.join(chats.chats_root(), "applet-1")
        chats.cmd_prepare_chat_dir({"directory": directory})
        with pytest.raises(ValueError):
            chats.cmd_delete_chat_files({"directory": directory, "files": [name]})


@pytest.mark.parametrize("sub", ["", "applet-1/..", "../applet-1", "other", "applet-1/nested"])
def test_directory_must_be_an_applet_folder(sub):
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        with pytest.raises(ValueError):
            chats.cmd_prepare_chat_dir({"directory": os.path.join(chats.chats_root(), sub)})


def _folder():
    directory = os.path.join(chats.chats_root(), "applet-1")
    chats.cmd_prepare_chat_dir({"directory": directory})
    return directory


def test_keep_damaged_file_copies_once_and_leaves_the_original(capsys):
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        directory = _folder()
        path = os.path.join(directory, "chat-a.ini")
        with open(path, "w") as f:
            f.write("[General]\nmessages=[{\"role\"")
        chats.cmd_keep_damaged_file({"directory": directory, "file": "chat-a.ini", "stamp": "20261027-101500"})
        copy = path + ".damaged-20261027-101500"
        assert open(copy).read() == open(path).read()
        assert _mode(copy) == 0o600
        # A second copy with the same stamp does not replace the first.
        with open(path, "a") as f:
            f.write("more")
        chats.cmd_keep_damaged_file({"directory": directory, "file": "chat-a.ini", "stamp": "20261027-101500"})
        assert not open(copy).read().endswith("more")
        assert '"copied": false' in capsys.readouterr().out


@pytest.mark.parametrize("name,stamp", [("../x.ini", "20261027-101500"), ("projects.ini", "20261027-101500"),
                                        ("chat-a.ini", "../../etc"), ("chat-a.ini", "2026")])
def test_keep_damaged_file_rejects_bad_input(name, stamp):
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        with pytest.raises(ValueError):
            chats.cmd_keep_damaged_file({"directory": _folder(), "file": name, "stamp": stamp})


def test_list_chat_files_lists_only_chat_files(capsys):
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        directory = _folder()
        for name in ("chat-a.ini", "chat-b%3Ac.ini", "index.ini", "chat-a.ini.damaged-20261027-101500", "projects.ini"):
            open(os.path.join(directory, name), "w").close()
        os.symlink("/etc/passwd", os.path.join(directory, "chat-link.ini"))
        capsys.readouterr()
        chats.cmd_list_chat_files({"directory": directory})
        assert json.loads(capsys.readouterr().out)["files"] == ["chat-a.ini", "chat-b%3Ac.ini"]
