"""Setting up the natural voice (Kokoro) for read aloud, from Settings → Voice.

- ``tts_neural_status {}``: installed?, model found?, running?, GPU, and what
  installing would download (``size``), so the page shows it before the
  Install button is pressed.
- ``tts_neural_install {gpu}``: creates the read-aloud venv
  (``voice/tts_venv_setup.sh``: kokoro-onnx + onnxruntime, no torch) and
  downloads the model and voices (checked against their SHA-256).
- ``tts_neural_remove {}``: stops the service and deletes the venv and model.
- ``tts_neural_stop {}``: stops the service now (read aloud switched off).

The venv is ``~/.local/share/kdeaichat/tts-venv``, the model
``~/.local/share/kdeaichat/tts-models/kokoro``. Nothing is downloaded
except by ``tts_neural_install``. ``KDEAICHAT_TTS_SETUP`` replaces the setup
script and ``KDEAICHAT_TTS_MODEL_URL`` the download base URL (tests).
"""
import glob
import hashlib
import json
import os
import shutil
import subprocess
import urllib.request
from typing import Any, Dict, Optional

from kdeaichat import chats

DEFAULT_VOICE = "af_heart"
BASE_URL = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/"
# name -> (bytes, sha256). fp16 is the default: as natural as the full model, faster on CPU, half the size.
FILES = {
    "kokoro-v1.0.fp16.onnx": (177464787, "c1610a859f3bdea01107e73e50100685af38fff88f5cd8e5c56df109ec880204"),
    "voices-v1.0.bin": (28214398, "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d"),
}
# Also used when already there (the user's own copy): full precision, then 8-bit.
OTHER_MODELS = ["kokoro-v1.0.onnx", "kokoro-v1.0.int8.onnx"]
# Download sizes in MB (manylinux wheels for Python 3.13, checked 2026-10-26): kokoro-onnx,
# onnxruntime 24, numpy 17, espeakng-loader 10 and small packages; for the GPU, onnxruntime-gpu
# 256 and the NVIDIA CUDA 13 / cuDNN 9 wheels 1298 (about 2.3 GB once installed).
PROGRAM_MB = 52
GPU_MB = 1554
TIMEOUT = 3600
_UI_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def venv_dir() -> str:
    return os.path.join(chats.data_root(), "tts-venv")


def models_dir() -> str:
    return os.path.join(chats.data_root(), "tts-models", "kokoro")


def venv_python() -> str:
    for name in ("python3", "python"):
        candidate = os.path.join(venv_dir(), "bin", name)
        if os.path.exists(candidate):
            return candidate
    return ""


def _site_has(name: str) -> bool:
    return bool(glob.glob(os.path.join(venv_dir(), "lib", "python3*", "site-packages", name)))


def packages_installed() -> bool:
    return _site_has("kokoro_onnx") and _site_has("onnxruntime")


def gpu_installed() -> bool:
    return _site_has("onnxruntime_gpu-*") and _site_has("nvidia")


def has_gpu() -> bool:
    return os.path.exists("/proc/driver/nvidia/version") or os.path.exists("/dev/nvidia0")


def model_files() -> Optional[Dict[str, str]]:
    folder = models_dir()
    voices = os.path.join(folder, "voices-v1.0.bin")
    for name in ["kokoro-v1.0.fp16.onnx"] + OTHER_MODELS:
        model = os.path.join(folder, name)
        if os.path.isfile(model) and os.path.isfile(voices):
            return {"model": model, "voices": voices}
    return None


def estimate(gpu: bool = False) -> Dict[str, Any]:
    """What Install downloads now, in MB (what is already there is not counted)."""
    program = 0 if packages_installed() else PROGRAM_MB
    gpu_mb = GPU_MB if gpu and not gpu_installed() else 0
    model = 0 if model_files() else round(sum(size for size, _ in FILES.values()) / 1e6)
    return {"program_mb": program, "gpu_mb": gpu_mb, "model_mb": model, "total_mb": program + gpu_mb + model,
            "gpu": gpu, "approximate": True}


