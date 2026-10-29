"""Filesystem side of the chat store (store/ChatStore.qml).

QML writes chat files itself; it can't set permissions or delete files, so
these commands do that. Paths are confined to the chats folder (and, for an
incognito chat's Pi files, to Pi's folders under ~/.local/share/kdeaichat).
"""
import json
import os
import re
import shutil
from typing import Any, Dict

_FILE_NAME = re.compile(r"^chat-[A-Za-z0-9._%-]{1,400}\.ini\Z")
# A file kept as evidence when it cannot be read: only the index, its backup or a chat file.
_DAMAGEABLE = re.compile(r"^(index\.ini|index\.ini\.bak|chat-[A-Za-z0-9._%-]{1,400}\.ini)\Z")
_STAMP = re.compile(r"^\d{8}-\d{6}\Z")
# chat/Incognito.qml: an incognito chat's id. Such a chat is never stored.
_INCOGNITO = re.compile(r"^s-incognito-[A-Za-z0-9._-]{1,100}\Z")


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
    if os.path.dirname(directory) != root or not re.match(r"^applet-[A-Za-z0-9._-]{1,64}\Z", os.path.basename(directory)):
        raise ValueError("chat directory must be chats/applet-<id>")
    return directory


def chat_folder_name(chat_id: str) -> str:
    """A chat id as a folder name (images/<chat>, attachments/<chat>): characters outside [A-Za-z0-9._-] become "_"."""
    name = re.sub(r"[^A-Za-z0-9._-]", "_", str(chat_id or ""))[:128].strip(".")
    if not name:
        raise ValueError("chat is required")
    return name


def cmd_prepare_chat_dir(payload: Dict[str, Any]) -> None:
    """Create the chat folder and its inbox private (0700) and tighten existing files to 0600."""
    directory = _chat_dir(payload)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    os.makedirs(os.path.join(directory, "inbox"), mode=0o700, exist_ok=True)  # scheduled runs (schedule_chat.py)
    for path in (os.path.dirname(directory), directory, os.path.join(directory, "inbox")):
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


def cmd_keep_damaged_file(payload: Dict[str, Any]) -> None:
    """Copy an unreadable index.ini / chat-<id>.ini to <name>.damaged-<stamp> (stamp
    YYYYMMDD-HHMMSS) so a repair is possible by hand. The original is never touched
    and an existing copy is never replaced."""
    directory = _chat_dir(payload)
    name, stamp = str(payload.get("file", "")), str(payload.get("stamp", ""))
    if not _DAMAGEABLE.match(name) or not _STAMP.match(stamp):
        raise ValueError("invalid file name or stamp")
    source = os.path.join(directory, name)
    target = source + ".damaged-" + stamp
    if os.path.islink(source) or not os.path.isfile(source) or os.path.lexists(target):
        print(json.dumps({"copied": False}))
        return
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with open(source, "rb") as src, os.fdopen(fd, "wb") as dst:
        shutil.copyfileobj(src, dst)
    print(json.dumps({"copied": True, "file": os.path.basename(target)}))


def cmd_list_chat_files(payload: Dict[str, Any]) -> None:
    """Names of the chat-<id>.ini files in the chats folder (to rebuild a lost index)."""
    directory = _chat_dir(payload)
    names = [name for name, path in _real_entries(directory) if _FILE_NAME.match(name) and os.path.isfile(path)]
    print(json.dumps({"files": names}))


def _real_entries(folder: str):
    """(name, path) of the entries of `folder` that are not symlinks; none if it is missing or a link."""
    if os.path.islink(folder) or not os.path.isdir(folder):
        return []
    return [(name, os.path.join(folder, name)) for name in sorted(os.listdir(folder))
            if not os.path.islink(os.path.join(folder, name))]


def cmd_incognito_cleanup(payload: Dict[str, Any]) -> None:
    """Remove what incognito chats leave behind while they are open: their image
    folders (images/s-incognito-*), the file of instructions Pi was started with
    and Pi's working folder when it is empty (files Pi made there stay). With
    ``chat``, only that chat's (it was closed); without, every incognito chat's
    (at start, after a session that ended with one open)."""
    directory = _chat_dir(payload)
    chat = str(payload.get("chat") or "")
    if chat and not _INCOGNITO.match(chat):
        raise ValueError("not an incognito chat: " + chat)

    def wanted(name: str) -> bool:
        return bool(_INCOGNITO.match(name)) and (not chat or name == chat)

    removed = []
    for name, path in _real_entries(os.path.join(directory, "images")):
        if wanted(name) and os.path.isdir(path):
            shutil.rmtree(path, ignore_errors=True)
            removed.append("images/" + name)
    # Never written by the widget (store/ChatStore.qml skips incognito chats); removed if found all the same.
    for name, path in _real_entries(directory):
        if name.startswith("chat-") and name.endswith(".ini") and wanted(name[5:-4]) and os.path.isfile(path):
            os.unlink(path)
            removed.append(name)
    for name, path in _real_entries(os.path.join(data_root(), "pi-instructions")):
        if name.endswith(".md") and wanted(name[:-3]) and os.path.isfile(path):
            os.unlink(path)
            removed.append("pi-instructions/" + name)
    for name, path in _real_entries(os.path.join(data_root(), "pi-workspaces")):
        if wanted(name) and os.path.isdir(path) and not os.listdir(path):
            os.rmdir(path)
            removed.append("pi-workspaces/" + name)
    print(json.dumps({"removed": removed}))


COMMANDS = {
    "prepare_chat_dir": cmd_prepare_chat_dir,
    "delete_chat_files": cmd_delete_chat_files,
    "incognito_cleanup": cmd_incognito_cleanup,
    "keep_damaged_file": cmd_keep_damaged_file,
    "list_chat_files": cmd_list_chat_files,
}
