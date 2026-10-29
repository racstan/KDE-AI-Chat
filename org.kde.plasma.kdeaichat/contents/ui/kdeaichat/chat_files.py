"""Writing chats into a chat folder from outside the widget (backup restore, imports of other apps' chats).

Same file format as store/ChatStore.qml and schedule_chat.py: ``index.ini`` (and
its backup ``index.ini.bak``) hold ``sessions`` = JSON list of chat metadata,
``chat-<id>.ini`` holds ``messages`` = JSON list. Callers hold ``locked()``
while they add chats, so two writers can't interleave. A chat that is already
there is never touched. The widget picks new chats up by reloading the list
(chat/HistoryRecovery.qml, when the settings page asks for it).
"""
import json
import os
import re
from contextlib import contextmanager
from typing import Any, Dict, Iterator, List, Set

from kdeaichat import chats, common, qsettings_ini, schedule_chat

CHAT_ID = re.compile(r"^[A-Za-z0-9._:-]{1,128}\Z")  # Security.js validateSessionId
INCOGNITO = re.compile(r"^s-incognito-")


def folder(payload: Dict[str, Any]) -> str:
    """The applet's chat folder from the payload (must be chats/applet-<id>), created private if missing."""
    directory = chats._chat_dir(payload)
    common.ensure_private_dir(os.path.dirname(directory))
    common.ensure_private_dir(directory)
    return directory


@contextmanager
def locked(directory: str) -> Iterator[None]:
    with schedule_chat.folder_lock(directory):
        yield


def valid_id(chat_id: Any) -> bool:
    return isinstance(chat_id, str) and bool(CHAT_ID.match(chat_id)) and chat_id not in (".", "..") \
        and not INCOGNITO.match(chat_id)


def sessions(directory: str) -> List[Dict[str, Any]]:
    """The index's chats. An index that exists but can't be read raises: it is never replaced."""
    path = os.path.join(directory, "index.ini")
    raw = qsettings_ini.read_value(path, "sessions", "")
    if raw:
        try:
            data = json.loads(raw)
        except ValueError:
            raise ValueError("the chat list is damaged; open the widget to repair it first") from None
        if not isinstance(data, list):
            raise ValueError("the chat list is damaged; open the widget to repair it first")
    return schedule_chat._sessions(directory)


def known_ids(directory: str) -> Set[str]:
    """Ids of the chats in the index plus those that only have a chat file."""
    ids = {str(s.get("value")) for s in sessions(directory)}
    try:
        for name in os.listdir(directory):
            if name.startswith("chat-") and name.endswith(".ini"):
                ids.add(name[5:-4])
    except OSError:
        pass
    return ids


def write_messages(directory: str, chat_id: str, messages: List[Dict[str, Any]]) -> None:
    path = os.path.join(directory, schedule_chat.file_name_for_id(chat_id))
    qsettings_ini.write_values(path, {"messages": json.dumps(messages, ensure_ascii=False, separators=(",", ":"))})


def add_to_index(directory: str, new_metas: List[Dict[str, Any]]) -> None:
    """Append chat metadata (caller holds the lock and has written the chat files first)."""
    if not new_metas:
        return
    value = {"version": "1",
             "sessions": json.dumps(sessions(directory) + new_metas, ensure_ascii=False, separators=(",", ":"))}
    for name in ("index.ini", "index.ini.bak"):
        qsettings_ini.write_values(os.path.join(directory, name), value)
