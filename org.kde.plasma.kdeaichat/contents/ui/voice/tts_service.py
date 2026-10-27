#!/usr/bin/env python3
"""On-demand natural voice (Kokoro) for read aloud; runs in the read-aloud venv.

The helper (``kdeaichat/tts_worker.py``) starts it when the first sentence is
to be spoken and talks to it over a Unix socket in the private runtime folder
(``$XDG_RUNTIME_DIR/kdeaichat-tts``, mode 0700, so no token is needed). It
loads the model on the first request, keeps it while sentences keep coming
and exits after ``--idle-timeout`` seconds without a request, removing its
socket. No torch: kokoro-onnx with onnxruntime (CPU, or CUDA when the GPU
build is installed).

One JSON line per connection, one JSON line back:
  {"op": "synthesize", "text", "voice", "speed", "lang", "out", "pause_ms",
   "model", "voices"}  -> {"ok": true, "path", "seconds", "synth", "device"}
  {"op": "status"}     -> {"ok": true, "loaded", "device", "pid"}
  {"op": "stop"}       -> {"ok": true}, then exits
``out`` must be a .wav path in ``--out-dir``. ``--fake`` makes a tone instead
of speech (tests).
"""
import argparse
import json
import math
import os
import socket
import socketserver
import struct
import sys
import time
import wave
from typing import Any, Dict, Optional, Tuple

MAX_REQUEST = 256 * 1024
MAX_TEXT = 5000
# Kokoro voice prefix -> its language for the phonemizer.
LANGS = {"a": "en-us", "b": "en-gb", "e": "es", "f": "fr-fr", "h": "hi", "i": "it", "j": "ja",
         "p": "pt-br", "z": "cmn"}


class SpeechError(Exception):
    pass


class KokoroModel:
    """The loaded model, made again when the files change."""

    def __init__(self) -> None:
        self.key: Optional[Tuple[str, str]] = None
        self.kokoro = None
        self.device = ""

    def load(self, model: str, voices: str) -> None:
        if self.key == (model, voices) and self.kokoro is not None:
            return
        for path in (model, voices):
            if not os.path.isfile(path):
                raise SpeechError("the voice model is missing: " + path)
        import onnxruntime as ort
        from kokoro_onnx import Kokoro
        providers = ["CPUExecutionProvider"]
        if "CUDAExecutionProvider" in ort.get_available_providers():
            if hasattr(ort, "preload_dlls"):
                try:
                    ort.preload_dlls()  # CUDA and cuDNN from the venv's nvidia packages
                except Exception:
                    pass
            providers.insert(0, "CUDAExecutionProvider")
        session = ort.InferenceSession(model, providers=providers)
        self.kokoro = Kokoro.from_session(session, voices)
        self.device = "gpu" if session.get_providers()[0] == "CUDAExecutionProvider" else "cpu"
        self.key = (model, voices)

    def synthesize(self, text: str, voice: str, speed: float, lang: str) -> Tuple[Any, int]:
        samples, rate = self.kokoro.create(text, voice=voice, speed=speed, lang=lang)
        return samples, int(rate)

    def unload(self) -> None:
        self.kokoro = None
        self.key = None


class FakeModel(KokoroModel):
    """A quiet tone, 60 ms per character (tests)."""

    def load(self, model: str, voices: str) -> None:
        self.key, self.kokoro, self.device = (model, voices), True, "cpu"

    def synthesize(self, text: str, voice: str, speed: float, lang: str) -> Tuple[Any, int]:
        rate = 24000
        count = int(rate * 0.06 * len(text) / max(0.5, speed))
        return [0.3 * math.sin(2 * math.pi * 220 * i / rate) for i in range(count)], rate


def _pcm(samples) -> bytes:
    """16-bit little-endian PCM (numpy in the venv; plain Python for the fake model)."""
    try:
        import numpy as np
        return (np.clip(np.asarray(samples, dtype="float32"), -1, 1) * 32767).astype("<i2").tobytes()
    except ImportError:
        return b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)


def write_wav(path: str, samples, rate: int, pause_ms: int) -> float:
    """Mono WAV with ``pause_ms`` (0-2000) of silence at the end; returns its length in seconds."""
    pcm = _pcm(samples) + b"\0\0" * int(rate * max(0, min(2000, pause_ms)) / 1000)
    tmp = path + ".part"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)
    os.replace(tmp, path)
    return len(pcm) / 2 / rate


