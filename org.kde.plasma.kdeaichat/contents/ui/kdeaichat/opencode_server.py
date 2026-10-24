"""Starting and stopping an `opencode serve` for the widget.

The widget only ever stops a server it started itself: the process id and
the exact command are recorded when starting, and stopping checks both
before sending SIGTERM. A server the user runs on their own is left alone
(older versions ran `pkill -f opencode`, which also killed terminal sessions).
"""
import json
import os
import shutil
import signal
import subprocess
import time
import urllib.request
from typing import Any, Dict, Optional

from kdeaichat import chats, procs


def _state_path() -> str:
    return os.path.join(chats.data_root(), "opencode-server.json")


def find_binary() -> Optional[str]:
    found = shutil.which("opencode")
    if found:
        return found
    for candidate in ("~/.opencode/bin/opencode", "~/.npm-global/bin/opencode", "~/.local/bin/opencode", "~/.bun/bin/opencode"):
        path = os.path.expanduser(candidate)
        if os.access(path, os.X_OK):
            return path
    return None


def _port(payload: Dict[str, Any]) -> int:
    port = int(payload.get("port", 4096))
    if not 1024 <= port <= 65535:
        raise ValueError("port must be between 1024 and 65535")
    return port


def healthy(port: int, timeout: float = 1.5) -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/global/health", timeout=timeout) as response:
            return 200 <= response.status < 300
    except OSError:
        return False


def _read_state() -> Dict[str, Any]:
    try:
        with open(_state_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def cmd_opencode_server_status(payload: Dict[str, Any]) -> None:
    port = _port(payload)
    state = _read_state()
    print(json.dumps({"running": healthy(port), "ours": procs.is_ours(state) and state.get("port") == port,
                      "binary": find_binary() or ""}))


def cmd_opencode_server_start(payload: Dict[str, Any]) -> None:
    """Starts `opencode serve` on 127.0.0.1:<port> unless something already answers there."""
    port = _port(payload)
    if healthy(port):
        print(json.dumps({"status": "already-running", "ours": procs.is_ours(_read_state())}))
        return
    binary = find_binary()
    if not binary:
        print(json.dumps({"status": "error", "message": "OpenCode isn't installed (no `opencode` command found)."}))
        return
    directory = os.path.expanduser(str(payload.get("directory") or "~"))
    if not os.path.isdir(directory):
        directory = os.path.expanduser("~")
    argv = [binary, "serve", "--port", str(port), "--hostname", "127.0.0.1"]
    log_path = os.path.join(chats.data_root(), "opencode-server.log")
    os.makedirs(chats.data_root(), mode=0o700, exist_ok=True)
    with open(log_path, "ab") as log:
        process = subprocess.Popen(argv, cwd=directory, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                   start_new_session=True, close_fds=True)
    with open(_state_path(), "w", encoding="utf-8") as f:
        json.dump({"pid": process.pid, "port": port, "argv": argv}, f)
    os.chmod(_state_path(), 0o600)
    deadline = time.time() + float(payload.get("wait", 20))
    while time.time() < deadline:
        if process.poll() is not None:
            print(json.dumps({"status": "error", "message": f"OpenCode exited right away (see {log_path})."}))
            return
        if healthy(port, timeout=1.0):
            print(json.dumps({"status": "started", "pid": process.pid}))
            return
        time.sleep(0.3)
    print(json.dumps({"status": "error", "message": f"OpenCode didn't start answering on port {port} (see {log_path})."}))


def cmd_opencode_server_stop(payload: Dict[str, Any]) -> None:
    """Stops the server this widget started, and nothing else."""
    state = _read_state()
    if not procs.is_ours(state):
        print(json.dumps({"status": "not-ours", "message": "No OpenCode server started by the widget is running."}))
        return
    os.kill(int(state["pid"]), signal.SIGTERM)
    try:
        os.unlink(_state_path())
    except OSError:
        pass
    print(json.dumps({"status": "stopped", "pid": state["pid"]}))


COMMANDS = {
    "opencode_server_status": cmd_opencode_server_status,
    "opencode_server_start": cmd_opencode_server_start,
    "opencode_server_stop": cmd_opencode_server_stop,
}
