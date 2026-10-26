"""panel_icon_check: what Settings → Appearance needs to know about a file
chosen as the animated panel icon, before it is used.

Payload {path}. Reply {ok, exists, size, kind}: size in bytes, kind
"animated" (GIF, APNG, WebP) or "video" (MP4, WebM, MKV, MOV, M4V, OGV) by
the file's contents where they say it, else its extension, "" otherwise.
The size limit itself is decided by the page (chat/PanelIcon.js). Nothing is
written.
"""
import json
import os
from typing import Any, Dict

from kdeaichat.common import safe_path

ANIMATED = {"gif", "apng", "png", "webp"}
VIDEO = {"mp4", "webm", "mkv", "mov", "m4v", "ogv"}


def sniff(head: bytes) -> str:
    """The kind a file's first bytes show, or "" when they don't say."""
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return "animated"
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return "animated"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "animated"
    if head[4:8] == b"ftyp" or head[:4] == b"\x1a\x45\xdf\xa3" or head[:4] == b"OggS":
        return "video"
    return ""


def check(path: str) -> Dict[str, Any]:
    try:
        target = safe_path(path)
    except ValueError as error:
        return {"ok": False, "error": str(error)}
    if not os.path.isfile(target):
        return {"ok": True, "exists": False, "size": 0, "kind": ""}
    size = os.path.getsize(target)
    try:
        with open(target, "rb") as f:
            kind = sniff(f.read(16))
    except OSError as error:
        return {"ok": False, "error": str(error)}
    if not kind:
        ext = os.path.splitext(target)[1].lower().lstrip(".")
        kind = "animated" if ext in ANIMATED else "video" if ext in VIDEO else ""
    return {"ok": True, "exists": True, "size": size, "kind": kind}


def cmd_panel_icon_check(payload: Dict[str, Any]) -> None:
    print(json.dumps(check(str(payload.get("path") or ""))))


COMMANDS = {"panel_icon_check": cmd_panel_icon_check}
