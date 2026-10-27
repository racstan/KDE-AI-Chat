"""Disk space used by the voice features, removing it again, and Piper voices on disk.

  voice_data         {} -> {"type": "voice_data", "faster_whisper": {venv, venv_exists, venv_mb, has_torch,
                       rebuild_frees_mb, models: [{name, repo, path, mb}], models_mb, total_mb}}
  voice_data_remove  {engine: "faster-whisper", confirm: true, keepModels} -> {"type": "voice_data_removed",
                       freed_mb, removed: [paths]} | {"type": "voice_data_error", error}
  tts_piper_voices   {} -> {"type": "tts_piper_voices", voices: [{path, name, language, quality, source, mb}]}

Only what this widget made is ever deleted: the voice venv (exactly
``stt_settings.venv_dir({})``), the HuggingFace cache folders of models
recorded in ``stt-downloads.json`` when ``stt_download_model`` downloaded
them, and Parakeet's download folder (``stt_parakeet.own_dir()``). Models from Speech Note, Handy, whisper.cpp or other HF downloads are
never touched. ``keepModels`` is "Rebuild (smaller)": the venv goes, the
models stay, and the UI runs ``venv_setup.sh`` again.
"""
import fnmatch
import glob
import json
import os
import re
import shutil
from typing import Any, Dict, List, Optional

from kdeaichat import chats, stt_parakeet, stt_settings, stt_setup, stt_units
from kdeaichat.common import atomic_write_json
from kdeaichat.stt_models import speech_note_dirs

# site-packages entries the slim faster-whisper install does not need (older venvs had torch,
# the Kokoro/Piper read-aloud stack and spaCy). Matched on the normalised name (dist-info too).
_NOT_NEEDED = ("torch", "torch_*", "torchaudio", "torchvision", "torchgen", "functorch", "triton", "triton_*",
               "spacy", "spacy_*", "thinc", "blis", "cymem", "preshed", "murmurhash", "srsly", "wasabi",
               "weasel", "confection", "catalogue", "langcodes", "language_data", "curated_*", "en_core_web*",
               "transformers", "kokoro", "kokoro_*", "misaki", "piper", "piper_*", "sympy", "mpmath",
               "networkx", "scipy", "scipy.libs", "numba", "llvmlite", "espeakng*", "phonemizer*",
               "segments", "csvw", "clldutils", "dlinfo", "rdflib", "isodate", "uritemplate")
_NVIDIA_KEEP = ("cublas", "cudnn")
_PIPER_NAME = re.compile(r"^([a-z]{2,3}(?:_[A-Z]{2})?)-.+-(x_low|low|medium|high)$")
_MAX_JSON = 1024 * 1024


def _emit(data: Dict[str, Any]) -> None:
    print(json.dumps(data), flush=True)


def _mb(size: int) -> int:
    return round(size / 1e6)


def tree_bytes(path: str) -> int:
    """Bytes under ``path`` without following symlinks (a link counts as itself)."""
    try:
        st = os.lstat(path)
    except OSError:
        return 0
    if os.path.islink(path) or not os.path.isdir(path):
        return st.st_size
    total = 0
    for root, dirs, files in os.walk(path, followlinks=False):
        for name in files + [d for d in dirs if os.path.islink(os.path.join(root, d))]:
            try:
                total += os.lstat(os.path.join(root, name)).st_size
            except OSError:
                pass
    return total


# --- the record of models we downloaded --------------------------------------------------------

def record_path() -> str:
    return os.path.join(chats.data_root(), "stt-downloads.json")


