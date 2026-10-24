"""Filesystem side of the chat store (store/ChatStore.qml).

QML writes chat files itself; it can't set permissions or delete files, so
these two commands do that. Paths are confined to the chats folder.
"""
import json
import os
import re
from typing import Any, Dict

_FILE_NAME = re.compile(r"^chat-[A-Za-z0-9._%-]{1,400}\.ini$")


def data_root() -> str:
    """~/.local/share/kdeaichat, honouring XDG_DATA_HOME like the QML side."""
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(data, "kdeaichat")


def chats_root() -> str:
    return os.path.join(data_root(), "chats")


def _chat_dir(payload: Dict[str, Any]) -> str:
    """The requested folder, which must be a direct child of chats_root()."""
    root = os.path.realpath(chats_root())
    directory = os.path.realpath(str(payload.get("directory", "")))
    if os.path.dirname(directory) != root or not re.match(r"^applet-[A-Za-z0-9._-]{1,64}$", os.path.basename(directory)):
        raise ValueError("chat directory must be chats/applet-<id>")
    return directory


def cmd_prepare_chat_dir(payload: Dict[str, Any]) -> None:
    """Create the chat folder private (0700) and tighten existing files to 0600."""
    directory = _chat_dir(payload)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    for path in (os.path.dirname(directory), directory):
        os.chmod(path, 0o700)
    for name in os.listdir(directory):
        path = os.path.join(directory, name)
        if os.path.isfile(path) and not os.path.islink(path):
            os.chmod(path, 0o600)
    print(json.dumps({"status": "ok"}))


def cmd_delete_chat_files(payload: Dict[str, Any]) -> None:
    """Delete chat-<id>.ini files of removed chats."""
    directory = _chat_dir(payload)
    deleted = []
    for name in payload.get("files", []):
        name = str(name)
        if not _FILE_NAME.match(name):
            raise ValueError("invalid chat file name: " + name)
        try:
            os.unlink(os.path.join(directory, name))
            deleted.append(name)
        except FileNotFoundError:
            pass
    print(json.dumps({"deleted": deleted}))


COMMANDS = {
    "prepare_chat_dir": cmd_prepare_chat_dir,
    "delete_chat_files": cmd_delete_chat_files,
}
