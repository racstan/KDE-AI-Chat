"""What installing faster-whisper would download, shown before anything is downloaded.

``estimate`` adds up the Python packages still missing from the voice venv
(approximate manylinux wheel sizes, checked 2026-10) and the chosen model,
unless it is already in the HuggingFace cache or is the user's own folder.
GPU support (cuBLAS + cuDNN wheels for CTranslate2) is counted only when an
NVIDIA GPU is detected, or when the user forces it.
"""
import glob
import os
from typing import Any, Dict, List, Optional

# Download sizes in MB. faster-whisper needs no torch, spacy or transformers.
PACKAGES = {
    "faster-whisper": 1, "ctranslate2": 40, "onnxruntime": 24, "av": 40, "tokenizers": 4,
    "huggingface-hub": 1, "hf-xet": 4, "numpy": 17, "other small packages": 4,
}
GPU_PACKAGES = {"nvidia-cublas-cu12": 581, "nvidia-cudnn-cu12": 766}
# Where faster-whisper downloads each model name from, and its download size in MB.
MODELS = {
    "tiny": ("Systran/faster-whisper-tiny", 75), "tiny.en": ("Systran/faster-whisper-tiny.en", 75),
    "base": ("Systran/faster-whisper-base", 145), "base.en": ("Systran/faster-whisper-base.en", 145),
    "small": ("Systran/faster-whisper-small", 484), "small.en": ("Systran/faster-whisper-small.en", 484),
    "medium": ("Systran/faster-whisper-medium", 1530), "medium.en": ("Systran/faster-whisper-medium.en", 1530),
    "large-v1": ("Systran/faster-whisper-large-v1", 3090), "large-v2": ("Systran/faster-whisper-large-v2", 3090),
    "large-v3": ("Systran/faster-whisper-large-v3", 3090), "large": ("Systran/faster-whisper-large-v3", 3090),
    "large-v3-turbo": ("mobiuslabsgmbh/faster-whisper-large-v3-turbo", 1620),
    "turbo": ("mobiuslabsgmbh/faster-whisper-large-v3-turbo", 1620),
    "distil-small.en": ("Systran/faster-distil-whisper-small.en", 337),
    "distil-medium.en": ("Systran/faster-distil-whisper-medium.en", 789),
    "distil-large-v2": ("Systran/faster-distil-whisper-large-v2", 1510),
    "distil-large-v3": ("Systran/faster-distil-whisper-large-v3", 1510),
    "distil-large-v3.5": ("distil-whisper/distil-large-v3.5-ct2", 1510),
}
_IMPORT_NAMES = {"faster-whisper": "faster_whisper", "huggingface-hub": "huggingface_hub", "hf-xet": "hf_xet",
                 "nvidia-cublas-cu12": "nvidia/cublas", "nvidia-cudnn-cu12": "nvidia/cudnn"}


def hf_cache() -> str:
    if os.environ.get("HF_HUB_CACHE"):
        return os.environ["HF_HUB_CACHE"]
    home = os.environ.get("HF_HOME") or os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                                                     "huggingface")
    return os.path.join(home, "hub")


def cached_model(name: str, cache: Optional[str] = None) -> str:
    """The snapshot folder of a downloaded model (with model.bin), or ""."""
    if name not in MODELS:
        return ""
    repo = "models--" + MODELS[name][0].replace("/", "--")
    for snapshot in sorted(glob.glob(os.path.join(cache or hf_cache(), repo, "snapshots", "*"))):
        if os.path.isfile(os.path.join(snapshot, "model.bin")):
            return snapshot
    return ""


def cached_models(cache: Optional[str] = None) -> List[str]:
    return [name for name in MODELS if cached_model(name, cache)]


def installed(venv: str, package: str) -> bool:
    if package == "other small packages":
        return bool(glob.glob(os.path.join(venv, "lib", "python3*", "site-packages", "tqdm")))
    name = _IMPORT_NAMES.get(package, package.replace("-", "_"))
    return bool(glob.glob(os.path.join(venv, "lib", "python3*", "site-packages", name)))


def estimate(model: str, venv: str, gpu: Any = "auto", has_gpu: bool = False,
             cache: Optional[str] = None) -> Dict[str, Any]:
    use_gpu = has_gpu if gpu in ("auto", None, "") else gpu in (True, "cuda", "gpu")
    wanted = dict(PACKAGES, **(GPU_PACKAGES if use_gpu else {}))
    items = [{"name": name, "mb": mb, "kind": "package"} for name, mb in wanted.items() if not installed(venv, name)]
    model_mb, model_note = 0, ""
    if model in MODELS:
        found = cached_model(model, cache)
        if found:
            model_note = "already downloaded: " + found
        else:
            model_mb = MODELS[model][1]
            items.append({"name": "model " + model, "mb": model_mb, "kind": "model", "from": MODELS[model][0],
                          "to": hf_cache()})
    else:
        model_note = "your own model folder"
    packages_mb = sum(i["mb"] for i in items if i["kind"] == "package")
    return {"type": "stt_setup_size", "gpu": use_gpu, "packages_mb": packages_mb, "model_mb": model_mb,
            "total_mb": packages_mb + model_mb, "items": items, "model_note": model_note, "venv": venv,
            "approximate": True}