def read_record() -> Dict[str, str]:
    try:
        with open(record_path(), encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    models = data.get("models") if isinstance(data, dict) else None
    if not isinstance(models, dict):
        return {}
    return {str(k): str(v) for k, v in models.items() if k in stt_setup.MODELS}


def _write_record(models: Dict[str, str]) -> None:
    atomic_write_json(record_path(), {"models": dict(sorted(models.items()))})


def record_download(name: str) -> None:
    """Remember that ``stt_download_model`` downloaded this model (it was not on disk before)."""
    if name in stt_setup.MODELS:
        models = read_record()
        models[name] = stt_setup.MODELS[name][0]
        _write_record(models)


def _model_folder(name: str) -> str:
    """The HF cache folder of a recorded model; the repo comes from our list, not from the file."""
    return os.path.join(stt_setup.hf_cache(), "models--" + stt_setup.MODELS[name][0].replace("/", "--"))


def _our_models() -> List[Dict[str, Any]]:
    rows, seen = [], set()
    for name in sorted(read_record()):
        folder = _model_folder(name)
        if folder in seen or os.path.islink(folder) or not os.path.isdir(folder):
            continue
        seen.add(folder)
        rows.append({"name": name, "repo": stt_setup.MODELS[name][0], "path": folder, "mb": _mb(tree_bytes(folder))})
    parakeet = stt_parakeet.own_dir()
    if os.path.isdir(parakeet) and not os.path.islink(parakeet) and os.listdir(parakeet):
        rows.append({"name": stt_parakeet.NAME, "repo": stt_parakeet.REPO, "path": parakeet,
                     "mb": _mb(tree_bytes(parakeet))})
    return rows


# --- the venv --------------------------------------------------------------------------------

def _site_packages(venv: str) -> List[str]:
    return sorted(glob.glob(os.path.join(venv, "lib", "python3*", "site-packages")))


def _normalised(entry: str) -> str:
    name = entry.lower()
    for suffix in (".dist-info", ".egg-info"):
        if name.endswith(suffix):
            name = name[: -len(suffix)].split("-")[0]
    return name.replace("-", "_")


def not_needed(site: str) -> List[str]:
    """site-packages entries a rebuild would leave out."""
    found = []
    for entry in sorted(os.listdir(site)):
        name = _normalised(entry)
        if name.startswith("nvidia_"):  # nvidia_*_cu12 dist-info: only cuBLAS and cuDNN are used
            if not any(name.startswith("nvidia_" + keep) for keep in _NVIDIA_KEEP):
                found.append(os.path.join(site, entry))
            continue
        if any(fnmatch.fnmatch(name, pattern) for pattern in _NOT_NEEDED):
            found.append(os.path.join(site, entry))
    nvidia = os.path.join(site, "nvidia")
    if os.path.isdir(nvidia) and not os.path.islink(nvidia):
        found += [os.path.join(nvidia, sub) for sub in sorted(os.listdir(nvidia))
                  if sub not in _NVIDIA_KEEP and sub not in ("__init__.py", "__pycache__")]
    return found


def faster_whisper_data() -> Dict[str, Any]:
    venv = stt_settings.venv_dir({})
    exists = os.path.isdir(venv) and not os.path.islink(venv)
    sites = _site_packages(venv) if exists else []
    venv_mb = _mb(tree_bytes(venv)) if exists else 0
    frees = sum(tree_bytes(p) for site in sites for p in not_needed(site))
    models = _our_models()
    models_mb = sum(m["mb"] for m in models)
    return {"venv": venv, "venv_exists": exists, "venv_mb": venv_mb,
            "has_torch": any(os.path.isdir(os.path.join(site, "torch")) for site in sites),
            "rebuild_frees_mb": _mb(frees), "models": models, "models_mb": models_mb,
            "total_mb": venv_mb + models_mb}


def cmd_voice_data(payload: Dict[str, Any]) -> None:
    _emit({"type": "voice_data", "faster_whisper": faster_whisper_data()})


def _checked_venv() -> str:
    venv = stt_settings.venv_dir({})
    root = chats.data_root()
    if os.path.islink(venv):
        raise ValueError("the voice venv is a symlink; remove it by hand")
    real_root = os.path.realpath(root)
    if os.path.dirname(os.path.realpath(venv)) != real_root or os.path.realpath(venv) == real_root:
        raise ValueError("the voice venv is not in " + root)
    return venv


def remove(keep_models: bool, run=None) -> Dict[str, Any]:
    venv = _checked_venv()
    freed, removed = 0, []
    if os.path.lexists(venv):
        stt_units.sync({"sttEnabled": False}, run=run)  # stop dictation and remove its units first
        freed += tree_bytes(venv)
        shutil.rmtree(venv)
        removed.append(venv)
    if not keep_models:
        record = read_record()
        for name in sorted(record):
            folder = _model_folder(name)
            if os.path.islink(folder):
                continue
            if os.path.isdir(folder):
                freed += tree_bytes(folder)
                shutil.rmtree(folder)
                removed.append(folder)
            record.pop(name)
        _write_record(record)
        parakeet = stt_parakeet.own_dir()
        if os.path.isdir(parakeet) and not os.path.islink(parakeet):
            freed += tree_bytes(parakeet)
            shutil.rmtree(parakeet)
            removed.append(parakeet)
    return {"type": "voice_data_removed", "freed_mb": _mb(freed), "removed": removed}


def cmd_voice_data_remove(payload: Dict[str, Any]) -> None:
    if payload.get("engine", "faster-whisper") not in ("faster-whisper", "parakeet"):
        _emit({"type": "voice_data_error", "error": "unknown engine"})
        return
    if payload.get("confirm") is not True:
        _emit({"type": "voice_data_error", "error": "removal needs confirm: true"})
        return
    try:
        _emit(remove(payload.get("keepModels") is True))
    except (OSError, ValueError) as e:
        _emit({"type": "voice_data_error", "error": str(e)})


# --- Piper voices ----------------------------------------------------------------------------

def _voice(onnx: str, source: str) -> Optional[Dict[str, Any]]:
    meta = onnx + ".json"
    if not (os.path.isfile(onnx) and os.path.isfile(meta)):
        return None
    name = os.path.basename(onnx)[:-5]
    language = quality = ""
    try:
        if os.path.getsize(meta) <= _MAX_JSON:
            with open(meta, encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                lang, audio = data.get("language"), data.get("audio")
                language = str(lang.get("code") or "") if isinstance(lang, dict) else ""
                quality = str(audio.get("quality") or "") if isinstance(audio, dict) else ""
    except (OSError, ValueError):
        pass
    match = _PIPER_NAME.match(name)
    if match:
        language = language or match.group(1)
        quality = quality or match.group(2)
    return {"path": onnx, "name": name, "language": language, "quality": quality, "source": source,
            "mb": _mb(tree_bytes(onnx) + tree_bytes(meta))}


def _onnx_files(folder: str, depth: int) -> List[str]:
    found = []
    base = folder.rstrip(os.sep).count(os.sep)
    for root, dirs, files in os.walk(folder, followlinks=False):
        if root.count(os.sep) - base >= depth:
            dirs[:] = []
        found += [os.path.join(root, f) for f in sorted(files) if f.endswith(".onnx")]
        dirs.sort()
    return found


def piper_voices(home: Optional[str] = None) -> List[Dict[str, Any]]:
    home = home or os.path.expanduser("~")
    candidates = []
    for folder in speech_note_dirs(home):
        flatpak = os.path.join(".var", "app", "net.mkiol.SpeechNote") in folder
        source = "Speech Note (Flatpak)" if flatpak else "Speech Note"
        for entry in sorted(os.listdir(folder)):
            path = os.path.join(folder, entry)
            if "piper" in entry.lower() and os.path.isdir(path) and not os.path.islink(path):
                candidates += [(p, source) for p in _onnx_files(path, 0)]
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    for folder in (os.path.join(home, ".local", "share", "piper"), os.path.join(data, "piper"),
                   os.path.join(data, "piper-voices")):
        if os.path.isdir(folder):
            candidates += [(p, "Piper") for p in _onnx_files(folder, 3)]
    voices, seen = [], set()
    for path, source in candidates:
        real = os.path.realpath(path)
        if real in seen:
            continue
        voice = _voice(path, source)
        if voice:
            seen.add(real)
            voices.append(voice)
    return sorted(voices, key=lambda v: (v["source"], v["name"]))


def cmd_tts_piper_voices(payload: Dict[str, Any]) -> None:
    _emit({"type": "tts_piper_voices", "voices": piper_voices()})


COMMANDS = {
    "voice_data": cmd_voice_data,
    "voice_data_remove": cmd_voice_data_remove,
    "tts_piper_voices": cmd_tts_piper_voices,
}
