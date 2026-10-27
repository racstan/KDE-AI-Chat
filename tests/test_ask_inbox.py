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
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    return folder


@pytest.fixture
def home(inbox, tmp_path):
    return tmp_path / "home"


@pytest.fixture
def notes_log(tmp_path):
    """A stand-in notify-send (found through KDEAICHAT_SELECTION_PATH) that logs its arguments: no real notification."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log = tmp_path / "notify.log"
    tool = bin_dir / "notify-send"
    tool.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> ' + str(log) + "\n")
    tool.chmod(0o755)
    return bin_dir, log


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
    assert items == [{"text": "ok", "files": [], "newChat": False, "send": False,
                      "notes": [{"reason": "outside", "name": "file"}]}]
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
    assert data["items"] == [{"text": "via helper", "files": [], "newChat": False, "send": True, "notes": []}]


def run_ask(inbox, *args, stdin=None, tools=None):
    # Never a real notification: notify-send is looked up only in this folder (an empty one unless a test gives a stub).
    tools = tools or str(inbox) + "-no-tools"
    os.makedirs(tools, exist_ok=True)
    return subprocess.run([sys.executable, ASK, *args], input=stdin, capture_output=True, text=True,
                          env={**os.environ, "KDEAICHAT_ASK_DIR": str(inbox), "KDEAICHAT_SELECTION_PATH": str(tools)})


def test_command_with_text_files_and_stdin(inbox, home):
    doc = home / "report.pdf"
    doc.write_bytes(b"%PDF")
    assert run_ask(inbox, "--send", "--new-chat", "why", "is", "the", "sky", "blue").returncode == 0
    assert run_ask(inbox, "--stdin", "--file", str(doc), stdin="private question\n").returncode == 0
    assert run_ask(inbox, "--files", str(doc)).returncode == 0
    items = ask_inbox.take_all()
    assert items[0] == {"text": "why is the sky blue", "files": [], "newChat": True, "send": True, "notes": []}
    assert items[1] == {"text": "private question", "files": [os.path.realpath(doc)], "newChat": False, "send": False,
                        "notes": []}
    assert items[2]["text"] == "" and items[2]["files"] == [os.path.realpath(doc)]


def test_command_reports_problems(inbox, tmp_path):
    missing = run_ask(inbox, "--files", str(tmp_path / "nope.txt"))
    assert missing.returncode == 2 and "not a file" in missing.stderr
    nothing = run_ask(inbox)
    assert nothing.returncode == 1 and "nothing to send" in nothing.stderr


def test_files_never_send_by_themselves(inbox, home):
    doc = home / "a.txt"
    doc.write_text("x")
    ask_inbox.write_item("summarise", [str(doc)], send=True)
    ask_inbox.write_item("just text", send=True)
    first, second = ask_inbox.take_all()
    assert first["files"] == [os.path.realpath(doc)] and first["send"] is False
    assert second["send"] is True


def test_dot_folders_and_outside_home_are_refused_with_a_note(inbox, home, tmp_path):
    (home / ".ssh").mkdir()
    (home / ".ssh" / "id_rsa").write_text("secret")
    (home / "docs" / ".git").mkdir(parents=True)
    (home / "docs" / ".git" / "config").write_text("x")
    (home / ".bashrc").write_text("x")
    (home / "docs" / "ok.txt").write_text("ok")
    outside = tmp_path / "outside.txt"
    outside.write_text("x")
    link = home / "docs" / "link.txt"
    link.symlink_to(home / ".ssh" / "id_rsa")      # a symlink into a dot-folder is resolved first
    link2 = home / "docs" / "link2.txt"
    link2.symlink_to(outside)
    paths = [home / ".ssh" / "id_rsa", home / "docs" / ".git" / "config", home / ".bashrc", outside, link, link2,
             home / "docs" / "missing.txt", home / "docs", home / "docs" / "ok.txt"]
    ask_inbox.write_item("look", [str(p) for p in paths])
    (item,) = ask_inbox.take_all()
    assert item["files"] == [os.path.realpath(home / "docs" / "ok.txt")]
    reasons = [(n["reason"], n["name"]) for n in item["notes"]]
    assert reasons == [("hidden", "id_rsa"), ("hidden", "config"), ("hidden", ".bashrc"), ("outside", "outside.txt"),
                       ("hidden", "link.txt"), ("outside", "link2.txt"), ("unreadable", "missing.txt"),
                       ("unreadable", "docs")]
    assert item["send"] is False


def test_files_on_mounted_drives_are_attached(inbox, home, tmp_path, monkeypatch):
    drive = tmp_path / "media" / "me" / "USB"
    drive.mkdir(parents=True)
    (drive / "photo.jpg").write_text("x")
    (drive / ".Trash-1000").mkdir()
    (drive / ".Trash-1000" / "old.txt").write_text("x")
    monkeypatch.setattr(ask_inbox, "MOUNT_ROOTS", (str(tmp_path / "media"),))
    ask_inbox.write_item("look", [str(drive / "photo.jpg"), str(drive / ".Trash-1000" / "old.txt")])
    (item,) = ask_inbox.take_all()
    assert item["files"] == [os.path.realpath(drive / "photo.jpg")]
    assert [(n["reason"], n["name"]) for n in item["notes"]] == [("hidden", "old.txt")]


def test_more_than_ten_files_from_dolphin_are_cut_with_a_notification(inbox, home, notes_log):
    bin_dir, log = notes_log
    docs = []
    for i in range(25):
        doc = home / ("f%02d.txt" % i)
        doc.write_text("x")
        docs.append(str(doc))
    done = run_ask(inbox, "--files", *docs, tools=str(bin_dir))
    assert done.returncode == 0
    assert "Attached 10 of 25 files; the limit is 10" in log.read_text()
    (item,) = ask_inbox.take_all()
    assert item["files"] == [os.path.realpath(d) for d in docs[:10]]


def test_errors_from_the_command_are_also_notified_without_a_terminal(inbox, home, notes_log):
    bin_dir, log = notes_log
    assert run_ask(inbox, "--files", str(home / "nope.txt"), tools=str(bin_dir)).returncode == 2
    assert run_ask(inbox, tools=str(bin_dir)).returncode == 1
    text = log.read_text()
    assert "not a file" in text and "nothing to send" in text
