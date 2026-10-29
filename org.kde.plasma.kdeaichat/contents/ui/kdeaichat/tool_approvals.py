"""Remembered tool approvals for direct chats ("Always allow" on a permission card).

One private file shared by every widget instance:

    ~/.local/share/kdeaichat/tool-approvals.json   (0600, folder 0700)
    {"version": 1, "keys": [key, ...]}

A key says which tool may run without asking:
    mcp:<server>:<tool>              an MCP server's tool
    workspace:<folder>:<tool>        an agent tool in one chat folder
    skill:<name>                     reserved for skill tools

The widget (chat/DirectToolRunner.qml) never remembers anything for an incognito chat: it
simply does not call tool_approvals_add. Writes are atomic and serialised with a lock.

Commands (payload is JSON; every answer is the whole list after the change):
  tool_approvals_list    {}          -> {keys}
  tool_approvals_add     {key}       -> {keys}
  tool_approvals_remove  {key}       -> {keys}
"""
import fcntl
import json
import os
import re
from contextlib import contextmanager
from typing import Any, Dict, List

from kdeaichat import chats, common

MAX_KEYS = 2000
MAX_STORE_BYTES = 4 * 1024 * 1024

_NO_CONTROL = r"[^\x00-\x1f\x7f]"
_KEY_PATTERNS = (
    re.compile(r"^mcp:[^:\x00-\x1f\x7f]{1,200}:" + _NO_CONTROL + r"{1,200}\Z"),
    re.compile(r"^workspace:" + _NO_CONTROL + r"{1,1000}:[^:\x00-\x1f\x7f]{1,200}\Z"),
    re.compile(r"^skill:" + _NO_CONTROL + r"{1,200}\Z"),
)


def approvals_path() -> str:
    return os.path.join(chats.data_root(), "tool-approvals.json")


@contextmanager
def _locked():
    folder = os.path.dirname(approvals_path())
    common.ensure_private_dir(folder)
    os.chmod(folder, 0o700)
    fd = os.open(approvals_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def valid_key(value: Any) -> bool:
    return isinstance(value, str) and any(p.match(value) for p in _KEY_PATTERNS)


def _clean_key(value: Any) -> str:
    if not valid_key(value):
        raise ValueError("invalid approval key")
    return str(value)


def load() -> List[str]:
    """The stored keys; a missing, damaged or oversized file reads as empty. Bad entries are dropped."""
    try:
        if os.path.getsize(approvals_path()) > MAX_STORE_BYTES:
            return []
        with open(approvals_path(), "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return []
    keys = data.get("keys") if isinstance(data, dict) else None
    out: List[str] = []
    for key in keys if isinstance(keys, list) else []:
        if valid_key(key) and key not in out:
            out.append(key)
    return out[:MAX_KEYS]


def _save(keys: List[str]) -> None:
    common.atomic_write_json(approvals_path(), {"version": 1, "keys": keys})


def _print(keys: List[str]) -> None:
    print(json.dumps({"keys": keys}, ensure_ascii=False))


def cmd_tool_approvals_list(payload: Dict[str, Any]) -> None:
    _print(load())


def cmd_tool_approvals_add(payload: Dict[str, Any]) -> None:
    key = _clean_key(payload.get("key"))
    with _locked():
        keys = load()
        if key not in keys:
            if len(keys) >= MAX_KEYS:
                raise ValueError("too many remembered approvals")
            keys.append(key)
            _save(keys)
    _print(keys)


def cmd_tool_approvals_remove(payload: Dict[str, Any]) -> None:
    key = _clean_key(payload.get("key"))
    with _locked():
        keys = load()
        if key in keys:
            keys.remove(key)
            _save(keys)
    _print(keys)


COMMANDS = {
    "tool_approvals_list": cmd_tool_approvals_list,
    "tool_approvals_add": cmd_tool_approvals_add,
    "tool_approvals_remove": cmd_tool_approvals_remove,
}
