#!/usr/bin/env python3
"""On-demand speech-to-text service for Parakeet and faster-whisper (runs in the voice venv).

Started by systemd socket activation (``kde-ai-stt.socket`` listens on
127.0.0.1:9015 and passes the socket as fd 3), or with ``--listen-fd`` /
``--port`` for tests. It exits after ``--idle-timeout`` seconds without a
request; systemd keeps the socket and starts it again on the next request.
The model is loaded on the first request and reloaded when a request asks
for other settings, so nothing needs a restart. One engine's model is in
memory at a time: a request for the other engine frees it first. No torch.

Loopback only, every request needs the per-user token header
(``X-KDE-AI-Chat-Token``); browsers are refused (any ``Origin`` header).
The widget never talks to it directly: the helper (``stt_transcribe`` and
friends) records a WAV and posts its path here, and the reply carries the
result, so nothing polls.

  GET  /status       {"status", "loaded", "model", "device", "loads", ...}
  POST /transcribe   {"engine": "parakeet", "wav", "model": "/path/x.gguf", "device": auto|cpu|gpu}
                     {"engine": "faster-whisper" (default), "wav", "model", "device", "language", "allow_download"}
  POST /download     {"model"}  (explicit, after the UI showed its size)
  POST /unload       frees the model now
"""
import argparse
import hmac
import json
import os
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stt_whisper import ModelHolder, SttError, check_model, download_faster_whisper  # noqa: E402
from stt_parakeet_model import ParakeetHolder  # noqa: E402

MAX_BODY = 64 * 1024
TOKEN_HEADER = "X-KDE-AI-Chat-Token"
SD_LISTEN_FDS_START = 3


def read_token(path: str) -> str:
    with open(path, encoding="ascii") as f:
        token = f.read().strip()
    if len(token) < 32 or not all(c.isalnum() or c in "_-" for c in token):
        raise ValueError("invalid voice token file")
    return token


def systemd_socket() -> Optional[socket.socket]:
    """The socket systemd passed (LISTEN_FDS for this pid), or None."""
    if os.environ.get("LISTEN_PID") != str(os.getpid()):
        return None
    try:
        count = int(os.environ.get("LISTEN_FDS", "0"))
    except ValueError:
        return None
    for name in ("LISTEN_PID", "LISTEN_FDS", "LISTEN_FDNAMES"):
        os.environ.pop(name, None)
    if count < 1:
        return None
    return socket.socket(fileno=SD_LISTEN_FDS_START)


class SttServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, sock: Optional[socket.socket], port: int, token: str, holder: ModelHolder,
                 idle_timeout: float, downloader=download_faster_whisper, parakeet: Optional[ParakeetHolder] = None):
        self.token = token
        self.holder = holder
        self.parakeet = parakeet or ParakeetHolder()
        self.downloader = downloader
        self.idle_timeout = idle_timeout
        self.active = 0
        self.last_activity = time.monotonic()
        self._activity_lock = threading.Lock()
        if sock is None:
            super().__init__(("127.0.0.1", port), Handler)
        else:
            super().__init__(sock.getsockname()[:2], Handler, bind_and_activate=False)
            self.socket = sock
            self.server_address = sock.getsockname()[:2]

    def begin(self) -> None:
        with self._activity_lock:
            self.active += 1
            self.last_activity = time.monotonic()

    def end(self) -> None:
        with self._activity_lock:
            self.active -= 1
            self.last_activity = time.monotonic()

    # Counted from accept to close, so the idle watch never stops a request.
    def process_request(self, request, client_address) -> None:
        self.begin()
        super().process_request(request, client_address)

    def shutdown_request(self, request) -> None:
        try:
            super().shutdown_request(request)
        finally:
            self.end()

    def holder_for(self, engine: Any):
        """The engine's holder; the other engine's model is unloaded first (one model in memory)."""
        engine = str(engine or "faster-whisper")
        if engine not in ("parakeet", "faster-whisper"):
            raise SttError("Unknown engine: " + engine[:32], "bad_engine")
        wanted, other = (self.parakeet, self.holder) if engine == "parakeet" else (self.holder, self.parakeet)
        other.unload()
        return wanted

    def status(self) -> Dict[str, Any]:
        parakeet = self.parakeet.status()
        status = dict(parakeet, engine="parakeet") if parakeet["loaded"] else dict(self.holder.status(),
                                                                                 engine="faster-whisper")
        if parakeet["status"] != "idle":
            status["status"] = parakeet["status"]
        return status

    def unload_all(self) -> None:
        self.holder.unload()
        self.parakeet.unload()

    def idle_for(self) -> float:
        with self._activity_lock:
            return 0.0 if self.active else time.monotonic() - self.last_activity

    def watch_idle(self) -> None:
        """Shut down after ``idle_timeout`` seconds with no request in flight."""
        step = max(0.05, min(5.0, self.idle_timeout / 10))
        while True:
            time.sleep(step)
            if self.idle_for() >= self.idle_timeout:
                self.shutdown()
                return


