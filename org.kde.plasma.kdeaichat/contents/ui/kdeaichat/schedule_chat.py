"""A scheduled run's view of the chat store (store/ChatStore.qml), and its inbox.

Reading: the target chat is found by id in ``chats/applet-<N>/index.ini``
(metadata) and ``chat-<id>.ini`` (messages); ``projects.ini`` holds projects.

Writing, safely while the widget may have the chat open (one writer can't be
guaranteed, so two steps that together can't lose anything):
1. Under a per-folder lock, the run's messages are appended to the chat file
   (re-read just before, skipped if this run id is already there, written
   atomically in the widget's own INI format). With the widget closed, this
   is all that is needed.
2. Then the same messages go into ``inbox/run-<time>-<schedule>.ini``. The
   widget watches that folder (chat/ScheduleInbox.qml, a file-system watcher,
   no polling), merges the messages into the chat in memory by run id (so
   twice is harmless), saves, and only then removes the file with
   ``schedule_inbox_done``. If the widget wrote a stale copy of the chat over
   step 1, its own merge puts the messages back; if step 1 overwrote a
   message the widget had just saved, the merge rewrites the chat from memory.
"""
import fcntl
import json
import os
import re
import time
from contextlib import contextmanager
from typing import Any, Dict, Iterator, List, Optional

from kdeaichat import chats, qsettings_ini
from kdeaichat.common import atomic_write_text
from kdeaichat.schedule_model import CHAT_ID_RE

INBOX = "inbox"
_APPLET_DIR = re.compile(r"^applet-[A-Za-z0-9._-]{1,64}$")
_INBOX_FILE = re.compile(r"^(run|notice)-[0-9]{13}-[A-Za-z0-9-]{1,64}(-[0-9]+)?\.ini$")


def file_name_for_id(chat_id: str) -> str:
    """The chat file's name on disk.

    ChatStore.fileNameForId percent-encodes every character but [A-Za-z0-9._-],
    but Qt decodes that again when it turns the ``file://`` URL into a path,
    so the file on disk is plainly ``chat-<id>.ini`` (checked against Qt in
    tests/test_schedule_ini_qt.py). Ids are limited to the characters for
    which that holds (schedule_model.CHAT_ID_RE: no "/", "#" or "?").
    """
    if not CHAT_ID_RE.match(chat_id or "") or chat_id in (".", ".."):
        raise ValueError("invalid chat id")
    return "chat-" + chat_id + ".ini"


def _sessions(directory: str) -> List[Dict[str, Any]]:
    raw = qsettings_ini.read_value(os.path.join(directory, "index.ini"), "sessions", "")
    try:
        data = json.loads(raw) if raw else []
    except ValueError:
        return []
    return [s for s in data if isinstance(s, dict)] if isinstance(data, list) else []


def find_chat(chat_id: str) -> Optional[Dict[str, Any]]:
    """{directory, appletId, meta} of the chat with this id, or None."""
    root = chats.chats_root()
    try:
        folders = sorted(os.listdir(root))
    except OSError:
        return None
    for name in folders:
        directory = os.path.join(root, name)
        if not _APPLET_DIR.match(name) or not os.path.isdir(directory):
            continue
        for meta in _sessions(directory):
            if meta.get("value") == chat_id:
                return {"directory": directory, "appletId": name[len("applet-"):], "meta": meta}
    return None


def load_messages(ref: Dict[str, Any]) -> List[Dict[str, Any]]:
    path = os.path.join(ref["directory"], file_name_for_id(ref["meta"]["value"]))
    raw = qsettings_ini.read_value(path, "messages", "")
    if not raw:
        return []
    data = json.loads(raw)  # an unreadable chat file is an error, never overwritten
    if not isinstance(data, list):
        raise ValueError("the chat file holds no message list")
    return [m for m in data if isinstance(m, dict)]


def load_projects(directory: str) -> List[Dict[str, Any]]:
    raw = qsettings_ini.read_value(os.path.join(directory, "projects.ini"), "projects", "")
    try:
        data = json.loads(raw) if raw else []
    except ValueError:
        return []
    return [p for p in data if isinstance(p, dict)] if isinstance(data, list) else []


def inbox_dir(directory: str) -> str:
    return os.path.join(directory, INBOX)


@contextmanager
def folder_lock(directory: str) -> Iterator[None]:
    """Serialises scheduled runs writing into the same chat folder."""
    folder = inbox_dir(directory)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    fd = os.open(os.path.join(folder, ".lock"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _inbox_path(directory: str, kind: str, schedule_id: str) -> str:
    stamp = "%013d" % int(time.time() * 1000)
    base = os.path.join(inbox_dir(directory), f"{kind}-{stamp}-{schedule_id}")
    path, n = base + ".ini", 1
    while os.path.exists(path):
        n += 1
        path = f"{base}-{n}.ini"
    return path


def write_inbox(directory: str, kind: str, schedule_id: str, entry: Dict[str, Any]) -> str:
    """One inbox file (QtCore Settings INI, key ``entry`` = JSON). Returns its path."""
    path = _inbox_path(directory, kind, schedule_id)
    atomic_write_text(path, "[General]\nentry=" + qsettings_ini.escape(_json(entry)) + "\nversion=1\n", mode=0o600)
    return path


def deliver(ref: Dict[str, Any], run_id: str, messages: List[Dict[str, Any]], entry: Dict[str, Any]) -> str:
    """Append ``messages`` to the chat file, then leave them in the inbox (see above)."""
    directory = ref["directory"]
    chat_id = ref["meta"]["value"]
    with folder_lock(directory):
        current = load_messages(ref)
        if not any(m.get("scheduleRunId") == run_id for m in current):
            path = os.path.join(directory, file_name_for_id(chat_id))
            qsettings_ini.write_values(path, {"messages": _json(current + messages)})
        inbox = dict(entry, chatId=chat_id, runId=run_id, messages=messages)
        return write_inbox(directory, "run", entry.get("scheduleId", "x"), inbox)


def cmd_schedule_inbox_done(payload: Dict[str, Any]) -> None:
    """Remove inbox files the widget has merged and saved."""
    directory = os.path.join(chats._chat_dir(payload), INBOX)
    removed = []
    for name in payload.get("files", []):
        name = str(name)
        if not _INBOX_FILE.match(name):
            raise ValueError("invalid inbox file name: " + name)
        try:
            os.unlink(os.path.join(directory, name))
            removed.append(name)
        except FileNotFoundError:
            pass
    print(json.dumps({"removed": removed}))


COMMANDS = {"schedule_inbox_done": cmd_schedule_inbox_done}
