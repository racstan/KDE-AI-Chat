"""Starting and stopping an `opencode serve` for the widget.

The widget only ever stops a server it started itself: the process id and
the exact command are recorded when starting, and stopping checks both
before sending SIGTERM. A server the user runs on their own is left alone
(older versions ran `pkill -f opencode`, which also killed terminal sessions).
"""
import base64
import json
import os
import secrets
import shutil
import signal
import subprocess
import time
import urllib.request
from typing import Any, Dict, Optional

from kdeaichat import chats, common, procs


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


def authorization(password: str) -> str:
    """The Authorization header value OpenCode's basic auth expects (user name `opencode`)."""
    return "Basic " + base64.b64encode(("opencode:" + password).encode("utf-8")).decode("ascii") if password else ""


def auth_for_port(port: int) -> str:
    """The Authorization value for the server the widget started on `port` ("" = none: a server the user
    started, or one started before passwords existed). Only a server that is still ours gets it."""
    state = _read_state()
    if state.get("password") and int(state.get("port") or 0) == port and procs.is_ours(state):
        return authorization(str(state["password"]))
    return ""


def healthy(port: int, timeout: float = 1.5) -> bool:
    headers = {"Authorization": auth_for_port(port)} if auth_for_port(port) else {}
    request = urllib.request.Request(f"http://127.0.0.1:{port}/global/health", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return 200 <= response.status < 300
    except OSError:
        return False


def _read_state() -> Dict[str, Any]:
    try:
        with open(_state_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


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
    common.ensure_private_dir(chats.data_root())
    # A random password for this server (basic auth), in its environment only: never in argv or the log.
    password = secrets.token_urlsafe(32)
    env = dict(os.environ, OPENCODE_SERVER_PASSWORD=password)
    env.pop("OPENCODE_SERVER_USERNAME", None)
    with common.private_log(log_path) as log:
        process = subprocess.Popen(argv, cwd=directory, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                   start_new_session=True, close_fds=True, env=env)
    common.atomic_write_json(_state_path(), {"pid": process.pid, "port": port, "argv": argv, "password": password})
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


def cmd_opencode_server_auth(payload: Dict[str, Any]) -> None:
    """{authorization} for the server on <port> when the widget started it with a password, else "" (the
    widget then sends no credentials). The value goes to the widget's stdout, never to a log or argv."""
    print(json.dumps({"authorization": auth_for_port(_port(payload))}))


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
    "opencode_server_start": cmd_opencode_server_start,
    "opencode_server_auth": cmd_opencode_server_auth,
    "opencode_server_stop": cmd_opencode_server_stop,
}
