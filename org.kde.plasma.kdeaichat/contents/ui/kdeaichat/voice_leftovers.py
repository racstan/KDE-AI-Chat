"""What the old built-in voice engines left on disk, found for Settings → Storage (never created here).

The widget no longer installs speech models: all speech goes through Speech Note (a separate app), the
system voice or a speech server. Users who tried the earlier engines still have their venvs and models,
and Settings → Storage ("Old voice engines") offers to delete them. This module finds them:

* the HuggingFace cache folders of faster-whisper models the widget downloaded itself, recorded in
  ``stt-downloads.json`` (only names on ``_REPOS``, so the file can't point anywhere else);
* Speech Note's own models folder, which is only reported, never counted or removed.
"""
import json
import os
from typing import List, Optional

from kdeaichat import chats

# Where faster-whisper downloaded each model name from.
_REPOS = {
    "tiny": "Systran/faster-whisper-tiny", "tiny.en": "Systran/faster-whisper-tiny.en",
    "base": "Systran/faster-whisper-base", "base.en": "Systran/faster-whisper-base.en",
    "small": "Systran/faster-whisper-small", "small.en": "Systran/faster-whisper-small.en",
    "medium": "Systran/faster-whisper-medium", "medium.en": "Systran/faster-whisper-medium.en",
    "large-v1": "Systran/faster-whisper-large-v1", "large-v2": "Systran/faster-whisper-large-v2",
    "large-v3": "Systran/faster-whisper-large-v3", "large": "Systran/faster-whisper-large-v3",
    "large-v3-turbo": "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
    "turbo": "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
    "distil-small.en": "Systran/faster-distil-whisper-small.en",
    "distil-medium.en": "Systran/faster-distil-whisper-medium.en",
    "distil-large-v2": "Systran/faster-distil-whisper-large-v2",
    "distil-large-v3": "Systran/faster-distil-whisper-large-v3",
    "distil-large-v3.5": "distil-whisper/distil-large-v3.5-ct2",
}


def hf_cache() -> str:
    if os.environ.get("HF_HUB_CACHE"):
        return os.environ["HF_HUB_CACHE"]
    home = os.environ.get("HF_HOME") or os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                                                     "huggingface")
    return os.path.join(home, "hub")


def recorded_models() -> List[str]:
    """Model names the old installer recorded as downloaded by the widget."""
    try:
        with open(os.path.join(chats.data_root(), "stt-downloads.json"), encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return []
    models = data.get("models") if isinstance(data, dict) else None
    return sorted(k for k in models if k in _REPOS) if isinstance(models, dict) else []


def model_folders() -> List[str]:
    """Existing HF cache folders of the recorded models (the repo comes from ``_REPOS``, not from the file)."""
    found: List[str] = []
    for name in recorded_models():
        folder = os.path.join(hf_cache(), "models--" + _REPOS[name].replace("/", "--"))
        if folder not in found and os.path.isdir(folder) and not os.path.islink(folder):
            found.append(folder)
    return found


def speech_note_dirs(home: Optional[str] = None) -> List[str]:
    home = home or os.path.expanduser("~")
    dirs = [os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(home, ".cache"), "net.mkiol", "dsnote",
                         "speech-models"),
            os.path.join(home, ".var", "app", "net.mkiol.SpeechNote", "cache", "net.mkiol", "dsnote", "speech-models")]
    for conf in (os.path.join(home, ".config", "net.mkiol", "dsnote", "settings.conf"),
                 os.path.join(home, ".var", "app", "net.mkiol.SpeechNote", "config", "net.mkiol", "dsnote", "settings.conf")):
        try:
            with open(conf, encoding="utf-8", errors="replace") as f:
                for line in f:
                    key, _, value = line.partition("=")
                    if key.strip() in ("models_dir", "lang_models_dir") and value.strip():
                        dirs.append(os.path.expanduser(value.strip().strip('"')))
        except OSError:
            pass
    unique: List[str] = []
    for d in dirs:
        if d not in unique and os.path.isdir(d):
            unique.append(d)
    return unique
