"""Attached files kept as files (kdeaichat/attachments.py): content-addressed, private, read back, deleted with the chat."""
import base64
import contextlib
import hashlib
import io
import json
import os
import stat
import sys
import tempfile
from unittest.mock import patch

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kdeaichat import attachments, chats  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32


@pytest.fixture
def chat_dir():
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        directory = os.path.join(chats.chats_root(), "applet-7")
        chats.cmd_prepare_chat_dir({"directory": directory})
        yield directory


def run(command, payload):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        command(payload)
    return json.loads(out.getvalue())


def store(directory, items, chat="s-1-2"):
    return run(attachments.cmd_attachment_store, {"directory": directory, "chat": chat, "items": items})["items"]


def image_item(data=PNG):
    return {"kind": "base64", "content": base64.b64encode(data).decode(), "mime": "image/png"}


def test_image_is_stored_by_hash_privately(chat_dir):
    [result] = store(chat_dir, [image_item()])
    digest = hashlib.sha256(PNG).hexdigest()
    assert result == {"ok": True, "hash": digest, "file": "attachments/s-1-2/%s.png" % digest, "bytes": len(PNG)}
    full = os.path.join(chat_dir, result["file"])
    assert open(full, "rb").read() == PNG
    assert stat.S_IMODE(os.stat(full).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(os.path.dirname(full)).st_mode) == 0o700
    assert stat.S_IMODE(os.stat(os.path.join(chat_dir, "attachments")).st_mode) == 0o700


def test_same_bytes_are_stored_once(chat_dir):
    first = store(chat_dir, [image_item(), image_item()])
    again = store(chat_dir, [image_item()])
    assert first[0]["file"] == first[1]["file"] == again[0]["file"]
    assert os.listdir(os.path.join(chat_dir, "attachments", "s-1-2")) == [os.path.basename(first[0]["file"])]


def test_text_is_stored_as_utf8(chat_dir):
    [result] = store(chat_dir, [{"kind": "text", "content": "héllo wörld"}])
    assert result["file"].endswith(".txt")
    assert open(os.path.join(chat_dir, result["file"]), encoding="utf-8").read() == "héllo wörld"


def test_a_damaged_existing_file_is_replaced(chat_dir):
    [result] = store(chat_dir, [image_item()])
    full = os.path.join(chat_dir, result["file"])
    open(full, "wb").write(b"broken")
    store(chat_dir, [image_item()])
    assert open(full, "rb").read() == PNG


def test_bad_items_are_reported_not_fatal(chat_dir):
    results = store(chat_dir, [{"kind": "base64", "content": "!!not base64!!"}, {"kind": "zip", "content": "x"}, {}, image_item()])
    assert [r["ok"] for r in results] == [False, False, False, True]


def test_incognito_chat_keeps_no_files(chat_dir):
    with pytest.raises(ValueError):
        store(chat_dir, [image_item()], chat="s-incognito-abc")
    assert not os.path.exists(os.path.join(chat_dir, "attachments"))


def test_read_returns_the_content_and_checks_the_hash(chat_dir):
    [image, text] = store(chat_dir, [image_item(), {"kind": "text", "content": "notes"}])
    out = run(attachments.cmd_attachment_read, {"directory": chat_dir, "items": [
        {"file": image["file"], "kind": "base64"}, {"file": text["file"], "kind": "text"}]})["items"]
    assert base64.b64decode(out[0]["content"]) == PNG
    assert out[1]["content"] == "notes"
    open(os.path.join(chat_dir, image["file"]), "wb").write(b"changed")
    damaged = run(attachments.cmd_attachment_read, {"directory": chat_dir, "items": [{"file": image["file"], "kind": "base64"}]})["items"][0]
    assert damaged["ok"] is False


@pytest.mark.parametrize("rel", ["../x", "attachments/../../x.png", "attachments/a/b.png", "images/s/" + "0" * 64 + ".png",
                                 "attachments/s-1-2/" + "0" * 64 + ".png", "/etc/passwd"])
def test_read_refuses_other_paths(chat_dir, rel):
    out = run(attachments.cmd_attachment_read, {"directory": chat_dir, "items": [{"file": rel, "kind": "text"}]})["items"][0]
    assert out["ok"] is False


def test_delete_removes_the_chats_folder_only(chat_dir):
    a = store(chat_dir, [image_item()], chat="a")[0]
    b = store(chat_dir, [image_item()], chat="b")[0]
    assert run(attachments.cmd_attachment_delete, {"directory": chat_dir, "chats": ["a", "missing"]}) == {"deleted": 1}
    assert not os.path.exists(os.path.join(chat_dir, a["file"]))
    assert os.path.exists(os.path.join(chat_dir, b["file"]))
    run(attachments.cmd_attachment_delete, {"directory": chat_dir, "chats": ["b"]})
    assert not os.path.exists(os.path.join(chat_dir, "attachments"))


def test_directory_must_be_an_applet_folder(chat_dir):
    with pytest.raises(ValueError):
        store("/tmp", [image_item()])
