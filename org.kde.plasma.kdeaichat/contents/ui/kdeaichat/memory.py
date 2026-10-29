"""Memories: short notes the user wants every chat (or one project or chat) to know.

They live in one private file, shared by every widget instance:

    ~/.local/share/kdeaichat/memory.json   (0600, folder 0700)
    {"version": 1, "memories": [memory, ...]}

A memory is
    {id, text, scope, projectId, chatId, pinned, enabled, created, sourceChatId}
  id            "m-" + 16 hex characters, made here
  scope         "all" (every chat), "project" (projectId's chats) or "chat" (chatId)
  projectId     the project's id for scope "project", else ""
  chatId        the chat's id for scope "chat", else ""
  created       milliseconds since the epoch
  sourceChatId  the chat it came from ("" = typed in, or not known)

The widget (store/MemoryStore.qml) keeps the list in memory; every command
answers with the whole list after the change, so the widget never has to
merge. Writes are atomic and serialised with a lock, since several widgets
may write at once.

Commands (payload is JSON):
  memory_list    {}                                   -> {memories}
  memory_add     {items: [{text, scope, projectId?, chatId?, pinned?, enabled?,
                           sourceChatId?, id?, created?}]}
                 -> {added: [ids], existing: [ids], memories}
                 An item whose text, scope, project and chat match a stored
                 memory is not added again (its id is in `existing`), so
                 adding twice is harmless. `id`/`created` bring a removed
                 memory back as it was (Undo).
  memory_update  {id, text?, pinned?, enabled?, scope?, projectId?, chatId?}
                 -> {memory, memories}
  memory_delete  {ids?: [...], chatIds?: [...], projectIds?: [...]}
                 removes those memories and every memory scoped to those
                 chats or projects -> {deleted: [memories], memories}
"""
import fcntl
import json
import os
import re
import secrets
import time
from contextlib import contextmanager
from typing import Any, Dict, List, Optional

from kdeaichat import chats, common
from kdeaichat.common import as_bool, atomic_write_json

MAX_TEXT = 4000
MAX_MEMORIES = 1000
MAX_ITEMS_PER_CALL = 100
MAX_IDS_PER_CALL = 1000
MAX_STORE_BYTES = 16 * 1024 * 1024
SCOPES = ("all", "project", "chat")

_MEMORY_ID = re.compile(r"^m-[0-9a-f]{16}\Z")
_PROJECT_ID = re.compile(r"^p-[A-Za-z0-9_-]{1,64}\Z")
_CHAT_ID = re.compile(r"^[A-Za-z0-9._:-]{1,128}\Z")


def memory_path() -> str:
    return os.path.join(chats.data_root(), "memory.json")


def _private_folder() -> str:
    folder = os.path.dirname(memory_path())
    common.ensure_private_dir(folder)
    os.chmod(folder, 0o700)
    return folder


