"""Pi bridge: runs `pi --mode rpc` for the widget's chats and serves them over loopback HTTP.

QML can't keep a pipe to a process open, so this small server does: one Pi
process per chat (started in the chat's folder, resuming the chat's Pi
session), its JSON events streamed to the widget as server-sent events, and
the widget's prompts, aborts and dialog answers written to its stdin.

Every request but /health needs `Authorization: Bearer <token>`. The port and
token are written to the state file given as the only argument (mode 0600);
the helper (pi_bridge.py) starts this script and reads them from there.

Routes:
  GET  /health
  GET  /chats/<id>/events        SSE: bridge_connected, then each Pi event,
                                 bridge_exit if the Pi process ends
  POST /chats/<id>/prompt        {directory, provider, model, thinking, instructions, message, images, ephemeral}
                                 (ephemeral: an incognito chat, Pi keeps no session file)
                                 (no directory: the chat's own folder under
                                 ~/.local/share/kdeaichat/pi-workspaces/<id>;
                                 instructions: added to Pi's system prompt)
  GET  /chats/<id>/status        {running, alive}: running only while Pi's process is alive and mid-run
  POST /chats/<id>/abort
  POST /chats/<id>/ui-response   {id, value | confirmed | cancelled}
  POST /chats/<id>/close         stops that chat's Pi process
  POST /shutdown

Idle Pi processes exit after AGENT_IDLE seconds, and the bridge after
SERVER_IDLE seconds without any. Stdlib only.
"""
import collections
import hmac
import json
import os
import queue
import re
import secrets
import shutil
import signal
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Started with `python -I`: only this file's own folder is added, for pi_files.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pi_files import default_directory, instructions_file, private_write  # noqa: E402

AGENT_IDLE = float(os.environ.get("KDEAICHAT_PI_AGENT_IDLE", 15 * 60))
SERVER_IDLE = float(os.environ.get("KDEAICHAT_PI_SERVER_IDLE", 10 * 60))
MAX_BODY = 40 * 1024 * 1024
CHAT_ID = re.compile(r"[A-Za-z0-9._:-]{1,128}")
THINKING = ("", "off", "minimal", "low", "medium", "high", "xhigh", "max")
ROUTE = re.compile(r"^/chats/([^/]+)/(events|status|prompt|abort|ui-response|close)$")

lock = threading.Lock()
agents = {}          # chat id -> Agent
subscribers = {}     # chat id -> set of queue.Queue
last_activity = time.monotonic()


def pi_env():
    env = os.environ.copy()
    extra = [os.path.expanduser(p) for p in ("~/.npm-global/bin", "~/.local/bin", "~/bin")]
    env["PATH"] = os.pathsep.join([env.get("PATH", "")] + extra)
    return env


def broadcast(chat_id, event):
    line = json.dumps(event, separators=(",", ":"))
    with lock:
        for q in list(subscribers.get(chat_id, ())):
            q.put(line)


