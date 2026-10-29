"""Files attached to messages: kept once as files, not inside the chat file.

    chats/applet-<id>/attachments/<chatId>/<sha256>.<ext>      (files 0600, folders 0700)

The chat file keeps only a reference ({name, type, mimeType, size, file, hash});
the bytes live here, content-addressed by their SHA-256, so the same file attached
twice in a chat is stored once. Writes are atomic and read back (hash checked)
before the widget drops the inline copy from the chat file.

Commands (payload is JSON, passed through a private payload file; ``directory`` is chats/applet-<id>):
  attachment_store   {directory, chat, items: [{kind: "base64"|"text", content, mime?}]}
                     -> {"items": [{"ok", "hash", "file", "bytes"} | {"ok": false, "error"}]}
  attachment_read    {directory, items: [{file, kind: "base64"|"text"}]}
                     -> {"items": [{"file", "ok", "content"} | {"file", "ok": false, "error"}]}
  attachment_delete  {directory, chats: [id, ...]}   the attachment folders of removed chats
"""
import base64
import hashlib
import json
import os
import re
import shutil
import tempfile
from typing import Any, Dict, List

from kdeaichat import chats
from kdeaichat.images import sniff

MAX_BYTES = 64 * 1024 * 1024
_FILE = re.compile(r"^attachments/([A-Za-z0-9._-]{1,128})/([0-9a-f]{64})\.([a-z0-9]{1,8})\Z")
_EXT_BY_MIME = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif", "image/bmp": "bmp"}


def _decode(item: Dict[str, Any]) -> bytes:
    content = item.get("content")
    if not isinstance(content, str):
        raise ValueError("no content")
    if item.get("kind") == "text":
        data = content.encode("utf-8")
    elif item.get("kind") == "base64":
        data = base64.b64decode(content, validate=True)
    else:
        raise ValueError("unknown kind")
    if len(data) > MAX_BYTES:
        raise ValueError("too large")
    return data


def _extension(item: Dict[str, Any], data: bytes) -> str:
    if item.get("kind") == "text":
        return "txt"
    kind = sniff(data)
    if kind:
        return kind[1]
    return _EXT_BY_MIME.get(str(item.get("mime") or ""), "bin")


def _folder(directory: str, chat: str, create: bool) -> str:
    base = os.path.join(directory, "attachments")
    path = os.path.join(base, chats.chat_folder_name(chat))
    if create:
        for folder in (base, path):
            if os.path.islink(folder):
                raise ValueError("attachment folder is a link")
            os.makedirs(folder, mode=0o700, exist_ok=True)
            os.chmod(folder, 0o700)
    return path


def _sha256_of_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def _store_one(directory: str, chat: str, item: Dict[str, Any]) -> Dict[str, Any]:
    data = _decode(item)
    digest = hashlib.sha256(data).hexdigest()
    folder = _folder(directory, chat, True)
    existing = [n for n in os.listdir(folder) if n.startswith(digest + ".") and not os.path.islink(os.path.join(folder, n))]
    name = existing[0] if existing else digest + "." + _extension(item, data)
    full = os.path.join(folder, name)
    # An existing file is trusted only after its hash is checked again.
    if not existing or _sha256_of_file(full) != digest:
        fd, tmp = tempfile.mkstemp(prefix="." + name + ".", dir=folder)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, full)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        if _sha256_of_file(full) != digest:  # read back before the caller drops its copy
            raise OSError("the stored file does not match")
    return {"ok": True, "hash": digest, "file": "/".join(["attachments", os.path.basename(folder), name]), "bytes": len(data)}


def cmd_attachment_store(payload: Dict[str, Any]) -> None:
    directory = chats._chat_dir(payload)
    chat = str(payload.get("chat") or "")
    if chat.startswith("s-incognito-"):
        raise ValueError("incognito chats keep no files")
    results: List[Dict[str, Any]] = []
    for item in payload.get("items", []):
        try:
            results.append(_store_one(directory, chat, item if isinstance(item, dict) else {}))
        except (ValueError, OSError) as e:
            results.append({"ok": False, "error": str(e)})
    print(json.dumps({"items": results}))


def _file_for(directory: str, rel: str) -> str:
    match = _FILE.match(rel)
    if not match:
        raise ValueError("invalid attachment path")
    full = os.path.join(os.path.realpath(directory), rel)
    if os.path.islink(full) or not os.path.isfile(full):
        raise ValueError("attachment not found")
    if not os.path.realpath(full).startswith(os.path.realpath(directory) + os.sep):
        raise ValueError("invalid attachment path")
    return full


def cmd_attachment_read(payload: Dict[str, Any]) -> None:
    directory = chats._chat_dir(payload)
    results: List[Dict[str, Any]] = []
    for item in payload.get("items", []):
        rel = str(item.get("file", "")) if isinstance(item, dict) else ""
        try:
            full = _file_for(directory, rel)
            if os.path.getsize(full) > MAX_BYTES:
                raise ValueError("too large")
            with open(full, "rb") as f:
                data = f.read()
            if hashlib.sha256(data).hexdigest() != _FILE.match(rel).group(2):  # type: ignore[union-attr]
                raise ValueError("the stored file is damaged")
            content = data.decode("utf-8", errors="replace") if item.get("kind") == "text" else base64.b64encode(data).decode("ascii")
            results.append({"file": rel, "ok": True, "content": content})
        except (ValueError, OSError) as e:
            results.append({"file": rel, "ok": False, "error": str(e)})
    print(json.dumps({"items": results}))


def cmd_attachment_delete(payload: Dict[str, Any]) -> None:
    """Remove the attachment folders of chats that are gone."""
    directory = chats._chat_dir(payload)
    removed = 0
    for chat in payload.get("chats", []):
        folder = os.path.join(directory, "attachments", chats.chat_folder_name(str(chat)))
        if os.path.isdir(folder) and not os.path.islink(folder):
            shutil.rmtree(folder, ignore_errors=True)
            removed += 1
    base = os.path.join(directory, "attachments")
    try:
        os.rmdir(base)  # only when empty
    except OSError:
        pass
    print(json.dumps({"deleted": removed}))


COMMANDS = {
    "attachment_store": cmd_attachment_store,
    "attachment_read": cmd_attachment_read,
    "attachment_delete": cmd_attachment_delete,
}
