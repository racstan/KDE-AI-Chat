"""The memory store behind store/MemoryStore.qml (kdeaichat/memory.py)."""
import base64
import json
import os
import stat
import subprocess
import sys
import tempfile
from unittest.mock import patch

import pytest

UI_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI_DIR)

from kdeaichat import memory  # noqa: E402


@pytest.fixture
def data_home():
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        yield data


def run(capsys, command, payload=None):
    memory.COMMANDS[command](payload or {})
    return json.loads(capsys.readouterr().out)


def _mode(path):
    return stat.S_IMODE(os.stat(path).st_mode)


def test_empty_store_lists_nothing(data_home, capsys):
    assert run(capsys, "memory_list") == {"memories": []}
    assert not os.path.exists(memory.memory_path())


def test_add_writes_a_private_file_with_every_field(data_home, capsys):
    out = run(capsys, "memory_add", {"items": [
        {"text": "  I use Fedora  ", "scope": "all", "pinned": True},
        {"text": "Uses pytest", "scope": "project", "projectId": "p-1-2", "chatId": "ignored"},
        {"text": "Call me Ana", "scope": "chat", "chatId": "s-1-2", "enabled": False, "sourceChatId": "s-1-2"},
    ]})
    assert len(out["added"]) == 3 and out["existing"] == []
    first, project, chat = out["memories"]
    assert first["text"] == "I use Fedora" and first["pinned"] is True and first["enabled"] is True
    assert first["projectId"] == "" and first["chatId"] == ""
    assert project["projectId"] == "p-1-2" and project["chatId"] == ""
    assert chat["enabled"] is False and chat["sourceChatId"] == "s-1-2"
    assert all(m["id"].startswith("m-") and m["created"] > 0 for m in out["memories"])
    path = memory.memory_path()
    assert _mode(path) == 0o600
    assert _mode(os.path.dirname(path)) == 0o700
    with open(path, encoding="utf-8") as f:
        assert json.load(f) == {"version": 1, "memories": out["memories"]}
    assert run(capsys, "memory_list")["memories"] == out["memories"]


def test_adding_the_same_memory_twice_keeps_one(data_home, capsys):
    first = run(capsys, "memory_add", {"items": [{"text": "Likes tea", "scope": "all"}]})
    again = run(capsys, "memory_add", {"items": [{"text": " likes   TEA ", "scope": "all"},
                                                 {"text": "Likes tea", "scope": "chat", "chatId": "s-1"}]})
    assert again["existing"] == first["added"]
    assert len(again["added"]) == 1
    assert len(again["memories"]) == 2


def test_add_keeps_a_given_id_for_undo(data_home, capsys):
    out = run(capsys, "memory_add", {"items": [{"text": "x", "scope": "all", "id": "m-0123456789abcdef", "created": 5}]})
    assert out["memories"][0]["id"] == "m-0123456789abcdef" and out["memories"][0]["created"] == 5
    bad = run(capsys, "memory_add", {"items": [{"text": "y", "scope": "all", "id": "../evil"}]})
    assert bad["added"][0] != "../evil" and bad["added"][0].startswith("m-")


@pytest.mark.parametrize("item", [
    {"text": "", "scope": "all"},
    {"text": "   ", "scope": "all"},
    {"text": 5, "scope": "all"},
    {"text": "x" * (memory.MAX_TEXT + 1), "scope": "all"},
    {"text": "a\x00b", "scope": "all"},
    {"text": "x", "scope": "everyone"},
    {"text": "x", "scope": "project"},
    {"text": "x", "scope": "project", "projectId": "../p"},
    {"text": "x", "scope": "chat", "chatId": "a/b"},
    {"text": "x", "scope": "all", "sourceChatId": "a b"},
    "not an object",
])
def test_add_rejects_bad_items_and_writes_nothing(data_home, capsys, item):
    with pytest.raises(ValueError):
        memory.cmd_memory_add({"items": [{"text": "good", "scope": "all"}, item]})
    assert not os.path.exists(memory.memory_path())


def test_caps_on_items_per_call_and_total_count(data_home, capsys):
    with pytest.raises(ValueError):
        memory.cmd_memory_add({"items": [{"text": str(i)} for i in range(memory.MAX_ITEMS_PER_CALL + 1)]})
    with patch.object(memory, "MAX_MEMORIES", 3):
        run(capsys, "memory_add", {"items": [{"text": "a"}, {"text": "b"}, {"text": "c"}]})
        with pytest.raises(ValueError):
            memory.cmd_memory_add({"items": [{"text": "d"}]})
        # A duplicate is not a new memory, so it still works at the cap.
        assert len(run(capsys, "memory_add", {"items": [{"text": "a"}]})["existing"]) == 1
    assert len(memory.load()) == 3


def test_text_of_exactly_the_cap_is_kept(data_home, capsys):
    out = run(capsys, "memory_add", {"items": [{"text": "x" * memory.MAX_TEXT}]})
    assert len(out["memories"][0]["text"]) == memory.MAX_TEXT


