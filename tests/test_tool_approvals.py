"""Remembered tool approvals (kdeaichat/tool_approvals.py)."""
import json
import os
import stat
import sys
import tempfile
from unittest.mock import patch

import pytest

UI_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI_DIR)

from kdeaichat import tool_approvals  # noqa: E402


@pytest.fixture
def data_home():
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        yield data


def run(capsys, command, payload=None):
    tool_approvals.COMMANDS[command](payload or {})
    return json.loads(capsys.readouterr().out)


def test_empty_list_creates_nothing(data_home, capsys):
    assert run(capsys, "tool_approvals_list") == {"keys": []}
    assert not os.path.exists(tool_approvals.approvals_path())


def test_add_list_remove_and_private_file(data_home, capsys):
    key = "mcp:files:read_text"
    assert run(capsys, "tool_approvals_add", {"key": key}) == {"keys": [key]}
    assert run(capsys, "tool_approvals_add", {"key": key}) == {"keys": [key]}, "adding twice is harmless"
    other = "workspace:/home/me/my project:write_file"
    assert run(capsys, "tool_approvals_add", {"key": other})["keys"] == [key, other]
    path = tool_approvals.approvals_path()
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode) == 0o700
    assert run(capsys, "tool_approvals_list") == {"keys": [key, other]}
    assert run(capsys, "tool_approvals_remove", {"key": key}) == {"keys": [other]}
    assert json.load(open(path)) == {"version": 1, "keys": [other]}


@pytest.mark.parametrize("key", ["", None, 5, "mcp:", "mcp:server", "mcp::tool", "mcp:a:", "mcp:a:b\nc", "mcp:a:b\x00",
                                 "other:a:b", "workspace:nocolon", "workspace::tool", "mcp:" + "s" * 201 + ":t"])
def test_bad_keys_are_refused(data_home, capsys, key):
    with pytest.raises(ValueError):
        tool_approvals.COMMANDS["tool_approvals_add"]({"key": key})
    with pytest.raises(ValueError):
        tool_approvals.COMMANDS["tool_approvals_remove"]({"key": key})
    assert not os.path.exists(tool_approvals.approvals_path())


def test_a_damaged_file_reads_as_empty_and_bad_entries_are_dropped(data_home, capsys):
    path = tool_approvals.approvals_path()
    os.makedirs(os.path.dirname(path))
    with open(path, "w") as f:
        f.write("{not json")
    assert run(capsys, "tool_approvals_list") == {"keys": []}
    with open(path, "w") as f:
        json.dump({"version": 1, "keys": ["mcp:a:b", "junk", 7, "mcp:a:b", "skill:notes"]}, f)
    assert run(capsys, "tool_approvals_list") == {"keys": ["mcp:a:b", "skill:notes"]}
    assert run(capsys, "tool_approvals_add", {"key": "mcp:c:d"})["keys"] == ["mcp:a:b", "skill:notes", "mcp:c:d"]


def test_registered_with_the_helper():
    import kde_ai_helper  # noqa: F401
    from kdeaichat import tool_approvals as module
    assert set(module.COMMANDS) == {"tool_approvals_list", "tool_approvals_add", "tool_approvals_remove"}
    source = open(os.path.join(UI_DIR, "kde_ai_helper.py")).read()
    assert "tool_approvals" in source.split("for module in")[1]
