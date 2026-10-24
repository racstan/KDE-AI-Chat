"""Starting and stopping the Pi bridge (pi_bridge_server.py) for the widget.

`pi_bridge_start` returns the bridge's loopback port and access token,
starting the bridge first if it isn't running. The bridge only ever runs Pi
processes it started itself, and `pi_bridge_stop` only signals a bridge whose
pid still runs the recorded command.
"""
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from typing import Any, Dict

from kdeaichat import chats, procs

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


def cmd_pi_bridge_start(payload: Dict[str, Any]) -> None:
    state = _running()
    if state:
        print(json.dumps({"status": "running", "port": state["port"], "token": state["token"]}))
        return
    os.makedirs(chats.data_root(), mode=0o700, exist_ok=True)
    log_path = os.path.join(chats.data_root(), "pi-bridge.log")
    with open(log_path, "ab") as log:
        process = subprocess.Popen([sys.executable, "-I", SERVER, _state_path()], cwd=os.path.expanduser("~"),
                                   stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True, close_fds=True)
    deadline = time.time() + 10
    while time.time() < deadline:
        state = _read_state()
        if state.get("pid") == process.pid and _healthy(int(state.get("port") or 0)):
            print(json.dumps({"status": "started", "port": state["port"], "token": state["token"]}))
            return
        if process.poll() is not None:
            break
        time.sleep(0.1)
    print(json.dumps({"status": "error", "message": f"The Pi bridge didn't start (see {log_path})."}))


def cmd_pi_bridge_stop(payload: Dict[str, Any]) -> None:
    state = _read_state()
    if not procs.is_ours(state):
        print(json.dumps({"status": "not-running"}))
        return
    os.kill(int(state["pid"]), signal.SIGTERM)
    print(json.dumps({"status": "stopped", "pid": state["pid"]}))


COMMANDS = {
    "pi_bridge_start": cmd_pi_bridge_start,
    "pi_bridge_stop": cmd_pi_bridge_stop,
}
