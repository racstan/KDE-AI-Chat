"""mcp.json (mcp_list / mcp_save / mcp_delete) and mcp_import from Claude Desktop and OpenCode configs."""
import contextlib
import io
import json
import os
import stat
import sys
import tempfile
from unittest.mock import patch

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui"))
from kdeaichat import mcp_config  # noqa: E402


def run(fn, payload=None):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        fn(payload or {})
    return json.loads(out.getvalue())


@pytest.fixture
def home():
    with tempfile.TemporaryDirectory() as tmp:
        with patch.dict(os.environ, {"XDG_DATA_HOME": os.path.join(tmp, "data"), "HOME": tmp}):
            yield tmp


def test_save_list_delete(home):
    assert run(mcp_config.cmd_mcp_list) == {"status": "ok", "servers": []}
    server = {"id": "files", "command": "npx", "args": ["-y", "srv", "/tmp"], "env": {"A": "1", "TOKEN": {"secret": "TOKEN", "value": "no"}}}
    assert run(mcp_config.cmd_mcp_save, {"server": server}) == {"status": "ok", "id": "files"}
    run(mcp_config.cmd_mcp_save, {"server": {"id": "web", "url": "https://x.example/mcp", "headers": {"Authorization": {"secret": "Authorization"}}}})
    path = mcp_config.config_path()
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
    assert "no" not in [v for v in json.load(open(path))["mcpServers"]["files"]["env"]["TOKEN"].values()]
    listed = run(mcp_config.cmd_mcp_list)["servers"]
    assert [s["id"] for s in listed] == ["files", "web"]
    assert listed[0]["env"] == {"A": "1", "TOKEN": {"secret": "TOKEN"}} and listed[0]["enabled"] is True
    assert run(mcp_config.cmd_mcp_delete, {"id": "files"})["status"] == "ok"
    assert [s["id"] for s in run(mcp_config.cmd_mcp_list)["servers"]] == ["web"]
    assert run(mcp_config.cmd_mcp_delete, {"id": "files"})["status"] == "error"


@pytest.mark.parametrize("server", [
    {"id": "Bad", "command": "x"}, {"id": "-x", "command": "x"}, {"id": "a" * 41, "command": "x"}, {"id": "ok\n", "command": "x"},
    {"id": "a"}, {"id": "a", "command": "x", "url": "https://x"}, {"id": "a", "url": "ftp://x"}, {"id": "a", "url": "http://"},
    {"id": "a", "command": "x\ny"}, {"id": "a", "command": "x", "args": "no"}, {"id": "a", "command": "x", "env": {"bad name": "1"}},
    {"id": "a", "command": "x", "env": {"A": {"secret": "bad name!"}}}, {"id": "a", "command": "x", "env": {"A": ["l"]}}, "text",
])
def test_save_rejects_invalid(home, server):
    assert run(mcp_config.cmd_mcp_save, {"server": server})["status"] == "error"
    assert not os.path.exists(mcp_config.config_path())


def test_import_claude_desktop_and_opencode(home):
    os.makedirs(os.path.join(home, ".config", "Claude"))
    with open(os.path.join(home, ".config", "Claude", "claude_desktop_config.json"), "w") as f:
        json.dump({"mcpServers": {"My Files": {"command": "npx", "args": ["-y", "fs", "/home"], "env": {"API_KEY": "abc", "MODE": "x"}},
                                  "remote": {"url": "https://r.example/mcp", "headers": {"Authorization": "Bearer t"}}}}, f)
    os.makedirs(os.path.join(home, ".config", "opencode"))
    with open(os.path.join(home, ".config", "opencode", "opencode.jsonc"), "w") as f:
        f.write('{\n // servers\n "mcp": {\n  "git": {"type": "local", "command": ["uvx", "mcp-git", "--x"], "enabled": false,\n'
                '    "environment": {"URL": "http://a//b"},},\n  "docs": {"type": "remote", "url": "https://d.example/mcp"},\n }, /* end */\n}\n')
    run(mcp_config.cmd_mcp_save, {"server": {"id": "git", "command": "x"}})
    out = run(mcp_config.cmd_mcp_import)
    by = {c["id"]: c for c in out["servers"]}
    assert set(by) == {"my-files", "remote", "git", "docs"}
    f = by["my-files"]
    assert (f["command"], f["args"], f["source"]) == ("npx", ["-y", "fs", "/home"], "Claude Desktop")
    assert f["env"]["MODE"] == "x" and f["env"]["API_KEY"] == {"secret": "API_KEY", "value": "abc"}
    assert by["remote"]["url"] == "https://r.example/mcp" and by["remote"]["headers"]["Authorization"]["secret"] == "Authorization"
    g = by["git"]
    assert (g["command"], g["args"], g["enabled"], g["source"], g["exists"]) == ("uvx", ["mcp-git", "--x"], False, "OpenCode", True)
    assert g["env"] == {"URL": "http://a//b"}
    assert by["docs"]["url"] == "https://d.example/mcp" and by["docs"]["exists"] is False
    assert not any("problem" in c for c in out["servers"])
    assert [s["id"] for s in run(mcp_config.cmd_mcp_list)["servers"]] == ["git"]  # nothing saved by importing


def test_import_with_no_configs(home):
    assert run(mcp_config.cmd_mcp_import) == {"status": "ok", "servers": []}
