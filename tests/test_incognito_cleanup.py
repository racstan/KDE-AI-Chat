"""incognito_cleanup (kdeaichat/chats.py): what an incognito chat leaves while it is open goes when it closes."""
import contextlib
import io
import json
import os
import sys
import tempfile
from unittest.mock import patch

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kdeaichat import chats  # noqa: E402


def _run(payload):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        chats.cmd_incognito_cleanup(payload)
    return json.loads(out.getvalue())


def _touch(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").close()


@contextlib.contextmanager
def _folder():
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        directory = os.path.join(chats.chats_root(), "applet-7")
        with contextlib.redirect_stdout(io.StringIO()):
            chats.cmd_prepare_chat_dir({"directory": directory})
        yield data, directory


def _layout(data, directory):
    root = os.path.join(data, "kdeaichat")
    _touch(os.path.join(directory, "images", "s-incognito-1-1", "m-1-0.png"))
    _touch(os.path.join(directory, "images", "s-incognito-2-2", "m-2-0.png"))
    _touch(os.path.join(directory, "images", "s-17-3", "m-3-0.png"))          # a stored chat's image
    _touch(os.path.join(directory, "chat-s-17-3.ini"))
    _touch(os.path.join(root, "pi-instructions", "s-incognito-1-1.md"))
    _touch(os.path.join(root, "pi-instructions", "s-17-3.md"))
    os.makedirs(os.path.join(root, "pi-workspaces", "s-incognito-1-1"))       # empty: removed
    _touch(os.path.join(root, "pi-workspaces", "s-incognito-2-2", "made-by-pi.txt"))  # kept: Pi made a file
    return root


def test_one_closed_chat_loses_its_images_and_pi_files_only():
    with _folder() as (data, directory):
        root = _layout(data, directory)
        result = _run({"directory": directory, "chat": "s-incognito-1-1"})
        assert sorted(result["removed"]) == ["images/s-incognito-1-1", "pi-instructions/s-incognito-1-1.md",
                                             "pi-workspaces/s-incognito-1-1"]
        assert sorted(os.listdir(os.path.join(directory, "images"))) == ["s-17-3", "s-incognito-2-2"]
        assert os.listdir(os.path.join(root, "pi-instructions")) == ["s-17-3.md"]


def test_at_start_every_incognito_leftover_goes_but_files_pi_made_stay():
    with _folder() as (data, directory):
        root = _layout(data, directory)
        _touch(os.path.join(directory, "chat-s-incognito-9-9.ini"))
        _run({"directory": directory})
        assert os.listdir(os.path.join(directory, "images")) == ["s-17-3"]
        assert "chat-s-incognito-9-9.ini" not in os.listdir(directory)
        assert "chat-s-17-3.ini" in os.listdir(directory)
        assert os.listdir(os.path.join(root, "pi-workspaces")) == ["s-incognito-2-2"]


def test_symlinks_are_not_followed():
    with _folder() as (data, directory):
        outside = os.path.join(data, "outside")
        _touch(os.path.join(outside, "keep.png"))
        os.makedirs(os.path.join(directory, "images"))
        os.symlink(outside, os.path.join(directory, "images", "s-incognito-1-1"))
        _run({"directory": directory})
        assert os.path.exists(os.path.join(outside, "keep.png"))


@pytest.mark.parametrize("chat", ["s-17-3", "../x", "s-incognito-", "s-incognito-a/b"])
def test_only_incognito_ids_are_accepted(chat):
    with _folder() as (data, directory):
        with pytest.raises(ValueError):
            _run({"directory": directory, "chat": chat})


def test_directory_must_be_an_applet_folder():
    with _folder() as (data, directory):
        with pytest.raises(ValueError):
            _run({"directory": data})
