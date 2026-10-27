"""The Parakeet dictation engine's model: NVIDIA Parakeet Unified EN 0.6B as GGUF (helper side, stdlib only).

The model is ``nvidia/parakeet-unified-en-0.6b`` (NVIDIA Open Model License),
converted to GGUF by Handy's authors for transcribe.cpp
(``handy-computer/parakeet-unified-en-0.6b-gguf``, Q8_0, 731 MB): the same
file Handy uses. The on-demand service runs it with transcribe.cpp's Python
binding (``voice/stt_parakeet_model.py``), no torch.

``sttParakeetModel`` is ``parakeet-unified-en-0.6b`` (the default: found on
disk, else downloaded) or an absolute ``.gguf`` path. The default is looked
for, in this order, in our own download folder, the HuggingFace cache (where
Handy keeps it) and Handy's models folder, so an existing copy is reused
without downloading. A download is pinned to one revision and checked
against the file's SHA-256 before it is used.
"""
import glob
import hashlib
import os
import urllib.request
from typing import Any, Callable, Dict, List, Optional

from kdeaichat import chats
from kdeaichat.stt_setup import hf_cache

NAME = "parakeet-unified-en-0.6b"
LABEL = "Parakeet Unified EN 0.6B"
REPO = "handy-computer/parakeet-unified-en-0.6b-gguf"
REVISION = "7e948f21b7bdbac698d3318db9d350f1096f3b6c"
FILE = "parakeet-unified-en-0.6b-Q8_0.gguf"
SHA256 = "4b50b6dd862bf6e346929aaf4f5eaacec003bfa3f56462d6c874b41ef2f38795"
BYTES = 731357568
MB = round(BYTES / 1e6)
URL = "https://huggingface.co/%s/resolve/%s/%s" % (REPO, REVISION, FILE)
# transcribe.cpp's binding and its prebuilt library (CPU and Vulkan GPU). Pre-1.0, both must match exactly.
VERSION = "0.4.1"
PACKAGES = {"transcribe-cpp": 1, "transcribe-cpp-native": 23}
IMPORT_NAMES = {"transcribe-cpp": "transcribe_cpp", "transcribe-cpp-native": "transcribe_cpp_native"}
CHUNK = 1024 * 1024


class DownloadError(Exception):
    pass


def own_dir() -> str:
    """Where a download goes: everything in it is ours (Remove data deletes it)."""
    return os.path.join(chats.data_root(), "models", "parakeet")


def handy_dir(home: Optional[str] = None) -> str:
    return os.path.join(home or os.path.expanduser("~"), ".local", "share", "com.pais.handy", "models")


def _hf_files(cache: Optional[str], repo_glob: str, file_glob: str) -> List[str]:
    pattern = os.path.join(cache or hf_cache(), repo_glob, "snapshots", "*", file_glob)
    return [p for p in sorted(glob.glob(pattern)) if os.path.isfile(p)]


def default_candidates(home: Optional[str] = None, cache: Optional[str] = None) -> List[Dict[str, str]]:
    """Where the default model may already be, in the order they are used."""
    rows = [{"path": os.path.join(own_dir(), FILE), "source": "KDE AI Chat"}]
    # Handy downloads it into the HuggingFace cache.
    rows += [{"path": p, "source": "Handy, HuggingFace cache"}
             for p in _hf_files(cache, "models--" + REPO.replace("/", "--"), FILE)]
    rows.append({"path": os.path.join(handy_dir(home), FILE), "source": "Handy"})
    return rows


def find_default(home: Optional[str] = None, cache: Optional[str] = None) -> Dict[str, str]:
    """The first copy of the default model on disk: {"path", "source"}, or {}."""
    for row in default_candidates(home, cache):
        if os.path.isfile(row["path"]) and os.path.getsize(row["path"]) > 0:
            return row
    return {}


def resolve(model: str, home: Optional[str] = None, cache: Optional[str] = None) -> str:
    """The .gguf file to load for sttParakeetModel, or "" when it has to be downloaded first."""
    if model == NAME:
        return find_default(home, cache).get("path", "")
    return model if os.path.isfile(model) else ""


def is_gguf(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"GGUF"
    except OSError:
        return False


def discover(home: Optional[str] = None, cache: Optional[str] = None) -> List[Dict[str, Any]]:
    """Parakeet GGUF files on this computer (HuggingFace cache, Handy, our downloads), other than
    the default's copy that the catalogue row already stands for."""
    default = os.path.realpath(find_default(home, cache).get("path", "") or "/nonexistent")
    candidates = [(p, "HuggingFace") for p in _hf_files(cache, "models--*parakeet*", "*.gguf")]
    candidates += [(p, "Handy") for p in sorted(glob.glob(os.path.join(handy_dir(home), "*.gguf")))
                   if "parakeet" in os.path.basename(p).lower()]
    candidates += [(p, "KDE AI Chat") for p in sorted(glob.glob(os.path.join(own_dir(), "*.gguf")))]
    found, seen = [], {default}
    for path, source in candidates:
        real = os.path.realpath(path)
        if real in seen or not os.path.isfile(path):
            continue
        seen.add(real)
        found.append({"engine": "parakeet", "path": path, "model": path, "name": os.path.basename(path)[:-5],
                      "source": source, "mb": round(os.path.getsize(path) / 1e6)})
    return found


def catalogue(home: Optional[str] = None, cache: Optional[str] = None) -> List[Dict[str, Any]]:
    """The default model, whether it is on disk already and where."""
    found = find_default(home, cache)
    return [{"name": NAME, "label": LABEL, "mb": MB, "repo": REPO, "english_only": True, "recommended": True,
             "downloaded": bool(found), "path": found.get("path", ""), "source": found.get("source", ""),
             "note": "fast, accurate English transcription; English only"}]


def download(opener: Callable[..., Any] = urllib.request.urlopen, url: str = URL,
             sha256: str = SHA256, size: int = BYTES) -> Dict[str, Any]:
    """Download the default model into own_dir() (only after the settings page showed its size).

    Written to a private .part file, checked (size and SHA-256), then renamed into place.
    """
    found = find_default()
    if found:
        return {"type": "stt_downloaded", "model": NAME, "path": found["path"], "already": True}
    folder = own_dir()
    os.makedirs(folder, mode=0o700, exist_ok=True)
    target = os.path.join(folder, FILE)
    part = target + ".part"
    digest, written = hashlib.sha256(), 0
    try:
        with opener(url, timeout=60) as response, open(part, "wb") as out:
            while True:
                chunk = response.read(CHUNK)
                if not chunk:
                    break
                written += len(chunk)
                if written > size:
                    raise DownloadError("the download is bigger than expected")
                digest.update(chunk)
                out.write(chunk)
        if written != size or digest.hexdigest() != sha256:
            raise DownloadError("the downloaded file is damaged (size or checksum differs); try again")
        os.replace(part, target)
    except OSError as e:
        raise DownloadError("downloading failed: %s" % (getattr(e, "reason", None) or e.strerror or e)) from None
    finally:
        if os.path.exists(part):
            os.unlink(part)
    return {"type": "stt_downloaded", "model": NAME, "path": target}


def installed(venv: str) -> bool:
    """transcribe.cpp's binding and native library are in the voice venv."""
    return all(glob.glob(os.path.join(venv, "lib", "python3*", "site-packages", name))
               for name in IMPORT_NAMES.values())