def test_update_changes_fields_and_validates(data_home, capsys):
    added = run(capsys, "memory_add", {"items": [{"text": "a"}, {"text": "b"}]})
    first, second = added["added"]
    out = run(capsys, "memory_update", {"id": first, "text": "A!", "pinned": True, "enabled": False})
    assert out["memory"]["text"] == "A!" and out["memory"]["pinned"] and not out["memory"]["enabled"]
    out = run(capsys, "memory_update", {"id": first, "scope": "chat", "chatId": "s-9"})
    assert out["memory"]["scope"] == "chat" and out["memory"]["chatId"] == "s-9"
    for bad in ({"id": "m-ffffffffffffffff", "text": "x"}, {"id": "nope"}, {"id": second, "text": ""},
                {"id": second, "scope": "project"}, {"id": second, "text": "x" * (memory.MAX_TEXT + 1)}):
        with pytest.raises(ValueError):
            memory.cmd_memory_update(bad)
    # Turning `b` into a copy of another memory is refused.
    run(capsys, "memory_add", {"items": [{"text": "c"}]})
    with pytest.raises(ValueError):
        memory.cmd_memory_update({"id": second, "text": "c"})
    assert [m["text"] for m in memory.load()] == ["A!", "b", "c"]


def test_delete_by_id_chat_and_project(data_home, capsys):
    out = run(capsys, "memory_add", {"items": [
        {"text": "global"},
        {"text": "proj", "scope": "project", "projectId": "p-1"},
        {"text": "other proj", "scope": "project", "projectId": "p-2"},
        {"text": "chat", "scope": "chat", "chatId": "s-1"},
        {"text": "from s-1 but global", "sourceChatId": "s-1"},
    ]})
    ids = out["added"]
    gone = run(capsys, "memory_delete", {"chatIds": ["s-1"], "projectIds": ["p-1"]})
    assert sorted(m["text"] for m in gone["deleted"]) == ["chat", "proj"]
    assert [m["text"] for m in gone["memories"]] == ["global", "other proj", "from s-1 but global"]
    gone = run(capsys, "memory_delete", {"ids": [ids[0]]})
    assert [m["text"] for m in gone["deleted"]] == ["global"]
    for bad in ({"ids": ["x"]}, {"chatIds": ["a b"]}, {"projectIds": ["s-1"]}, {"ids": "m-0123456789abcdef"}):
        with pytest.raises(ValueError):
            memory.cmd_memory_delete(bad)


def test_bad_entries_in_the_file_are_dropped_on_read(data_home, capsys):
    os.makedirs(os.path.dirname(memory.memory_path()), exist_ok=True)
    with open(memory.memory_path(), "w", encoding="utf-8") as f:
        json.dump({"version": 1, "memories": [
            {"id": "m-0123456789abcdef", "text": "ok", "scope": "all"},
            {"id": "m-0123456789abcdef", "text": "dup id", "scope": "all"},
            {"id": "bad", "text": "x", "scope": "all"},
            {"id": "m-1123456789abcdef", "text": "x", "scope": "galaxy"},
            "junk",
        ]}, f)
    assert [m["text"] for m in run(capsys, "memory_list")["memories"]] == ["ok"]


def test_an_unreadable_file_is_never_overwritten(data_home, capsys):
    os.makedirs(os.path.dirname(memory.memory_path()), exist_ok=True)
    with open(memory.memory_path(), "w", encoding="utf-8") as f:
        f.write("{not json")
    with pytest.raises(ValueError):
        memory.cmd_memory_add({"items": [{"text": "x"}]})
    with open(memory.memory_path(), encoding="utf-8") as f:
        assert f.read() == "{not json"


def test_write_is_atomic(data_home, capsys):
    run(capsys, "memory_add", {"items": [{"text": "kept"}]})
    with patch("kdeaichat.common.os.replace", side_effect=OSError("disk full")):
        with pytest.raises(OSError):
            memory.cmd_memory_add({"items": [{"text": "lost"}]})
    assert [m["text"] for m in memory.load()] == ["kept"]
    folder = os.path.dirname(memory.memory_path())
    assert not [n for n in os.listdir(folder) if n.startswith(".memory.json.")]


def test_helper_dispatches_memory_commands(data_home):
    def helper(command, payload):
        encoded = base64.b64encode(json.dumps(payload).encode()).decode()
        return subprocess.run([sys.executable, os.path.join(UI_DIR, "kde_ai_helper.py"), command, encoded],
                              capture_output=True, text=True, timeout=30, env=dict(os.environ))

    result = helper("memory_add", {"items": [{"text": "über tea ☕", "scope": "all"}]})
    assert result.returncode == 0, result.stdout + result.stderr
    assert json.loads(result.stdout)["memories"][0]["text"] == "über tea ☕"
    result = helper("memory_add", {"items": [{"text": "x", "scope": "nope"}]})
    assert result.returncode == 1