class Agent:
    """One `pi --mode rpc` process for one chat."""

    def __init__(self, chat_id, directory, provider, model, thinking, instructions="", ephemeral=False):
        env = pi_env()
        binary = shutil.which("pi", path=env["PATH"])
        if not binary:
            raise FileNotFoundError("Pi isn't installed (no `pi` command found).")
        argv = [binary, "--mode", "rpc"] + (["--no-session"] if ephemeral else ["--session-id", "kde-ai-chat-" + chat_id])
        for flag, value in (("--provider", provider), ("--model", model), ("--thinking", thinking),
                            ("--append-system-prompt", instructions_file(chat_id, instructions))):
            if value:
                argv += [flag, value]
        self.chat_id = chat_id
        self.key = (directory, provider, model, thinking, instructions, ephemeral)
        self.running = False
        self.quiet = False   # stopped on purpose for a newer Pi: its exit is not news for the stream
        self.last_active = time.monotonic()
        self.stderr_tail = collections.deque(maxlen=40)
        self.write_lock = threading.Lock()
        self.proc = subprocess.Popen(argv, cwd=directory, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, start_new_session=True, close_fds=True)
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def send(self, command):
        data = (json.dumps(command, separators=(",", ":")) + "\n").encode("utf-8")
        with self.write_lock:
            self.proc.stdin.write(data)
            self.proc.stdin.flush()
        self.last_active = time.monotonic()

    def _read_stdout(self):
        buffer = b""
        while True:
            chunk = self.proc.stdout.read1(65536)
            if not chunk:
                break
            buffer += chunk
            # Records end with LF only: U+2028/2029 inside JSON strings are not separators.
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                self._handle_line(line.rstrip(b"\r"))
        code = self.proc.wait()
        with lock:
            if agents.get(self.chat_id) is self:
                del agents[self.chat_id]
        if self.quiet:
            return
        broadcast(self.chat_id, {"type": "bridge_exit", "code": code, "stderr": "\n".join(self.stderr_tail)[-4000:]})

    def _handle_line(self, line):
        try:
            event = json.loads(line.decode("utf-8"))
        except ValueError:
            return
        if not isinstance(event, dict):
            return
        kind = event.get("type")
        if kind == "agent_start":
            self.running = True
        elif kind == "agent_settled" or (kind == "response" and event.get("command") == "prompt" and not event.get("success")):
            self.running = False
        self.last_active = time.monotonic()
        broadcast(self.chat_id, event)

    def _read_stderr(self):
        for raw in self.proc.stderr:
            self.stderr_tail.append(raw.decode("utf-8", "replace").rstrip())

    def alive(self):
        return self.proc.poll() is None

    def stop(self, quiet=False):
        self.quiet = quiet
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
            self.proc.wait(timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except OSError:
                pass


def _option(payload, name, limit=256):
    value = str(payload.get(name) or "").strip()
    if len(value) > limit or value.startswith("-") or any(ord(ch) < 0x20 for ch in value):
        raise ValueError("invalid " + name)
    return value


def prompt(chat_id, payload):
    requested = str(payload.get("directory") or "").strip()
    directory = os.path.realpath(os.path.expanduser(requested)) if requested else default_directory(chat_id)
    if not os.path.isdir(directory):
        raise ValueError("the chat's folder doesn't exist: " + directory)
    provider, model, thinking = _option(payload, "provider"), _option(payload, "model"), _option(payload, "thinking")
    if thinking not in THINKING:
        raise ValueError("invalid thinking level")
    message = str(payload.get("message") or "")
    if not message.strip() or "\x00" in message:
        raise ValueError("the message is empty")
    instructions = str(payload.get("instructions") or "")
    if len(instructions) > 100000 or "\x00" in instructions:
        raise ValueError("invalid instructions")
    images = [{"type": "image", "data": str(i.get("data", "")), "mimeType": str(i.get("mimeType", "image/png"))}
              for i in (payload.get("images") or [])[:20] if isinstance(i, dict)]
    # A run that was just stopped may take a moment to settle.
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and getattr(agents.get(chat_id), "running", False):
        time.sleep(0.1)
    ephemeral = payload.get("ephemeral") is True
    key = (directory, provider, model, thinking, instructions, ephemeral)
    with lock:
        replaced = agents.pop(chat_id) if chat_id in agents and agents[chat_id].key != key and not agents[chat_id].running else None
    if replaced:
        # Quiet: its exit must not reach the stream the new prompt is about to use.
        replaced.stop(quiet=True)  # before starting another Pi on the same session
    with lock:
        agent = agents.get(chat_id)
        if agent and not agent.alive():
            # Pi died just now and its reader hasn't removed it yet: a message written to it would be lost.
            agents.pop(chat_id, None)
            agent = None
        if agent and agent.running:
            return 409, {"error": "Pi is still working on this chat."}
        if agent is None:
            agent = agents[chat_id] = Agent(chat_id, directory, provider, model, thinking, instructions, ephemeral)
        agent.running = True
    command = {"id": "prompt-" + secrets.token_hex(4), "type": "prompt", "message": message}
    if images:
        command["images"] = images
    try:
        agent.send(command)
    except OSError:
        agent.running = False
        with lock:
            if agents.get(chat_id) is agent:
                del agents[chat_id]
        agent.stop(quiet=True)
        raise OSError("Pi stopped before it got the message.")
    return 202, {"ok": True}


class Handler(BaseHTTPRequestHandler):
    token = ""

    def log_message(self, *args):
        pass

    def _reply(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorised(self):
        given = self.headers.get("Authorization", "")
        if hmac.compare_digest(given.encode(), ("Bearer " + self.token).encode()):
            return True
        self._reply(401, {"error": "unauthorised"})
        return False

    def _route(self):
        match = ROUTE.match(self.path.split("?", 1)[0])
        if not match or not CHAT_ID.fullmatch(match.group(1)):
            self._reply(404, {"error": "not found"})
            return None, None
        return match.group(1), match.group(2)

    def do_GET(self):
        global last_activity
        if self.path == "/health":
            return self._reply(200, {"ok": True})
        if not self._authorised():
            return
        chat_id, action = self._route()
        if action == "status":
            with lock:
                agent = agents.get(chat_id)
            alive = bool(agent and agent.alive())
            return self._reply(200, {"running": alive and agent.running, "alive": alive})
        if action != "events":
            return chat_id and self._reply(405, {"error": "use POST"})
        q = queue.Queue()
        with lock:
            subscribers.setdefault(chat_id, set()).add(q)
            agent = agents.get(chat_id)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        try:
            hello = {"type": "bridge_connected", "running": bool(agent and agent.running)}
            self.wfile.write(("data: " + json.dumps(hello) + "\n\n").encode())
            self.wfile.flush()
            while True:
                try:
                    line = q.get(timeout=15)
                    self.wfile.write(("data: " + line + "\n\n").encode("utf-8"))
                except queue.Empty:
                    self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
        except OSError:
            pass
        finally:
            with lock:
                subscribers.get(chat_id, set()).discard(q)
                last_activity = time.monotonic()

    def do_POST(self):
        global last_activity
        if not self._authorised():
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            return self._reply(413, {"error": "request too large"})
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return self._reply(400, {"error": "invalid JSON"})
        if not isinstance(payload, dict):
            return self._reply(400, {"error": "expected an object"})
        last_activity = time.monotonic()
        if self.path == "/shutdown":
            self._reply(200, {"ok": True})
            threading.Thread(target=shutdown, daemon=True).start()
            return
        chat_id, action = self._route()
        if not chat_id:
            return
        if action == "prompt":
            try:
                return self._reply(*prompt(chat_id, payload))
            except (ValueError, OSError) as exc:
                return self._reply(400, {"error": str(exc)})
        with lock:
            agent = agents.get(chat_id)
        if action == "abort" and agent:
            agent.send({"type": "abort"})
        elif action == "ui-response" and agent:
            response = {"type": "extension_ui_response", "id": str(payload.get("id", ""))}
            for name in ("value", "confirmed", "cancelled"):
                if name in payload:
                    response[name] = payload[name] if name != "value" else str(payload[name])
            agent.send(response)
        elif action == "close" and agent:
            with lock:
                agents.pop(chat_id, None)
            agent.stop()
        elif action == "events":
            return self._reply(405, {"error": "use GET"})
        self._reply(200, {"ok": True, "running": bool(agent and agent.running)})


server = None


def shutdown(only_if_idle=False):
    with lock:
        if only_if_idle and (agents or any(subscribers.values()) or time.monotonic() - last_activity <= SERVER_IDLE):
            return False  # a prompt or a stream arrived since the janitor looked
        running = list(agents.values())
        agents.clear()
    for agent in running:
        agent.stop()
    server.shutdown()
    return True


def janitor():
    while True:
        time.sleep(min(30, max(1, AGENT_IDLE / 4)))
        now = time.monotonic()
        with lock:
            idle = [a for a in agents.values() if not a.running and not subscribers.get(a.chat_id)
                    and now - a.last_active > AGENT_IDLE]
            for agent in idle:
                agents.pop(agent.chat_id, None)
            empty = not agents and not any(subscribers.values()) and now - last_activity > SERVER_IDLE
        for agent in idle:
            agent.stop()
        if empty and shutdown(only_if_idle=True):
            return


def write_state(path, port, token):
    private_write(path, json.dumps({"pid": os.getpid(), "port": port, "token": token, "argv": [sys.executable] + sys.argv}))


def main():
    global server
    state_path = sys.argv[1]
    Handler.token = secrets.token_urlsafe(32)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    write_state(state_path, server.server_address[1], Handler.token)
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=shutdown, daemon=True).start())
    threading.Thread(target=janitor, daemon=True).start()
    try:
        server.serve_forever()
    finally:
        try:
            with open(state_path, encoding="utf-8") as f:
                if json.load(f).get("pid") == os.getpid():
                    os.unlink(state_path)
        except (OSError, ValueError):
            pass


if __name__ == "__main__":
    main()
