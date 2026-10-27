"""Parakeet model handling for the on-demand STT service (runs in the voice venv).

Runs NVIDIA Parakeet Unified EN 0.6B as a GGUF file (the one Handy uses)
with transcribe.cpp's Python binding (``transcribe-cpp`` +
``transcribe-cpp-native``: ggml, no torch, no numpy needed). The graphics
card is used through Vulkan; when it fails, the CPU takes over and the reply
says so. The model is loaded on the first request and kept until the
service exits (idle) or another engine or file is asked for.
``load_model`` is injectable so tests can use a fake model without the venv.
"""
import array
import gc
import os
import sys
import threading
import wave
from typing import Any, Callable, Dict, Optional, Tuple

from stt_whisper import SttError, check_wav

DEVICES = ("auto", "cpu", "gpu")
MAX_MODEL_BYTES = 8 * 1024 ** 3
RATE = 16000


def check_model(value: Any) -> str:
    path = os.path.normpath(str(value or ""))
    if not os.path.isabs(path) or "\x00" in path or not path.endswith(".gguf"):
        raise SttError("The Parakeet model must be a .gguf file path", "bad_model")
    if not os.path.isfile(path):
        raise SttError("The Parakeet model file is missing: " + path, "model_missing")
    if os.path.getsize(path) > MAX_MODEL_BYTES:
        raise SttError("The Parakeet model file is too big", "bad_model")
    return path


def check_device(value: Any) -> str:
    device = str(value or "auto")
    if device == "cuda":
        device = "gpu"
    if device not in DEVICES:
        raise SttError("Unknown device: " + device[:16], "bad_device")
    return device


def read_pcm(path: str) -> "array.array":
    """A PCM WAV as 16 kHz mono float32 samples (array('f')): stereo is mixed down and
    other rates are resampled linearly. Dictation records 16 kHz mono already."""
    try:
        with wave.open(path, "rb") as w:
            rate, width, channels = w.getframerate(), w.getsampwidth(), w.getnchannels()
            frames = w.readframes(w.getnframes())
    except (OSError, EOFError, wave.Error) as e:
        raise SttError("The recording is not a PCM WAV file: %s" % e, "bad_wav") from None
    if width != 2 or channels not in (1, 2) or rate < 4000:
        raise SttError("The recording must be 16-bit PCM mono or stereo", "bad_wav")
    ints = array.array("h")
    ints.frombytes(frames[: len(frames) - len(frames) % 2])
    if channels == 2:
        ints = array.array("h", ((ints[i] + ints[i + 1]) // 2 for i in range(0, len(ints) - 1, 2)))
    samples = array.array("f", (x / 32768.0 for x in ints))
    if rate == RATE or not samples:
        return samples
    step = rate / RATE
    count = int(len(samples) / step)
    last = len(samples) - 1
    out = array.array("f", bytes(4 * count))
    for i in range(count):
        pos = i * step
        j = int(pos)
        frac = pos - j
        out[i] = samples[j] * (1 - frac) + samples[min(j + 1, last)] * frac
    return out


_quiet = False


def _log_errors_only(level: int, message: str) -> None:
    if level == 3:
        sys.stderr.write("kde-ai-stt: " + str(message).rstrip()[:300] + "\n")


def load_transcribe_cpp(path: str, device: str) -> Any:
    global _quiet
    import transcribe_cpp  # type: ignore
    if not _quiet:  # its per-request info lines would fill the journal
        _quiet = True
        transcribe_cpp.set_log_callback(_log_errors_only)
    backend = {"gpu": "vulkan"}.get(device, device)
    if backend == "vulkan" and not transcribe_cpp.backend_available("vulkan"):
        raise RuntimeError("no Vulkan graphics card")
    return transcribe_cpp.Model(path, backend=backend)


Loader = Callable[[str, str], Any]


class ParakeetHolder:
    """One Parakeet model at a time; requests are serialized."""

    def __init__(self, loader: Loader = load_transcribe_cpp):
        self._loader = loader
        self._lock = threading.Lock()
        self.model: Any = None
        self.session: Any = None
        self.key: Optional[Tuple[str, str]] = None
        self.loads = 0
        self.state = "idle"
        self.gpu_broken = ""  # why the graphics card failed in this process; later requests use the CPU

    def _backend(self) -> str:
        try:
            return str(self.model.backend)
        except Exception:
            return ""

    def _ensure(self, path: str, device: str) -> Dict[str, Any]:
        note = ""
        if device != "cpu" and self.gpu_broken:
            device, note = "cpu", "The graphics card failed earlier (%s); using the CPU" % self.gpu_broken
        if self.key != (path, device) or self.model is None:
            self.unload_locked()
            self.state = "loading"
            try:
                self.model = self._loader(path, device)
                self.session = self.model.session()
            except Exception as e:
                self.unload_locked()
                if device == "cpu":
                    raise SttError("Loading the Parakeet model failed: " + str(e)[:300], "load_failed") from None
                self.gpu_broken = str(e)[:160]
                return dict(self._ensure(path, "cpu"),
                            note="The graphics card failed (%s); using the CPU" % self.gpu_broken)
            self.key = (path, device)
            self.loads += 1
        return {"device": device, "note": note}

    def _run(self, pcm: Any) -> str:
        self.state = "transcribing"
        return str(self.session.run(pcm).text or "").strip()

    def transcribe(self, request: Dict[str, Any]) -> Dict[str, Any]:
        wav = check_wav(request.get("wav"))
        path = check_model(request.get("model"))
        device = check_device(request.get("device"))
        pcm = read_pcm(wav)
        if len(pcm) < RATE // 10:
            return {"type": "stt_result", "text": "", "engine": "parakeet", "model": os.path.basename(path),
                    "device": device, "language": "en"}
        with self._lock:
            try:
                info = self._ensure(path, device)
                try:
                    text = self._run(pcm)
                except Exception as e:
                    if self.key is None or self.key[1] == "cpu":
                        raise SttError("Transcription failed: " + str(e)[:300], "failed") from None
                    self.gpu_broken = str(e)[:160]
                    self.unload_locked()
                    info = dict(self._ensure(path, "cpu"),
                                note="The graphics card failed (%s); using the CPU" % self.gpu_broken)
                    text = self._run(pcm)
            finally:
                self.state = "idle"
        reply = {"type": "stt_result", "text": text, "engine": "parakeet", "model": os.path.basename(path),
                 "device": info["device"], "backend": self._backend(), "language": "en"}
        if info["note"]:
            reply["note"] = info["note"]
        return reply

    def unload_locked(self) -> None:
        for name in ("session", "model"):
            obj = getattr(self, name)
            setattr(self, name, None)
            try:
                if obj is not None and hasattr(obj, "close"):
                    obj.close()
            except Exception:
                pass
        self.key = None
        gc.collect()

    def unload(self) -> None:
        with self._lock:
            self.unload_locked()

    def status(self) -> Dict[str, Any]:
        return {"status": self.state, "loaded": self.model is not None, "loads": self.loads,
                "model": self.key[0] if self.key else "", "device": self.key[1] if self.key else ""}
