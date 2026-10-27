"""Talking to the Speech Note service (https://github.com/mkiol/dsnote) over D-Bus.

Everything except private text goes through ``busctl`` run as a subprocess
(never a shell); ``KDEAICHAT_BUSCTL`` overrides the binary (tests use a fake).
Starting the service is ``flatpak run ... net.mkiol.SpeechNote --service`` or
``dsnote --service`` (``KDEAICHAT_FLATPAK`` / ``KDEAICHAT_DSNOTE`` override).
"""
import json
import os
import select
import shutil
import subprocess
import time
from typing import Any, Dict, Iterator, List, Optional

from kdeaichat.stt_settings import runtime_dir

NAME = "net.mkiol.Speech"
PATH = "/"
IFACE = "org.mkiol.Speech"
FLATPAK_ID = "net.mkiol.SpeechNote"

STATE_NOT_CONFIGURED = 1
STATE_IDLE = 3
NOT_CONFIGURED_GRACE = 3.0  # State 1 can show briefly while models load
CALL_TIMEOUT = 10.0
READY_POLL = 0.2


class SpeechNoteError(Exception):
    """``code`` is one of not_installed, service_failed_to_start, not_configured, timeout, busy, bus_error, ..."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def _tool(env: str, name: str) -> str:
    return os.environ.get(env) or shutil.which(name) or ""


def busctl(args: List[str], timeout: float = CALL_TIMEOUT) -> subprocess.CompletedProcess:
    exe = _tool("KDEAICHAT_BUSCTL", "busctl")
    if not exe:
        raise SpeechNoteError("bus_error", "busctl is not installed")
    try:
        return subprocess.run([exe, "--user", "--json=short"] + args, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise SpeechNoteError("bus_error", "busctl failed: %s" % (getattr(e, "strerror", None) or e)) from None


def _data(result: subprocess.CompletedProcess) -> Any:
    try:
        return json.loads(result.stdout)["data"]
    except (ValueError, KeyError, TypeError):
        raise SpeechNoteError("bus_error", "unexpected reply from the D-Bus tool") from None


def get_property(name: str) -> Any:
    result = busctl(["get-property", NAME, PATH, IFACE, name])
    if result.returncode != 0:
        raise SpeechNoteError("bus_error", "can't read %s: %s" % (name, result.stderr.strip()[:200]))
    return _data(result)


def call(method: str, signature: str = "", *args: Any) -> Any:
    """One method call; the first return value (an int for every method used here)."""
    argv = ["call", NAME, PATH, IFACE, method] + ([signature] + [str(a) for a in args] if signature else [])
    result = busctl(argv)
    if result.returncode != 0:
        raise SpeechNoteError("bus_error", "%s failed: %s" % (method, result.stderr.strip()[:200]))
    data = _data(result)
    return data[0] if isinstance(data, list) and data else data


def state() -> Optional[int]:
    """The service's State, or None when it isn't on the bus."""
    try:
        value = get_property("State")
    except SpeechNoteError:
        return None
    return value if isinstance(value, int) else None


# ---- installation and starting -------------------------------------------------------------

def install_kind() -> str:
    """"native" (dsnote on PATH), "flatpak", or "" when Speech Note is not installed."""
    if _tool("KDEAICHAT_DSNOTE", "dsnote"):
        return "native"
    flatpak = _tool("KDEAICHAT_FLATPAK", "flatpak")
    if flatpak:
        try:
            done = subprocess.run([flatpak, "info", FLATPAK_ID], capture_output=True, timeout=15)
            if done.returncode == 0:
                return "flatpak"
        except (OSError, subprocess.TimeoutExpired):
            pass
    return ""


def launch_argv(kind: str) -> List[str]:
    if kind == "native":
        return [_tool("KDEAICHAT_DSNOTE", "dsnote"), "--service"]
    return [_tool("KDEAICHAT_FLATPAK", "flatpak"), "run", "--own-name=" + NAME, "--command=dsnote", FLATPAK_ID, "--service"]


def log_path() -> str:
    folder = os.path.join(runtime_dir(), "speechnote")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    os.chmod(folder, 0o700)
    return os.path.join(folder, "service.log")


def _launch(kind: str) -> subprocess.Popen:
    fd = os.open(log_path(), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "wb") as log:
            return subprocess.Popen(launch_argv(kind), stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                    start_new_session=True)
    except OSError as e:
        raise SpeechNoteError("service_failed_to_start", "Can't start Speech Note: %s" % (e.strerror or e)) from None


def ensure_ready(timeout: float = 25.0) -> int:
    """Start the service if needed and wait until it is idle (State 3); returns the state.

    Requests sent before State 3 return task -1, so every command that needs
    the service calls this first. A service that is already listening or
    playing counts as ready.
    """
    current = state()
    proc = None
    if current is None:
        kind = install_kind()
        if not kind:
            raise SpeechNoteError("not_installed", "Speech Note is not installed")
        proc = _launch(kind)
    deadline = time.monotonic() + timeout
    seen_on_bus = current is not None
    unconfigured_since = 0.0
    while True:
        if current is not None:
            seen_on_bus = True
            if current >= STATE_IDLE:
                return current
            if current == STATE_NOT_CONFIGURED:
                unconfigured_since = unconfigured_since or time.monotonic()
                if time.monotonic() - unconfigured_since >= NOT_CONFIGURED_GRACE:
                    raise SpeechNoteError("not_configured", "Speech Note has no speech model yet")
            else:
                unconfigured_since = 0.0
        elif proc is not None and proc.poll() is not None and not seen_on_bus:
            raise SpeechNoteError("service_failed_to_start", "Speech Note exited while starting")
        if time.monotonic() >= deadline:
            if seen_on_bus:
                raise SpeechNoteError("timeout", "Speech Note did not become ready in time")
            raise SpeechNoteError("service_failed_to_start", "Speech Note did not start in time")
        time.sleep(READY_POLL)
        current = state()


def refused(task: int) -> SpeechNoteError:
    """The error for a request answered with task < 0 (read State to see why)."""
    now = state()
    if now == STATE_NOT_CONFIGURED:
        return SpeechNoteError("not_configured", "Speech Note has no speech model yet")
    if now == 2:
        return SpeechNoteError("busy", "Speech Note is busy")
    return SpeechNoteError("bus_error", "Speech Note refused the request (task %s)" % task)


# ---- signals ---------------------------------------------------------------------------------

class Monitor:
    """``busctl monitor`` on the service, started before the call that triggers a signal.

    ``ready()`` proves the monitor is attached (busctl prints nothing when it
    is) by calling KeepAliveService and waiting to see that call go by.
    """

    def __init__(self) -> None:
        exe = _tool("KDEAICHAT_BUSCTL", "busctl")
        if not exe:
            raise SpeechNoteError("bus_error", "busctl is not installed")
        try:
            self.proc = subprocess.Popen([exe, "--user", "--json=short", "monitor", NAME], stdin=subprocess.DEVNULL,
                                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError as e:
            raise SpeechNoteError("bus_error", "busctl failed: %s" % (e.strerror or e)) from None
        self._buf = b""

    def __enter__(self) -> "Monitor":
        return self

    def __exit__(self, *exc: Any) -> None:
        self.proc.kill()
        self.proc.wait()
        if self.proc.stdout:
            self.proc.stdout.close()

    def messages(self, timeout: float) -> Iterator[Dict[str, Any]]:
        """Decoded messages until ``timeout`` seconds pass (the iterator then just ends)."""
        deadline = time.monotonic() + timeout
        fd = self.proc.stdout.fileno()  # type: ignore[union-attr]
        while True:
            while b"\n" in self._buf:
                line, self._buf = self._buf.split(b"\n", 1)
                try:
                    message = json.loads(line)
                except ValueError:
                    continue
                if isinstance(message, dict):
                    yield message
            left = deadline - time.monotonic()
            if left <= 0:
                return
            if not select.select([fd], [], [], min(left, 0.5))[0]:
                if self.proc.poll() is not None:
                    return
                continue
            chunk = os.read(fd, 65536)
            if not chunk:
                return
            self._buf += chunk

    def ready(self, timeout: float = 5.0) -> None:
        call("KeepAliveService")
        for m in self.messages(timeout):
            if m.get("member") == "KeepAliveService":
                return
        raise SpeechNoteError("bus_error", "couldn't watch the Speech Note service")


def signal_args(message: Dict[str, Any], member: str) -> Optional[List[Any]]:
    """The arguments of a signal of ours with this name, else None."""
    if message.get("type") == "signal" and message.get("interface") == IFACE and message.get("member") == member:
        payload = message.get("payload") or {}
        data = payload.get("data")
        return data if isinstance(data, list) else []
    return None
