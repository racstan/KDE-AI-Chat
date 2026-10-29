"""Import conversations from a ChatGPT or Claude data export as new direct-mode chats.

Commands (payload is JSON; one JSON object on stdout; ``ok: false`` with an ``error`` text on a bad file):
  import_inspect {path}              -> {ok, format: "chatgpt"|"claude", conversations}
  import_run     {path, directory}   -> {ok, format, imported, existing, empty}
``path`` is the export's .zip or its conversations.json; ``directory`` is chats/applet-<id>.

Each conversation becomes a chat with the stable id ``imp-<format>-<source id>``, so a second import skips the
ones that are already there (``existing``). Only user and assistant text is kept (system and tool messages
and empty ones are skipped); pictures and files are not imported and are noted in the message as
"[attachment not imported: <name>]". Chats are written in the widget's own file format (chat_files.py).

ChatGPT: ``mapping`` is a tree of nodes; the main branch is the path from ``current_node`` up to the root.
Claude: ``chat_messages`` is a flat list with ``sender`` "human" or "assistant".
"""
import datetime as dt
import json
import os
import re
import zipfile
from typing import Any, Dict, Iterator, List, Optional, Tuple

from kdeaichat import chat_files
from kdeaichat.common import safe_path

MAX_JSON_BYTES = 512 * 1024 * 1024
MAX_CONVERSATIONS = 50000
MAX_MESSAGES = 20000
MAX_TEXT = 1000000
_MEMBER = re.compile(r"(^|/)conversations(-\d{1,4})?\.json\Z")
_ID_CHARS = re.compile(r"[^A-Za-z0-9._-]")


def _out(data: Dict[str, Any]) -> None:
    print(json.dumps(data, ensure_ascii=False))


def _read_json(raw: bytes) -> Any:
    return json.loads(raw.decode("utf-8-sig"))


def load_conversations(path: str) -> List[Any]:
    """The conversation list of an export (a zip with conversations*.json, or a conversations.json)."""
    path = safe_path(path)
    if not os.path.isfile(path):
        raise ValueError("That file wasn't found.")
    chunks: List[Any] = []
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            names = sorted(i for i in z.infolist() if not i.is_dir() and _MEMBER.search(i.filename)
                           and ".." not in i.filename.split("/"))
            if not names:
                raise ValueError("This zip has no conversations.json: is it a ChatGPT or Claude export?")
            for info in names:
                if info.file_size > MAX_JSON_BYTES:
                    raise ValueError("conversations.json is too large")
                with z.open(info) as f:
                    raw = f.read(MAX_JSON_BYTES + 1)
                if len(raw) > MAX_JSON_BYTES:
                    raise ValueError("conversations.json is too large")
                chunks.append(_read_json(raw))
    else:
        if os.path.getsize(path) > MAX_JSON_BYTES:
            raise ValueError("conversations.json is too large")
        with open(path, "rb") as f:
            chunks.append(_read_json(f.read()))
    items: List[Any] = []
    for chunk in chunks:
        if not isinstance(chunk, list):
            raise ValueError("conversations.json is not a list of conversations")
        items.extend(chunk)
    if len(items) > MAX_CONVERSATIONS:
        raise ValueError("too many conversations")
    return items


def detect(items: List[Any]) -> str:
    for item in items:
        if isinstance(item, dict):
            if isinstance(item.get("mapping"), dict):
                return "chatgpt"
            if isinstance(item.get("chat_messages"), list):
                return "claude"
    if not items:
        return "chatgpt"
    raise ValueError("This isn't a ChatGPT or Claude conversations.json.")


# ---- one conversation -> (title, created ms, updated ms, [(role, text, at ms, model)]) ----

def _ms(value: Any) -> int:
    """Epoch seconds (ChatGPT) or an ISO date (Claude) as milliseconds; 0 when unknown."""
    try:
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return int(value * 1000) if 0 < value < 1e11 else int(value)
        if isinstance(value, str) and value:
            return int(dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)
    except (ValueError, OverflowError, OSError):
        pass
    return 0