@contextmanager
def _locked():
    _private_folder()
    fd = os.open(memory_path() + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def clean_text(value: Any) -> str:
    if not isinstance(value, str):
        raise ValueError("text must be a string")
    text = value.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not text:
        raise ValueError("text is empty")
    if len(text) > MAX_TEXT:
        raise ValueError("text is longer than %d characters" % MAX_TEXT)
    if "\x00" in text:
        raise ValueError("text contains a NUL character")
    return text


def _id(value: Any, pattern: "re.Pattern[str]", what: str, allow_empty: bool = False) -> str:
    text = "" if value is None else str(value)
    if text == "" and allow_empty:
        return ""
    if not pattern.match(text):
        raise ValueError("invalid " + what)
    return text


def _scope_fields(raw: Dict[str, Any]) -> Dict[str, str]:
    """scope, projectId and chatId, consistent with each other."""
    scope = str(raw.get("scope", "all"))
    if scope not in SCOPES:
        raise ValueError("scope must be one of " + ", ".join(SCOPES))
    project_id = _id(raw.get("projectId"), _PROJECT_ID, "project id") if scope == "project" else ""
    chat_id = _id(raw.get("chatId"), _CHAT_ID, "chat id") if scope == "chat" else ""
    return {"scope": scope, "projectId": project_id, "chatId": chat_id}


def _created(value: Any) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        number = 0
    return number if 0 < number < 10 ** 14 else int(time.time() * 1000)


def normalize(raw: Any) -> Optional[Dict[str, Any]]:
    """A stored memory with every field valid, or None to drop it."""
    if not isinstance(raw, dict):
        return None
    try:
        memory = {"id": _id(raw.get("id"), _MEMORY_ID, "memory id"), "text": clean_text(raw.get("text"))}
        memory.update(_scope_fields(raw))
        memory["pinned"] = as_bool(raw.get("pinned"), False)
        memory["enabled"] = as_bool(raw.get("enabled"), True)
        memory["created"] = _created(raw.get("created"))
        memory["sourceChatId"] = _id(raw.get("sourceChatId"), _CHAT_ID, "chat id", allow_empty=True)
    except ValueError:
        return None
    return memory


def load() -> List[Dict[str, Any]]:
    """The stored memories. A file that can't be read raises, so it is never overwritten."""
    path = memory_path()
    if not os.path.exists(path):
        return []
    if os.path.getsize(path) > MAX_STORE_BYTES:
        raise ValueError("memory store is too large")
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    items = data.get("memories") if isinstance(data, dict) else None
    if not isinstance(items, list):
        raise ValueError("memory store is not in the expected format")
    out, seen = [], set()
    for raw in items:
        memory = normalize(raw)
        if memory and memory["id"] not in seen:
            seen.add(memory["id"])
            out.append(memory)
    return out


def _save(memories: List[Dict[str, Any]]) -> None:
    _private_folder()
    atomic_write_json(memory_path(), {"version": 1, "memories": memories})


def _key(memory: Dict[str, Any]) -> tuple:
    return (" ".join(memory["text"].split()).casefold(), memory["scope"], memory["projectId"], memory["chatId"])


def _new_id(taken: set) -> str:
    while True:
        candidate = "m-" + secrets.token_hex(8)
        if candidate not in taken:
            return candidate


def _list_of(payload: Dict[str, Any], name: str, limit: int) -> List[Any]:
    value = payload.get(name) or []
    if not isinstance(value, list):
        raise ValueError(name + " must be a list")
    if len(value) > limit:
        raise ValueError("too many " + name)
    return value


def _print(result: Dict[str, Any]) -> None:
    print(json.dumps(result, ensure_ascii=False))


def cmd_memory_list(payload: Dict[str, Any]) -> None:
    _print({"memories": load()})


def cmd_memory_add(payload: Dict[str, Any]) -> None:
    items = _list_of(payload, "items", MAX_ITEMS_PER_CALL)
    with _locked():
        memories = load()
        taken = {m["id"] for m in memories}
        by_key = {_key(m): m["id"] for m in memories}
        added, existing = [], []
        skip_invalid = payload.get("skipInvalid") is True
        skipped = 0
        for raw in items:
            try:
                if not isinstance(raw, dict):
                    raise ValueError("each item must be an object")
                memory = {"text": clean_text(raw.get("text"))}
                memory.update(_scope_fields(raw))
                memory["pinned"] = as_bool(raw.get("pinned"), False)
                memory["enabled"] = as_bool(raw.get("enabled"), True)
                memory["created"] = _created(raw.get("created"))
                memory["sourceChatId"] = _id(raw.get("sourceChatId"), _CHAT_ID, "chat id", allow_empty=True)
            except ValueError:
                if not skip_invalid:
                    raise
                skipped += 1
                continue
            key = _key(memory)
            if key in by_key:
                existing.append(by_key[key])
                continue
            wanted = str(raw.get("id") or "")
            memory_id = wanted if _MEMORY_ID.match(wanted) and wanted not in taken else _new_id(taken)
            if len(memories) >= MAX_MEMORIES:
                raise ValueError("there are already %d memories" % MAX_MEMORIES)
            memory = dict({"id": memory_id}, **memory)
            memories.append(memory)
            taken.add(memory_id)
            by_key[key] = memory_id
            added.append(memory_id)
        if added:
            _save(memories)
    result = {"added": added, "existing": existing, "memories": memories}
    if skip_invalid:
        result["skipped"] = skipped
    _print(result)


def cmd_memory_update(payload: Dict[str, Any]) -> None:
    memory_id = _id(payload.get("id"), _MEMORY_ID, "memory id")
    with _locked():
        memories = load()
        target = next((m for m in memories if m["id"] == memory_id), None)
        if target is None:
            raise ValueError("no such memory")
        changed = dict(target)
        if "text" in payload:
            changed["text"] = clean_text(payload.get("text"))
        if "scope" in payload:
            changed.update(_scope_fields(payload))
        for flag in ("pinned", "enabled"):
            if flag in payload:
                changed[flag] = as_bool(payload.get(flag), bool(target[flag]))
        if _key(changed) != _key(target) and any(_key(m) == _key(changed) for m in memories if m is not target):
            raise ValueError("the same memory already exists")
        memories[memories.index(target)] = changed
        _save(memories)
    _print({"memory": changed, "memories": memories})


def cmd_memory_delete(payload: Dict[str, Any]) -> None:
    ids = {_id(v, _MEMORY_ID, "memory id") for v in _list_of(payload, "ids", MAX_IDS_PER_CALL)}
    chat_ids = {_id(v, _CHAT_ID, "chat id") for v in _list_of(payload, "chatIds", MAX_IDS_PER_CALL)}
    project_ids = {_id(v, _PROJECT_ID, "project id") for v in _list_of(payload, "projectIds", MAX_IDS_PER_CALL)}

    def doomed(m: Dict[str, Any]) -> bool:
        return (m["id"] in ids or (m["scope"] == "chat" and m["chatId"] in chat_ids)
                or (m["scope"] == "project" and m["projectId"] in project_ids))

    with _locked():
        memories = load()
        deleted = [m for m in memories if doomed(m)]
        if deleted:
            memories = [m for m in memories if not doomed(m)]
            _save(memories)
    _print({"deleted": deleted, "memories": memories})


COMMANDS = {
    "memory_list": cmd_memory_list,
    "memory_add": cmd_memory_add,
    "memory_update": cmd_memory_update,
    "memory_delete": cmd_memory_delete,
}
