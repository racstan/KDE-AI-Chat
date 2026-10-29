"""Starting the Pi bridge (pi_bridge_server.py) for the widget.

`pi_bridge_start` returns the bridge's loopback port and access token,
starting the bridge first if it isn't running. The bridge only ever runs Pi
processes it started itself and exits when idle. `cmd_pi_bridge_stop` is not a
helper command (the widget never stops the bridge); tests and
scripts/dev-pi-e2e.sh call it directly, and it only signals a bridge whose pid
still runs the recorded command.
"""
import fcntl
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from typing import Any, Dict

from kdeaichat import chats, common, procs

SERVER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pi_bridge_server.py")


def _state_path() -> str:
    return os.path.join(chats.data_root(), "pi-bridge.json")


def _read_state() -> Dict[str, Any]:
    try:
        with open(_state_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _healthy(port: int) -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1.0) as response:
            return response.status == 200
    except OSError:
        return False


def _running() -> Dict[str, Any]:
    state = _read_state()
    if procs.is_ours(state) and _healthy(int(state.get("port") or 0)):
        return state
    return {}


LOG_MAX_BYTES = 1024 * 1024


def ensure_bridge() -> Dict[str, Any]:
    """{status: running|started, port, token}, starting the bridge if needed, or {status: error, message}.

    The check and the start happen under a file lock, so two calls at once (two widgets, a chat and the
    settings page) can't each start a bridge."""
    common.ensure_private_dir(chats.data_root())
    fd = os.open(os.path.join(chats.data_root(), "pi-bridge.lock"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        return _ensure_locked()
    finally:
        os.close(fd)  # also releases the lock; the bridge never inherits it (close_fds, O_CLOEXEC)


def _ensure_locked() -> Dict[str, Any]:
    state = _running()
    if state:
        return {"status": "running", "port": state["port"], "token": state["token"]}
    log_path = os.path.join(chats.data_root(), "pi-bridge.log")
    with common.private_log(log_path, LOG_MAX_BYTES) as log:
        process = subprocess.Popen([sys.executable, "-I", SERVER, _state_path()], cwd=os.path.expanduser("~"),
                                   stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True, close_fds=True)
    deadline = time.time() + 10
    while time.time() < deadline:
        state = _read_state()
        if state.get("pid") == process.pid and _healthy(int(state.get("port") or 0)):
            return {"status": "started", "port": state["port"], "token": state["token"]}
        if process.poll() is not None:
            break
        time.sleep(0.1)
    return {"status": "error", "message": f"The Pi bridge didn't start (see {log_path})."}


def cmd_pi_bridge_start(payload: Dict[str, Any]) -> None:
    print(json.dumps(ensure_bridge()))


def cmd_pi_bridge_stop(payload: Dict[str, Any]) -> None:
    state = _read_state()
    if not procs.is_ours(state):
        print(json.dumps({"status": "not-running"}))
        return
    os.kill(int(state["pid"]), signal.SIGTERM)
    print(json.dumps({"status": "stopped", "pid": state["pid"]}))


COMMANDS = {
    "pi_bridge_start": cmd_pi_bridge_start,
}
