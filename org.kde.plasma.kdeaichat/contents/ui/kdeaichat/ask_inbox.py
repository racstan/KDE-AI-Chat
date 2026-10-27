"""The ask inbox: how other parts of the desktop hand a question to the widget.

KRunner, the Dolphin menu and the ``kdeaichat-ask`` command (scripts/) write one JSON file per request into
``$XDG_RUNTIME_DIR/kdeaichat-ask/`` (a 0700 folder; files are 0600): ``{"text", "files", "newChat", "send"}``.
The runtime folder is private to the user and gone at logout, so the question never sits on the command line
(where every local user could read it) or in a long-lived file. The widget watches the folder (no polling,
chat/AskInbox.qml) and calls ``ask_inbox_take``, which claims every file by renaming it (so with two widgets
only one gets a request), reads it, deletes it and returns the requests. Requests nobody took within a day
are dropped.

  ask_inbox_take  {} -> {"type": "ask_items", "directory", "items": [{text, files, newChat, send, notes}]}

Attached files are checked when the widget takes a request (any program of the user can write one): only
regular readable files under the home folder, with no dot-folder in the path (.ssh, .gnupg, ...), after
resolving symlinks. Others are dropped and named in ``notes`` (the widget shows them). A request with files
never sends by itself: the files are attached and the user presses Enter.

``KDEAICHAT_ASK_DIR`` replaces the folder (tests, dev runs).
"""
import json
import os
import secrets
import stat
import time
from typing import Any, Dict, List, Optional, Tuple

from kdeaichat import private_payload

MAX_TEXT = 200000
MAX_FILES = 10
MAX_AGE = 24 * 3600
MAX_BYTES = 4 * 1024 * 1024
PREFIX = "ask-"


def inbox_dir() -> str:
    return os.environ.get("KDEAICHAT_ASK_DIR") or os.path.join(private_payload.runtime_dir(), "kdeaichat-ask")


def ensure_dir(directory: Optional[str] = None) -> str:
    """The inbox folder, created 0700. Refuses a folder that isn't ours or that others can open."""
    directory = directory or inbox_dir()
    os.makedirs(directory, mode=0o700, exist_ok=True)
    info = os.lstat(directory)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError("the inbox folder is not ours")
    if stat.S_IMODE(info.st_mode) & 0o077:
        os.chmod(directory, 0o700)
    return directory


def clean(raw: Any) -> Optional[Dict[str, Any]]:
    """A request as the widget should see it, or None when it is not one."""
    if not isinstance(raw, dict):
        return None
    text = raw.get("text", "")
    text = text if isinstance(text, str) else ""
    files = [f for f in (raw.get("files") or []) if isinstance(f, str) and os.path.isabs(f) and "\0" not in f]
    item = {"text": text[:MAX_TEXT], "files": files[:MAX_FILES], "newChat": raw.get("newChat") is True,
            "send": raw.get("send") is True}
    return item if item["text"].strip() or item["files"] else None


# Besides the home folder, files may come from removable and mounted drives.
MOUNT_ROOTS = ("/media", "/run/media", "/mnt")


def _inside(real: str, root: str) -> Optional[str]:
    """`real` relative to `root`, or None when it is not below it."""
    rel = os.path.relpath(real, root)
    return None if rel == os.curdir or rel == os.pardir or rel.startswith(os.pardir + os.sep) else rel


def check_files(files: List[str]) -> Tuple[List[str], List[Dict[str, str]]]:
    """(files to attach, notes {reason: outside|hidden|unreadable, name} about the refused ones). Real readable
    files under home or a mounted drive (MOUNT_ROOTS), with no dot-folder in the path."""
    roots = [os.path.realpath(os.path.expanduser("~"))] + [os.path.realpath(r) for r in MOUNT_ROOTS]
    kept: List[str] = []
    notes: List[Dict[str, str]] = []
    for path in files:
        real = os.path.realpath(path)
        name = os.path.basename(path) or path
        rel = next((r for r in (_inside(real, root) for root in roots) if r is not None), None)
        if rel is None:
            notes.append({"reason": "outside", "name": name})
        elif any(part.startswith(".") for part in rel.split(os.sep)):
            notes.append({"reason": "hidden", "name": name})
        elif not os.path.isfile(real) or not os.access(real, os.R_OK):
            notes.append({"reason": "unreadable", "name": name})
        else:
            kept.append(real)
    return kept, notes


def write_item(text: str = "", files: Optional[List[str]] = None, new_chat: bool = False, send: bool = False,
               directory: Optional[str] = None) -> str:
    """Leaves one request for the widget; returns the file name. Raises ValueError for an empty or bad request."""
    if len(text) > MAX_TEXT:
        raise ValueError("the text is too long (at most %d characters)" % MAX_TEXT)
    if len(files or []) > MAX_FILES:
        raise ValueError("at most %d files at a time" % MAX_FILES)
    item = clean({"text": text, "files": files or [], "newChat": new_chat, "send": send})
    if item is None:
        raise ValueError("nothing to send: give a question or at least one file")
    directory = ensure_dir(directory)
    name = "%s%d-%s.json" % (PREFIX, time.time_ns(), secrets.token_hex(4))
    tmp = os.path.join(directory, ".tmp-" + secrets.token_hex(6))
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(item, f)
        os.rename(tmp, os.path.join(directory, name))  # complete or absent: the widget ignores ".tmp-*"
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return name


def take_all(directory: Optional[str] = None) -> List[Dict[str, Any]]:
    """Claims, reads and deletes every waiting request, oldest first."""
    directory = ensure_dir(directory)
    items: List[Dict[str, Any]] = []
    for name in sorted(os.listdir(directory)):
        if not (name.startswith(PREFIX) and name.endswith(".json")):
            continue
        path = os.path.join(directory, name)
        claimed = os.path.join(directory, ".taking-" + secrets.token_hex(6))
        try:
            os.rename(path, claimed)  # atomic: only one taker wins
        except OSError:
            continue
        try:
            info = os.lstat(claimed)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > MAX_BYTES:
                continue
            if time.time() - info.st_mtime > MAX_AGE:
                continue
            with open(claimed, encoding="utf-8") as f:
                item = clean(json.load(f))
            if item is not None:
                asked = bool(item["files"])
                item["files"], item["notes"] = check_files(item["files"])
                if asked:
                    item["send"] = False  # files are never sent without the user pressing Enter
                items.append(item)
        except (OSError, ValueError):
            pass
        finally:
            try:
                os.unlink(claimed)
            except OSError:
                pass
    return items


def cmd_ask_inbox_take(payload: Dict[str, Any]) -> None:
    directory = ensure_dir()
    print(json.dumps({"type": "ask_items", "directory": directory, "items": take_all(directory)}), flush=True)


COMMANDS = {"ask_inbox_take": cmd_ask_inbox_take}