def status() -> Dict[str, Any]:
    from kdeaichat import tts, tts_worker
    files = model_files()
    running = tts_worker.status(tts.out_dir())
    return {"type": "tts_neural_status", "ok": True, "installed": packages_installed() and bool(files),
            "packages": packages_installed(), "model": files["model"] if files else "",
            "gpu": has_gpu(), "gpu_installed": gpu_installed(), "running": bool(running),
            "device": (running or {}).get("device", ""), "venv": venv_dir(), "models": models_dir(),
            "size": estimate(False), "size_gpu": estimate(True)}


def _sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def download_models() -> None:
    folder = models_dir()
    os.makedirs(folder, mode=0o700, exist_ok=True)
    base = os.environ.get("KDEAICHAT_TTS_MODEL_URL") or BASE_URL
    for name, (size, sha) in FILES.items():
        target = os.path.join(folder, name)
        if os.path.isfile(target) and os.path.getsize(target) == size:
            continue
        part = target + ".part"
        with urllib.request.urlopen(base + name, timeout=60) as response, open(part, "wb") as out:
            shutil.copyfileobj(response, out, 1 << 20)
        if _sha256(part) != sha:
            os.remove(part)
            raise RuntimeError("the downloaded %s is damaged (checksum mismatch); try again" % name)
        os.replace(part, target)


def setup_script() -> str:
    return os.environ.get("KDEAICHAT_TTS_SETUP") or os.path.join(_UI_DIR, "voice", "tts_venv_setup.sh")


def install(gpu: bool = False, timeout: float = TIMEOUT) -> Dict[str, Any]:
    folder = venv_dir()
    os.makedirs(os.path.dirname(folder), mode=0o700, exist_ok=True)
    try:
        result = subprocess.run(["bash", setup_script(), folder, "gpu" if gpu else "cpu"], stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=timeout, env=dict(os.environ, NON_INTERACTIVE="1"))
    except subprocess.TimeoutExpired:
        return {"type": "tts_neural_installed", "ok": False, "error": "The install took longer than an hour and was stopped."}
    except OSError as e:
        return {"type": "tts_neural_installed", "ok": False, "error": "Can't run the setup script: %s" % (e.strerror or e)}
    output = (result.stdout + result.stderr).decode("utf-8", "replace").strip().splitlines()
    if result.returncode != 0 or not packages_installed():
        return {"type": "tts_neural_installed", "ok": False, "error": "Installing the natural voice failed.",
                "log": "\n".join(output[-6:])[-1500:]}
    try:
        download_models()
    except (OSError, RuntimeError) as e:
        return {"type": "tts_neural_installed", "ok": False,
                "error": "Downloading the voice model failed: %s" % (getattr(e, "reason", None) or e)}
    return {"type": "tts_neural_installed", "ok": True, "gpu": gpu_installed()}


def remove() -> Dict[str, Any]:
    from kdeaichat import tts, tts_worker
    tts_worker.stop(tts.out_dir())
    removed = []
    for path in (venv_dir(), os.path.dirname(models_dir())):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path, ignore_errors=True)
            removed.append(path)
    return {"type": "tts_neural_removed", "ok": True, "removed": removed}


def cmd_tts_neural_status(payload: Dict[str, Any]) -> None:
    print(json.dumps(status()))


def cmd_tts_neural_install(payload: Dict[str, Any]) -> None:
    print(json.dumps(install(payload.get("gpu") is True)), flush=True)


def cmd_tts_neural_remove(payload: Dict[str, Any]) -> None:
    print(json.dumps(remove()))


def cmd_tts_neural_stop(payload: Dict[str, Any]) -> None:
    from kdeaichat import tts, tts_worker
    print(json.dumps({"ok": True, "stopped": tts_worker.stop(tts.out_dir())}))


COMMANDS = {
    "tts_neural_status": cmd_tts_neural_status,
    "tts_neural_install": cmd_tts_neural_install,
    "tts_neural_remove": cmd_tts_neural_remove,
    "tts_neural_stop": cmd_tts_neural_stop,
}