class Handler(BaseHTTPRequestHandler):
    server: SttServer
    protocol_version = "HTTP/1.1"

    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(30)

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        pass  # never log requests (paths, results) to the journal

    def _reply(self, status: int, data: Dict[str, Any]) -> None:
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            self.wfile.write(body)
        except OSError:
            pass
        self.close_connection = True

    def _allowed(self) -> bool:
        host = self.headers.get("Host", "").strip().lower()
        host = host[1:host.index("]")] if host.startswith("[") and "]" in host else host.split(":", 1)[0]
        supplied = self.headers.get(TOKEN_HEADER, "")
        return (host in ("127.0.0.1", "localhost", "::1") and "Origin" not in self.headers
                and bool(supplied) and hmac.compare_digest(supplied.encode(), self.server.token.encode()))

    def _handle(self, method: str) -> None:
        if not self._allowed():
            self._reply(403, {"type": "stt_error", "error": "request rejected", "code": "forbidden"})
            return
        if method == "GET":
            if self.path == "/status":
                self._reply(200, dict(self.server.status(), pid=os.getpid(),
                                      idle_timeout=self.server.idle_timeout))
            else:
                self._reply(404, {"type": "stt_error", "error": "not found", "code": "not_found"})
            return
        request = self._body()
        if request is not None:
            self._reply(200, self._route(request))

    def _body(self) -> Optional[Dict[str, Any]]:
        try:
            length = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            length = -1
        if length < 0 or length > MAX_BODY:
            self._reply(413 if length > MAX_BODY else 411, {"type": "stt_error", "error": "bad length", "code": "bad_request"})
            return None
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        except (ValueError, UnicodeError):
            data = None
        if not isinstance(data, dict):
            self._reply(400, {"type": "stt_error", "error": "bad JSON", "code": "bad_request"})
            return None
        return data

    def _route(self, request: Dict[str, Any]) -> Dict[str, Any]:
        try:
            if self.path == "/transcribe":
                return self.server.holder_for(request.get("engine")).transcribe(request)
            if self.path == "/download":
                model = check_model(request.get("model"))
                if os.path.isabs(model):
                    return {"type": "stt_downloaded", "model": model, "path": model}
                return {"type": "stt_downloaded", "model": model, "path": self.server.downloader(model)}
            if self.path == "/unload":
                self.server.unload_all()
                return {"type": "stt_unloaded"}
            return {"type": "stt_error", "error": "unknown endpoint", "code": "not_found"}
        except SttError as e:
            return {"type": "stt_error", "error": str(e), "code": e.code}
        except Exception as e:  # keep the service up; report the failure to the caller
            return {"type": "stt_error", "error": "Speech-to-text failed: " + str(e)[:300], "code": "failed"}

    def do_GET(self) -> None:
        self._handle("GET")

    def do_POST(self) -> None:
        self._handle("POST")


def main(argv=None, holder: Optional[ModelHolder] = None, downloader=download_faster_whisper,
         parakeet: Optional[ParakeetHolder] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--idle-timeout", type=float, default=300.0)
    parser.add_argument("--port", type=int, default=9015, help="without socket activation")
    parser.add_argument("--listen-fd", type=int, default=-1, help="an already listening socket")
    args = parser.parse_args(argv)
    try:
        token = read_token(os.path.expanduser(args.token_file))
    except (OSError, ValueError) as e:
        print("kde-ai-stt: no usable token file: %s" % e, file=sys.stderr, flush=True)
        return 1
    sock = socket.socket(fileno=args.listen_fd) if args.listen_fd >= 0 else systemd_socket()
    server = SttServer(sock, args.port, token, holder or ModelHolder(), max(0.1, args.idle_timeout), downloader,
                       parakeet)
    threading.Thread(target=server.watch_idle, daemon=True).start()
    print("kde-ai-stt: listening on %s:%s (idle exit after %ss)" % (*server.server_address[:2], args.idle_timeout),
          flush=True)
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.unload_all()
        server.server_close()
    print("kde-ai-stt: idle, exiting", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
