"""Speech-to-text models: the faster-whisper list (size, recommended) and models already on disk.

Models other apps downloaded are offered before any download:

* Speech Note (``net.mkiol/dsnote``): ``~/.cache/net.mkiol/dsnote/speech-models``
  (Flatpak: ``~/.var/app/net.mkiol.SpeechNote/cache/...``, or the folder set as
  ``service/models_dir`` in its ``settings.conf``). A faster-whisper model is a
  folder named after its id (``*_fasterwhisper_*``, CTranslate2 ``model.bin``);
  a whisper.cpp model is ``<id>.ggml`` (``*_whisper_*``; its Parakeet models use
  ``.ggml`` too and are skipped).
* Handy (``com.pais.handy``): whisper.cpp ``.bin`` files in
  ``~/.local/share/com.pais.handy/models`` (its newer ``.gguf`` files need
  Handy's own engine and are skipped).
* The HuggingFace cache (faster-whisper's own downloads, other CTranslate2 repos).
* whisper.cpp's ``models/`` folders (``ggml-*.bin``).
"""
import glob
import os
import re
from typing import Any, Dict, List, Optional

from kdeaichat.stt_setup import MODELS, cached_model, hf_cache

RECOMMENDED_CPU = "small"
RECOMMENDED_GPU = "large-v3-turbo"
_NOTES = {"tiny": "fastest, least accurate", "base": "fast", "small": "good balance on a CPU",
          "medium": "accurate, slow on a CPU", "large-v3": "most accurate, needs a GPU",
          "large-v3-turbo": "near large-v3 quality, much faster", "distil-large-v3": "English, fast on a GPU"}


def _home(*parts: str) -> str:
    return os.path.join(os.path.expanduser("~"), *parts)


def _size_mb(path: str) -> int:
    if os.path.isfile(path):
        return round(os.path.getsize(path) / 1e6)
    return round(sum(os.path.getsize(f) for f in glob.glob(os.path.join(path, "*")) if os.path.isfile(f)) / 1e6)


def catalogue(gpu: bool = False, cache: Optional[str] = None) -> List[Dict[str, Any]]:
    """faster-whisper model names with download size, whether downloaded, and the recommended one."""
    recommended = RECOMMENDED_GPU if gpu else RECOMMENDED_CPU
    rows = []
    for name, (repo, mb) in MODELS.items():
        if name in ("large", "turbo"):
            continue  # aliases of large-v3 / large-v3-turbo
        rows.append({"name": name, "mb": mb, "repo": repo, "english_only": name.endswith(".en"),
                     "downloaded": bool(cached_model(name, cache)), "recommended": name == recommended,
                     "note": _NOTES.get(name, "")})
    return rows


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
    seen, unique = set(), []
    for d in dirs:
        if d not in seen and os.path.isdir(d):
            seen.add(d)
            unique.append(d)
    return unique


def _is_ct2(folder: str) -> bool:
    return os.path.isfile(os.path.join(folder, "model.bin")) and os.path.isfile(os.path.join(folder, "config.json"))


def _speech_note(home: Optional[str]) -> List[Dict[str, Any]]:
    found = []
    for folder in speech_note_dirs(home):
        for entry in sorted(os.listdir(folder)):
            path = os.path.join(folder, entry)
            if "_fasterwhisper_" in entry and os.path.isdir(path) and _is_ct2(path):
                found.append({"engine": "faster-whisper", "path": path, "name": entry, "source": "Speech Note"})
            elif re.search(r"_whisper_.*\.ggml$", entry) and os.path.isfile(path):
                found.append({"engine": "whisper-cpp", "path": path, "name": entry[:-5], "source": "Speech Note"})
    return found


def _handy(home: Optional[str]) -> List[Dict[str, Any]]:
    folder = os.path.join(home or os.path.expanduser("~"), ".local", "share", "com.pais.handy", "models")
    return [{"engine": "whisper-cpp", "path": p, "name": os.path.basename(p)[:-4], "source": "Handy"}
            for p in sorted(glob.glob(os.path.join(folder, "*.bin"))) if os.path.isfile(p)]


def _whisper_cpp(home: Optional[str]) -> List[Dict[str, Any]]:
    home = home or os.path.expanduser("~")
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    folders = [os.path.join(home, "whisper.cpp", "models"), os.path.join(data, "whisper.cpp", "models"),
               "/usr/share/whisper.cpp/models", "/usr/local/share/whisper.cpp/models"]
    return [{"engine": "whisper-cpp", "path": p, "name": os.path.basename(p)[5:-4], "source": "whisper.cpp"}
            for folder in folders for p in sorted(glob.glob(os.path.join(folder, "ggml-*.bin")))
            if os.path.isfile(p) and "silero" not in p]


def _huggingface(cache: Optional[str]) -> List[Dict[str, Any]]:
    known = {"models--" + repo.replace("/", "--"): name for name, (repo, _) in MODELS.items()}
    found = []
    for repo in sorted(glob.glob(os.path.join(cache or hf_cache(), "models--*"))):
        base = os.path.basename(repo)
        if base not in known and "whisper" not in base.lower():
            continue
        for snapshot in sorted(glob.glob(os.path.join(repo, "snapshots", "*"))):
            if _is_ct2(snapshot):
                name = known.get(base) or base[len("models--"):].replace("--", "/")
                # A known name loads by name (faster-whisper finds it in the cache); others by folder.
                found.append({"engine": "faster-whisper", "path": snapshot, "name": name, "source": "HuggingFace",
                              "model": known.get(base) or snapshot})
                break
    return found


def discover(home: Optional[str] = None, cache: Optional[str] = None) -> List[Dict[str, Any]]:
    """Models on disk for faster-whisper (CTranslate2 folders) and whisper.cpp (ggml files)."""
    found = _huggingface(cache) + _speech_note(home) + _handy(home) + _whisper_cpp(home)
    for row in found:
        row.setdefault("model", row["path"])  # what goes into sttModel / sttWhisperCppModel
        row["mb"] = _size_mb(row["path"])
    return found
