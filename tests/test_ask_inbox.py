"""The ask inbox (kdeaichat/ask_inbox.py) and the kdeaichat-ask command (scripts/kdeaichat-ask)."""
import json
import os
import stat
import subprocess
import sys

import pytest

from kdeaichat import ask_inbox

UI = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui")
ASK = os.path.join(UI, "scripts", "kdeaichat-ask")
HELPER = os.path.join(UI, "kde_ai_helper.py")


@pytest.fixture
def inbox(tmp_path, monkeypatch):
    folder = tmp_path / "ask"
    monkeypatch.setenv("KDEAICHAT_ASK_DIR", str(folder))
    return folder


def test_written_request_is_private_and_complete(inbox, tmp_path):
    name = ask_inbox.write_item("what is this?", [str(tmp_path / "a.txt")], new_chat=True, send=True)
    assert stat.S_IMODE(os.stat(inbox).st_mode) == 0o700
    path = inbox / name
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
    assert json.loads(path.read_text()) == {"text": "what is this?", "files": [str(tmp_path / "a.txt")],
                                            "newChat": True, "send": True}
    assert not [n for n in os.listdir(inbox) if n.startswith(".tmp")]


def test_take_returns_oldest_first_and_deletes(inbox):
    ask_inbox.write_item("first")
    ask_inbox.write_item("second")
    assert [i["text"] for i in ask_inbox.take_all()] == ["first", "second"]
    assert os.listdir(inbox) == []
    assert ask_inbox.take_all() == []


def test_empty_and_oversized_requests_are_refused(inbox):
    with pytest.raises(ValueError):
        ask_inbox.write_item("   ")
    with pytest.raises(ValueError):
        ask_inbox.write_item("x" * (ask_inbox.MAX_TEXT + 1))
    with pytest.raises(ValueError):
        ask_inbox.write_item("", ["/a"] * 11)


def test_bad_files_in_the_folder_are_dropped_not_trusted(inbox):
    ask_inbox.ensure_dir()
    (inbox / "ask-1-aa.json").write_text("not json")
    (inbox / "ask-2-bb.json").write_text(json.dumps({"text": "ok", "files": ["relative", 5, "/abs/file"], "newChat": "yes"}))
    (inbox / "ask-3-cc.json").write_text(json.dumps(["list"]))
    (inbox / ".tmp-half").write_text("{")      # a request still being written is left alone
    (inbox / "other.json").write_text("{}")
    items = ask_inbox.take_all()
    assert items == [{"text": "ok", "files": ["/abs/file"], "newChat": False, "send": False}]
    assert sorted(os.listdir(inbox)) == [".tmp-half", "other.json"]


def test_old_requests_are_dropped(inbox):
    name = ask_inbox.write_item("stale")
    old = os.stat(inbox / name).st_mtime - ask_inbox.MAX_AGE - 10
    os.utime(inbox / name, (old, old))
    assert ask_inbox.take_all() == []


def test_a_folder_others_can_open_is_made_private(inbox):
    os.makedirs(inbox, mode=0o777)
    os.chmod(inbox, 0o755)
    ask_inbox.ensure_dir()
    assert stat.S_IMODE(os.stat(inbox).st_mode) == 0o700


def test_helper_command_takes_the_requests(inbox):
    ask_inbox.write_item("via helper", send=True)
    out = subprocess.run([sys.executable, HELPER, "ask_inbox_take"], capture_output=True, text=True, check=True,
                         env={**os.environ, "KDEAICHAT_ASK_DIR": str(inbox)}).stdout
    data = json.loads(out)
    assert data["type"] == "ask_items" and data["directory"] == str(inbox)
    assert data["items"] == [{"text": "via helper", "files": [], "newChat": False, "send": True}]


def run_ask(inbox, *args, stdin=None):
    return subprocess.run([sys.executable, ASK, *args], input=stdin, capture_output=True, text=True,
                          env={**os.environ, "KDEAICHAT_ASK_DIR": str(inbox)})


def test_command_with_text_files_and_stdin(inbox, tmp_path):
    doc = tmp_path / "report.pdf"
    doc.write_bytes(b"%PDF")
    assert run_ask(inbox, "--send", "--new-chat", "why", "is", "the", "sky", "blue").returncode == 0
    assert run_ask(inbox, "--stdin", "--file", str(doc), stdin="private question\n").returncode == 0
    assert run_ask(inbox, "--files", str(doc)).returncode == 0
    items = ask_inbox.take_all()
    assert items[0] == {"text": "why is the sky blue", "files": [], "newChat": True, "send": True}
    assert items[1] == {"text": "private question", "files": [os.path.realpath(doc)], "newChat": False, "send": False}
    assert items[2]["text"] == "" and items[2]["files"] == [os.path.realpath(doc)]


def test_command_reports_problems(inbox, tmp_path):
    missing = run_ask(inbox, "--files", str(tmp_path / "nope.txt"))
    assert missing.returncode == 2 and "not a file" in missing.stderr
    nothing = run_ask(inbox)
    assert nothing.returncode == 1 and "nothing to send" in nothing.stderr