class Server(socketserver.UnixStreamServer):
    def __init__(self, path: str, out_dir: str, model: KokoroModel, idle_timeout: float):
        self.out_dir = os.path.realpath(out_dir)
        self.model = model
        self.idle_timeout = idle_timeout
        self.last_activity = time.monotonic()
        self.stopping = False
        self.timeout = min(1.0, idle_timeout)
        super().__init__(path, Handler)

    def handle_timeout(self) -> None:
        pass

    def run(self) -> None:
        while not self.stopping and time.monotonic() - self.last_activity < self.idle_timeout:
            self.handle_request()

    def synthesize(self, request: Dict[str, Any]) -> Dict[str, Any]:
        text = str(request.get("text") or "").strip()[:MAX_TEXT]
        out = os.path.realpath(str(request.get("out") or ""))
        if not text:
            raise SpeechError("nothing to read")
        if os.path.dirname(out) != self.out_dir or not out.endswith(".wav"):
            raise SpeechError("the output file is not in the speech folder")
        voice = str(request.get("voice") or "af_heart")
        if not voice.replace("_", "").isalnum():
            raise SpeechError("unknown voice")
        try:
            speed = max(0.5, min(2.0, float(request.get("speed") or 1)))
        except (TypeError, ValueError):
            speed = 1.0
        lang = str(request.get("lang") or LANGS.get(voice[:1], "en-us"))
        started = time.monotonic()
        self.model.load(str(request.get("model") or ""), str(request.get("voices") or ""))
        samples, rate = self.model.synthesize(text, voice, speed, lang)
        try:
            pause = int(request.get("pause_ms") or 0)
        except (TypeError, ValueError):
            pause = 0
        seconds = write_wav(out, samples, rate, pause)
        return {"ok": True, "path": out, "seconds": round(seconds, 3),
                "synth": round(time.monotonic() - started, 3), "device": self.model.device}


class Handler(socketserver.StreamRequestHandler):
    server: Server

    def handle(self) -> None:
        self.connection.settimeout(30)
        try:
            line = self.rfile.readline(MAX_REQUEST + 1)
            request = json.loads(line.decode("utf-8")) if line and len(line) <= MAX_REQUEST else None
        except (OSError, ValueError, UnicodeError):
            request = None
        if not isinstance(request, dict):
            self._send({"ok": False, "error": "bad request"})
            return
        op = request.get("op")
        try:
            if op == "synthesize":
                reply = self.server.synthesize(request)
            elif op == "status":
                reply = {"ok": True, "loaded": self.server.model.key is not None,
                         "device": self.server.model.device, "pid": os.getpid()}
            elif op == "stop":
                self.server.stopping = True
                reply = {"ok": True}
            else:
                reply = {"ok": False, "error": "unknown request"}
        except SpeechError as e:
            reply = {"ok": False, "error": str(e)}
        except Exception as e:  # keep serving; the caller shows the reason
            reply = {"ok": False, "error": "the natural voice failed: " + str(e)[:300]}
        self.server.last_activity = time.monotonic()
        self._send(reply)

    def _send(self, data: Dict[str, Any]) -> None:
        try:
            self.wfile.write((json.dumps(data) + "\n").encode("utf-8"))
        except OSError:
            pass


def main(argv=None, model: Optional[KokoroModel] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--socket", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--idle-timeout", type=float, default=120.0)
    parser.add_argument("--fake", action="store_true", help="a tone instead of speech (tests)")
    args = parser.parse_args(argv)
    folder = os.path.dirname(os.path.abspath(args.socket))
    if os.stat(folder).st_mode & 0o077:
        print("kde-ai-tts: the socket folder must be private (0700)", file=sys.stderr, flush=True)
        return 1
    if os.path.exists(args.socket):
        probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            probe.connect(args.socket)
            print("kde-ai-tts: already running", file=sys.stderr, flush=True)
            return 0
        except OSError:
            os.unlink(args.socket)  # left by a copy that crashed
        finally:
            probe.close()
    server = Server(args.socket, args.out_dir, model or (FakeModel() if args.fake else KokoroModel()),
                    max(0.1, args.idle_timeout))
    print("kde-ai-tts: listening (idle exit after %ss)" % args.idle_timeout, flush=True)
    try:
        server.run()
    finally:
        server.model.unload()
        server.server_close()
        try:
            os.unlink(args.socket)
        except OSError:
            pass
    print("kde-ai-tts: idle, exiting", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
