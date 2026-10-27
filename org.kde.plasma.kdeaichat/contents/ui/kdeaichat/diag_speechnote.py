"""Setup check for the Speech Note engine (dictation or read aloud): is it installed,
does its service start, and has it a model for the role. Rows as in diag_agents.row.

Reads Speech Note's state through speechnote.status with start=True, which starts the
service when the user presses "Check setup" (it stops itself after 60 s idle).
"""
from typing import Any, Dict, List

from kdeaichat import speechnote
from kdeaichat.diag_agents import row
from kdeaichat.speechnote_bus import SpeechNoteError

ROLES = {"stt": ("stt_models", "stt-engine"), "tts": ("tts_models", "tts-engine")}


def check(role: str) -> List[Dict[str, Any]]:
    """role: "stt" (dictation) or "tts" (read aloud)."""
    models_key, row_id = ROLES[role]
    missing = "error" if role == "stt" else "warn"   # read aloud falls back to the system voice
    try:
        reply = speechnote.status({"start": True})
    except SpeechNoteError as e:
        if e.code == "not_installed":
            return [row(row_id, "voice", missing, "speechnote-missing-" + role)]
        if e.code == "not_configured":
            return [row(row_id, "voice", "warn", "speechnote-no-model-" + role)]
        return [row(row_id, "voice", "warn", "speechnote-service", str(e))]
    if not reply.get("installed"):
        return [row(row_id, "voice", missing, "speechnote-missing-" + role)]
    if reply.get("models_known") and not reply.get(models_key):
        return [row(row_id, "voice", "warn", "speechnote-no-model-" + role)]
    return [row(row_id, "voice", "ok", "speechnote-ready-" + role, reply.get("kind") or "")]
