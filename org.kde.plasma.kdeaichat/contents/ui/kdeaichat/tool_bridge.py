"""Starting the tool bridge (tool_bridge_server.py) for the widget, and the web-search keys.

`tools_bridge_start` returns the bridge's loopback port and access token,
starting the bridge first if it isn't running. The bridge only ever runs MCP
servers it started itself and exits when idle. `cmd_tools_bridge_stop` is not
a helper command (the widget never stops the bridge); tests call it directly,
and it only signals a bridge whose pid still runs the recorded command.

`tools_key_set` / `tools_key_status` keep the Brave and Tavily search keys in
KWallet (folder "KDEAIChat-tools"). The key is never printed or logged.
"""
import json
import os
import re
import signal
import subprocess
import sys
import time
import urllib.request
from typing import Any, Dict

from kdeaichat import chats, procs, schedule_wallet

SERVER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tool_bridge_server.py")
KEY_NAMES = ("brave", "tavily")


def _state_path() -> str:
    return os.path.join(chats.data_root(), "tool-bridge.json")


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


def ensure_bridge() -> Dict[str, Any]:
    """{status: running|started, port, token}, starting the bridge if needed, or {status: error, message}."""
    state = _running()
    if state:
        return {"status": "running", "port": state["port"], "token": state["token"]}
    os.makedirs(chats.data_root(), mode=0o700, exist_ok=True)
    log_path = os.path.join(chats.data_root(), "tool-bridge.log")
    with open(log_path, "ab") as log:
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
    return {"status": "error", "message": f"The tool bridge didn't start (see {log_path})."}


def cmd_tools_bridge_start(payload: Dict[str, Any]) -> None:
    print(json.dumps(ensure_bridge()))


def cmd_tools_bridge_stop(payload: Dict[str, Any]) -> None:
    state = _read_state()
    if not procs.is_ours(state):
        print(json.dumps({"status": "not-running"}))
        return
    os.kill(int(state["pid"]), signal.SIGTERM)
    print(json.dumps({"status": "stopped", "pid": state["pid"]}))


def cmd_tools_key_set(payload: Dict[str, Any]) -> None:
    """Stores (or, with an empty key, removes) a search key: {name: brave|tavily, key}."""
    name = str(payload.get("name") or "")
    key = payload.get("key")
    key = key.strip() if isinstance(key, str) else ""
    if name not in KEY_NAMES:
        print(json.dumps({"status": "error", "message": "Unknown search service."}))
        return
    if len(key) > 512 or re.search(r"[\x00-\x1f\x7f]", key):
        print(json.dumps({"status": "error", "message": "That key doesn't look valid."}))
        return
    try:
        done = schedule_wallet.write_key(name, key, folder=schedule_wallet.tools_folder())
    except schedule_wallet.WalletUnavailable as exc:
        print(json.dumps({"status": "error", "message": f"The key could not be saved ({exc.reason})."}))
        return
    if not done:
        print(json.dumps({"status": "error", "message": "KWallet refused to save the key."}))
    else:
        print(json.dumps({"status": "saved" if key else "removed", "message": ""}))


def cmd_tools_key_status(payload: Dict[str, Any]) -> None:
    """{brave: bool, tavily: bool}: whether a key is saved (never the key)."""
    status = {}
    for name in KEY_NAMES:
        try:
            status[name] = bool(schedule_wallet.read_key(name, folder=schedule_wallet.tools_folder()))
        except schedule_wallet.WalletUnavailable:
            status[name] = False
    print(json.dumps(status))


COMMANDS = {
    "tools_bridge_start": cmd_tools_bridge_start,
    "tools_key_set": cmd_tools_key_set,
    "tools_key_status": cmd_tools_key_status,
}
