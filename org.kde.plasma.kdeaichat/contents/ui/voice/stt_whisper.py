"""faster-whisper model handling for the on-demand STT service (runs in the voice venv).

No torch: CUDA is detected with ``ctranslate2.get_cuda_device_count()``.
The model is loaded on the first request and loaded again only when the
requested settings (model, device, compute type) differ from the loaded one.
``load_model`` is injectable so tests can use a fake model without the venv.
"""
import gc
import glob
import os
import re
import sys
import threading
from typing import Any, Callable, Dict, Optional, Tuple

# The names faster-whisper downloads by itself (Systran / distil-whisper repos).
MODEL_NAMES = (
    "tiny", "tiny.en", "base", "base.en", "small", "small.en", "medium", "medium.en",
    "large-v1", "large-v2", "large-v3", "large", "large-v3-turbo", "turbo",
    "distil-small.en", "distil-medium.en", "distil-large-v2", "distil-large-v3", "distil-large-v3.5",
)
DEVICES = ("auto", "cpu", "cuda")
_LANGUAGE = re.compile(r"^(auto|[a-z]{2,3}(-[A-Za-z]{2,4})?)$")
MAX_WAV_BYTES = 200 * 1024 * 1024


class SttError(Exception):
    """A request the service can't handle; ``code`` is machine-readable for the UI."""

    def __init__(self, message: str, code: str = "error"):
        super().__init__(message)
        self.code = code


def check_model(value: Any) -> str:
    """A known model name, or an absolute CTranslate2 model folder (with model.bin)."""
    model = str(value or "small").strip()
    if model in MODEL_NAMES:
        return model
    path = os.path.normpath(os.path.expanduser(model))
    if not os.path.isabs(path) or "\x00" in path or len(path) > 4096:
        raise SttError("Unknown speech model: " + model[:80], "bad_model")
    if os.path.isfile(path):
        path = os.path.dirname(path)
    if not os.path.isfile(os.path.join(path, "model.bin")):
        raise SttError("This folder has no CTranslate2 model (model.bin): " + path, "bad_model")
    return path


def check_language(value: Any) -> Optional[str]:
    language = str(value or "auto").strip()
    if not _LANGUAGE.match(language):
        raise SttError("Unknown language code: " + language[:16], "bad_language")
    return None if language == "auto" else language


def check_wav(value: Any) -> str:
    path = str(value or "")
    if not path or not os.path.isabs(path) or "\x00" in path:
        raise SttError("A WAV file path is required", "bad_wav")
    try:
        st = os.stat(path)
    except OSError:
        raise SttError("The recording is missing", "bad_wav") from None
    if not os.path.isfile(path) or st.st_uid != os.getuid():
        raise SttError("The recording is not a private file", "bad_wav")
    if st.st_size > MAX_WAV_BYTES:
        raise SttError("The recording is too long", "bad_wav")
    return path


def cuda_device_count() -> int:
    try:
        import ctranslate2  # type: ignore
        return int(ctranslate2.get_cuda_device_count())
    except Exception:
        return 0


def resolve_device(requested: Any, count: Callable[[], int] = cuda_device_count) -> str:
    device = str(requested or "auto")
    if device not in DEVICES:
        raise SttError("Unknown device: " + device[:16], "bad_device")
    if device == "auto":
        return "cuda" if count() > 0 else "cpu"
    return device


_nvidia_loaded = False


def preload_nvidia_libs() -> None:
    """Load cuBLAS/cuDNN from pip's nvidia-* packages in the venv, if present."""
    global _nvidia_loaded
    if _nvidia_loaded:
        return
    _nvidia_loaded = True
    import ctypes
    for folder in sys.path:
        for lib in sorted(glob.glob(os.path.join(folder, "nvidia", "*", "lib", "*.so*"))):
            try:
                ctypes.CDLL(lib)
            except OSError:
                pass


def load_faster_whisper(model: str, device: str, compute_type: str, allow_download: bool) -> Any:
    if device == "cuda":
        preload_nvidia_libs()
    from faster_whisper import WhisperModel  # type: ignore
    path = model
    if not os.path.isabs(model):
        from faster_whisper import download_model  # type: ignore
        try:
            path = download_model(model, local_files_only=not allow_download)
        except Exception:
            if not allow_download:
                raise SttError("The speech model '%s' is not downloaded yet" % model, "model_missing") from None
            raise
    return WhisperModel(path, device=device, compute_type=compute_type)