def _note(name: Any) -> str:
    return "[attachment not imported: %s]" % (str(name or "file").strip().replace("\n", " ")[:120] or "file")


def _gpt_text(message: Dict[str, Any]) -> str:
    content = message.get("content")
    if not isinstance(content, dict):
        return ""
    kind = content.get("content_type")
    parts: List[str] = []
    if kind == "code":
        code = str(content.get("text") or "")
        return "```%s\n%s\n```" % (str(content.get("language") or "").replace("unknown", ""), code) if code.strip() else ""
    if kind not in ("text", "multimodal_text"):
        return ""
    for part in content.get("parts") or []:
        if isinstance(part, str):
            if part.strip():
                parts.append(part)
        elif isinstance(part, dict):
            ptype = str(part.get("content_type") or "")
            if ptype in ("image_asset_pointer", "audio_asset_pointer", "real_time_user_audio_video_asset_pointer"):
                parts.append(_note(ptype.split("_")[0] + " " + str(part.get("asset_pointer") or "")[-40:]))
            elif isinstance(part.get("text"), str) and part["text"].strip():
                parts.append(part["text"])
    meta = message.get("metadata") if isinstance(message.get("metadata"), dict) else {}
    for att in meta.get("attachments") or []:
        if isinstance(att, dict):
            parts.append(_note(att.get("name")))
    return "\n\n".join(parts)


def _gpt_branch(mapping: Dict[str, Any], current: Any) -> List[Dict[str, Any]]:
    """Nodes from the root down to the conversation's last node on the main branch."""
    path: List[Dict[str, Any]] = []
    seen = set()
    node_id = current if isinstance(current, str) and current in mapping else None
    if node_id is None:  # no current_node: follow the last child from a root
        roots = [k for k, v in mapping.items() if isinstance(v, dict) and not v.get("parent")]
        node_id = roots[0] if roots else None
        while node_id and isinstance(mapping.get(node_id), dict):
            kids = [k for k in mapping[node_id].get("children") or [] if k in mapping]
            if not kids:
                break
            node_id = kids[-1]
    while node_id and node_id not in seen and isinstance(mapping.get(node_id), dict):
        seen.add(node_id)
        path.append(mapping[node_id])
        node_id = mapping[node_id].get("parent")
    path.reverse()
    return path


