"""Starting the MCP bridge (mcp_bridge_server.py) for the widget.

`mcp_bridge_start` returns the bridge's loopback port and access token,
starting the bridge first if it isn't running (under a file lock, so two
callers never start two). The bridge exits when idle.
"""
import fcntl
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from typing import Any, Dict, Tuple

from kdeaichat import chats, procs

SERVER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mcp_bridge_server.py")
LOG_LIMIT = 1024 * 1024


def _path(name: str) -> str:
    return os.path.join(chats.data_root(), name)


def _read_state() -> Dict[str, Any]:
    try:
        with open(_path("mcp-bridge.json"), encoding="utf-8") as f:
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


def _open_log() -> Tuple[Any, str]:
    """The log, 0600; over ~1 MB it becomes mcp-bridge.log.1 (one old file kept)."""
    path = _path("mcp-bridge.log")
    try:
        if os.path.getsize(path) > LOG_LIMIT:
            os.replace(path, path + ".1")
    except OSError:
        pass
    return os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600), "ab"), path


def ensure_bridge() -> Dict[str, Any]:
    """{status: running|started, port, token}, starting the bridge if needed, or {status: error, message}."""
    os.makedirs(chats.data_root(), mode=0o700, exist_ok=True)
    with open(_path("mcp-bridge.lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = _running()
        if state:
            return {"status": "running", "port": state["port"], "token": state["token"]}
        log, log_path = _open_log()
        with log:
            process = subprocess.Popen([sys.executable, "-I", SERVER, _path("mcp-bridge.json")],
                                       cwd=os.path.expanduser("~"), stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                       start_new_session=True, close_fds=True)
        deadline = time.time() + 10
        while time.time() < deadline:
            state = _read_state()
            if state.get("pid") == process.pid and _healthy(int(state.get("port") or 0)):
                return {"status": "started", "port": state["port"], "token": state["token"]}
            if process.poll() is not None:
                break
            time.sleep(0.05)
        return {"status": "error", "message": f"The MCP bridge didn't start (see {log_path})."}


def cmd_mcp_bridge_start(payload: Dict[str, Any]) -> None:
    print(json.dumps(ensure_bridge()))


def cmd_mcp_bridge_stop(payload: Dict[str, Any]) -> None:
    """Not a helper command (tests call it): signals the bridge only if its pid still runs the recorded command."""
    state = _read_state()
    if not procs.is_ours(state):
        print(json.dumps({"status": "not-running"}))
        return
    os.kill(int(state["pid"]), signal.SIGTERM)
    print(json.dumps({"status": "stopped", "pid": state["pid"]}))


COMMANDS = {
    "mcp_bridge_start": cmd_mcp_bridge_start,
}