def download_faster_whisper(model: str) -> str:
    from faster_whisper import download_model  # type: ignore
    return str(download_model(model))


def read_pcm16k(path: str) -> Any:
    """A 16 kHz 16-bit PCM WAV (what dictation records) as float32 samples, without PyAV;
    any other file is returned as its path for faster-whisper to decode."""
    try:
        import wave
        import numpy  # type: ignore
        with wave.open(path, "rb") as w:
            if w.getframerate() != 16000 or w.getsampwidth() != 2 or w.getnchannels() not in (1, 2):
                return path
            channels = w.getnchannels()
            frames = w.readframes(w.getnframes())
        samples = numpy.frombuffer(frames, dtype="<i2").astype(numpy.float32) / 32768.0
        return samples.reshape(-1, channels).mean(axis=1) if channels == 2 else samples
    except Exception:
        return path


Loader = Callable[[str, str, str, bool], Any]


class ModelHolder:
    """One loaded model at a time; requests are serialized."""

    def __init__(self, loader: Loader = load_faster_whisper, cuda_count: Callable[[], int] = cuda_device_count):
        self._loader = loader
        self._cuda_count = cuda_count
        self._lock = threading.Lock()
        self.model: Any = None
        self.key: Optional[Tuple[str, str, str]] = None
        self.loads = 0
        self.state = "idle"
        self.cuda_broken = ""  # why CUDA failed in this process; later requests use the CPU

    def _ensure(self, model: str, requested_device: str, allow_download: bool) -> Dict[str, Any]:
        device = resolve_device(requested_device, self._cuda_count)
        note = ""
        if device == "cuda" and self.cuda_broken:
            device, note = "cpu", "CUDA failed earlier (%s); using the CPU" % self.cuda_broken
        compute = "float16" if device == "cuda" else "int8"
        if self.key != (model, device, compute) or self.model is None:
            self.unload_locked()
            self.state = "loading"
            try:
                self.model = self._loader(model, device, compute, allow_download)
            except SttError:
                raise
            except Exception as e:
                if device != "cuda":
                    raise SttError("Loading the speech model failed: " + str(e)[:300], "load_failed") from None
                # CUDA missing or broken: fall back to the CPU and say so.
                self.cuda_broken = str(e)[:160]
                return self._ensure(model, "cpu", allow_download) | {
                    "note": "CUDA failed (%s); using the CPU" % self.cuda_broken}
            self.key = (model, device, compute)
            self.loads += 1
        return {"device": device, "note": note}

    def _run(self, wav: str, language: Optional[str]) -> Tuple[str, Any]:
        self.state = "transcribing"
        segments, details = self.model.transcribe(read_pcm16k(wav), language=language, beam_size=5, vad_filter=True)
        return " ".join(str(seg.text).strip() for seg in segments).strip(), details

    def transcribe(self, request: Dict[str, Any]) -> Dict[str, Any]:
        wav = check_wav(request.get("wav"))
        model = check_model(request.get("model"))
        language = check_language(request.get("language"))
        allow_download = request.get("allow_download") is True
        with self._lock:
            try:
                info = self._ensure(model, request.get("device") or "auto", allow_download)
                try:
                    text, details = self._run(wav, language)
                except Exception as e:
                    if not self.key or self.key[1] != "cuda":
                        raise SttError("Transcription failed: " + str(e)[:300], "failed") from None
                    # The model loaded on the GPU but CUDA libraries (cuBLAS/cuDNN) are missing.
                    self.cuda_broken = str(e)[:160]
                    self.unload_locked()
                    info = dict(self._ensure(model, "cpu", allow_download),
                                note="CUDA failed (%s); using the CPU" % self.cuda_broken)
                    text, details = self._run(wav, language)
            finally:
                self.state = "idle"
        reply = {"type": "stt_result", "text": text, "engine": "faster-whisper", "model": model,
                 "device": info["device"], "language": getattr(details, "language", language or "")}
        if info["note"]:
            reply["note"] = info["note"]
        return reply

    def unload_locked(self) -> None:
        if self.model is not None:
            self.model = None
            self.key = None
            gc.collect()

    def unload(self) -> None:
        with self._lock:
            self.unload_locked()

    def status(self) -> Dict[str, Any]:
        return {"status": self.state, "loaded": self.model is not None, "loads": self.loads,
                "model": self.key[0] if self.key else "", "device": self.key[1] if self.key else ""}