def convert_chatgpt(conv: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    mapping = conv.get("mapping") or {}
    source_id = str(conv.get("conversation_id") or conv.get("id") or "")
    out: List[Dict[str, Any]] = []
    for node in _gpt_branch(mapping, conv.get("current_node")):
        message = node.get("message")
        if not isinstance(message, dict):
            continue
        author = message.get("author") if isinstance(message.get("author"), dict) else {}
        role = author.get("role")
        meta = message.get("metadata") if isinstance(message.get("metadata"), dict) else {}
        if role not in ("user", "assistant") or meta.get("is_visually_hidden_from_conversation"):
            continue
        if role == "assistant" and message.get("recipient") not in (None, "all"):
            continue  # a call to a tool, not a reply
        text = _gpt_text(message)
        if text.strip():
            out.append({"role": role, "text": text, "at": _ms(message.get("create_time")),
                        "model": str(meta.get("model_slug") or "") if role == "assistant" else ""})
    return _finish("chatgpt", source_id, conv.get("title"), _ms(conv.get("create_time")), _ms(conv.get("update_time")), out)


def convert_claude(conv: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for message in conv.get("chat_messages") or []:
        if not isinstance(message, dict):
            continue
        role = {"human": "user", "assistant": "assistant"}.get(str(message.get("sender")))
        if role is None:
            continue
        text = message.get("text") if isinstance(message.get("text"), str) else ""
        if not text.strip():
            text = "\n\n".join(b["text"] for b in message.get("content") or []
                               if isinstance(b, dict) and b.get("type") == "text" and isinstance(b.get("text"), str)
                               and b["text"].strip())
        notes = [_note(a.get("file_name")) for a in list(message.get("attachments") or []) + list(message.get("files") or [])
                 if isinstance(a, dict)]
        text = "\n\n".join([text] + notes) if text.strip() else "\n\n".join(notes)
        if text.strip():
            out.append({"role": role, "text": text, "at": _ms(message.get("created_at")), "model": ""})
    return _finish("claude", str(conv.get("uuid") or ""), conv.get("name"), _ms(conv.get("created_at")),
                   _ms(conv.get("updated_at")), out)


def _finish(fmt: str, source_id: str, title: Any, created: int, updated: int, msgs: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if not msgs or not source_id:
        return None
    msgs = msgs[:MAX_MESSAGES]
    stamps = [m["at"] for m in msgs if m["at"]]
    created = created or (min(stamps) if stamps else 0) or int(dt.datetime.now().timestamp() * 1000)
    updated = updated or (max(stamps) if stamps else 0) or created
    clean = _ID_CHARS.sub("-", source_id)[:100]
    name = " ".join(str(title or "").split())[:80]
    first = msgs[0]["text"].strip().split("\n")[0][:40]
    return {"id": "imp-%s-%s" % (fmt, clean), "title": name or first or "Imported chat", "created": created,
            "updated": updated, "messages": msgs}


def _chat(conv: Dict[str, Any]) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    """(index entry, stored messages) of a converted conversation."""
    stored: List[Dict[str, Any]] = []
    for i, m in enumerate(conv["messages"]):
        at = m["at"] or conv["created"]
        clock = dt.datetime.fromtimestamp(at / 1000).strftime("%H:%M")
        item = {"id": "%s-%d" % (conv["id"], i), "role": m["role"], "content": m["text"][:MAX_TEXT], "time": clock,
                "at": at, "model": m["model"]}
        if m["role"] == "user":
            item.update(queueId=0, attachments=[])
        else:
            item["reasoning"] = ""
        stored.append(item)
    meta = {"value": conv["id"], "text": conv["title"], "source": "provider", "createdAt": conv["created"],
            "updatedAt": conv["updated"], "archived": False, "projectId": "", "openCodeSessionId": "",
            "openCodeWorkspaceCwd": "", "messageCount": len(stored)}
    return meta, stored


def _converted(items: List[Any]) -> Tuple[str, Iterator[Optional[Dict[str, Any]]]]:
    fmt = detect(items)
    convert = convert_chatgpt if fmt == "chatgpt" else convert_claude
    return fmt, (convert(i) if isinstance(i, dict) else None for i in items)


def cmd_import_inspect(payload: Dict[str, Any]) -> None:
    try:
        fmt, converted = _converted(load_conversations(payload.get("path")))
        count = sum(1 for c in converted if c)
    except (ValueError, OSError, zipfile.BadZipFile) as e:
        _out({"ok": False, "error": str(e) or "This file couldn't be read."})
        return
    _out({"ok": True, "format": fmt, "conversations": count})


def cmd_import_run(payload: Dict[str, Any]) -> None:
    try:
        fmt, converted = _converted(load_conversations(payload.get("path")))
        directory = chat_files.folder(payload)
        imported = existing = empty = 0
        with chat_files.locked(directory):
            taken = chat_files.known_ids(directory)
            metas: List[Dict[str, Any]] = []
            for conv in converted:
                if conv is None:
                    empty += 1
                elif conv["id"] in taken:
                    existing += 1
                else:
                    meta, stored = _chat(conv)
                    chat_files.write_messages(directory, conv["id"], stored)
                    metas.append(meta)
                    taken.add(conv["id"])
                    imported += 1
            chat_files.add_to_index(directory, metas)
    except (ValueError, OSError, zipfile.BadZipFile) as e:
        _out({"ok": False, "error": str(e) or "This file couldn't be read."})
        return
    _out({"ok": True, "format": fmt, "imported": imported, "existing": existing, "empty": empty})


COMMANDS = {"import_inspect": cmd_import_inspect, "import_run": cmd_import_run}
