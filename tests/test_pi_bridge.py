"""The Pi bridge: one `pi --mode rpc` per chat behind token-protected loopback HTTP.

Uses scripts/dev-pi-mock.py as `pi`, which replays real Pi captures.
"""
import contextlib
import io
import json
import os
import queue
import stat
import tempfile
import threading
import time
import urllib.error
import urllib.request
from unittest.mock import patch

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
import sys  # noqa: E402
sys.path.insert(0, os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui"))
from kdeaichat import pi_bridge, procs  # noqa: E402

FIXTURES = os.path.join(ROOT, "tests", "fixtures")


def _run(fn, payload=None):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        fn(payload or {})
    return json.loads(out.getvalue())


class Bridge:
    def __init__(self, port, token):
        self.base = f"http://127.0.0.1:{port}"
        self.token = token

    def post(self, path, body=None, token=None):
        req = urllib.request.Request(self.base + path, data=json.dumps(body or {}).encode(), method="POST",
                                     headers={"Authorization": "Bearer " + (token if token is not None else self.token)})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def events(self, chat):
        """Opens the chat's event stream; returns a queue of parsed events."""
        q = queue.Queue()
        req = urllib.request.Request(self.base + f"/chats/{chat}/events", headers={"Authorization": "Bearer " + self.token})
        response = urllib.request.urlopen(req, timeout=30)

        def read():
            try:
                for raw in response:
                    line = raw.decode().strip()
                    if line.startswith("data: "):
                        q.put(json.loads(line[6:]))
            except (OSError, ValueError):
                pass
        threading.Thread(target=read, daemon=True).start()
        first = q.get(timeout=5)
        assert first["type"] == "bridge_connected"
        q.response = response
        return q


def _until(q, kind, timeout=15):
    seen = []
    deadline = time.time() + timeout
    while time.time() < deadline:
        event = q.get(timeout=max(0.1, deadline - time.time()))
        seen.append(event)
        if event["type"] == kind:
            return seen
    raise AssertionError(f"no {kind} in {[e['type'] for e in seen]}")


@pytest.fixture
def bridge(request):
    with tempfile.TemporaryDirectory() as tmp:
        bindir = os.path.join(tmp, "bin")
        os.makedirs(bindir)
        os.symlink(os.path.join(ROOT, "scripts", "dev-pi-mock.py"), os.path.join(bindir, "pi"))
        log = os.path.join(tmp, "pi.log")
        env = {"PATH": bindir + os.pathsep + os.environ["PATH"], "XDG_DATA_HOME": os.path.join(tmp, "data"),
               "PI_CODING_AGENT_DIR": os.path.join(tmp, "pi-agent"),
               "KDEAICHAT_PI_MOCK_LOG": log,
               "KDEAICHAT_PI_MOCK_FIXTURE": os.path.join(FIXTURES, getattr(request, "param", "pi-0.84-ollama-write.jsonl"))}
        with patch.dict(os.environ, env):
            started = _run(pi_bridge.cmd_pi_bridge_start)
            assert started["status"] == "started", started
            b = Bridge(started["port"], started["token"])
            b.tmp, b.log = tmp, log
            try:
                yield b
            finally:
                _run(pi_bridge.cmd_pi_bridge_stop)


def _log(b):
    with open(b.log, encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def test_no_directory_runs_pi_in_the_chats_own_folder_not_home(bridge):
    q = bridge.events("chat-9")
    assert bridge.post("/chats/chat-9/prompt", {"provider": "ollama", "model": "m", "thinking": "low", "message": "hi"})[0] == 202
    _until(q, "agent_settled")
    expected = os.path.realpath(os.path.join(bridge.tmp, "data", "kdeaichat", "pi-workspaces", "chat-9"))
    assert _log(bridge)[0]["cwd"] == expected
    assert os.path.realpath(os.path.expanduser("~")) != expected


def test_chat_with_pi_history_in_home_stays_there(bridge):
    # Chats from before 1.4.0 ran Pi in the home folder; Pi files their history by folder.
    home = os.path.realpath(os.path.expanduser("~"))
    sessions = os.path.join(bridge.tmp, "pi-agent", "sessions", "--" + home.lstrip("/").replace("/", "-") + "--")
    os.makedirs(sessions)
    open(os.path.join(sessions, "2026-10-24T14-58-31-577Z_kde-ai-chat-chat-old.jsonl"), "w").close()
    q = bridge.events("chat-old")
    assert bridge.post("/chats/chat-old/prompt", {"provider": "ollama", "model": "m", "thinking": "low", "message": "hi"})[0] == 202
    _until(q, "agent_settled")
    assert _log(bridge)[0]["cwd"] == home


def test_prompt_streams_pi_events_in_the_chats_folder(bridge):
    folder = os.path.join(bridge.tmp, "project")
    os.makedirs(folder)
    q = bridge.events("chat-1")
    status, body = bridge.post("/chats/chat-1/prompt", {"directory": folder, "provider": "ollama", "model": "qwen3:8b",
                                                        "thinking": "low", "message": "Create hello.txt"})
    assert (status, body) == (202, {"ok": True})
    events = _until(q, "agent_settled")
    assert [e["type"] for e in events if e["type"].startswith("tool_execution")] == ["tool_execution_start", "tool_execution_end"]
    start, prompt = _log(bridge)[0], _log(bridge)[1]
    assert start["cwd"] == os.path.realpath(folder)
    assert start["argv"] == ["--mode", "rpc", "--session-id", "kde-ai-chat-chat-1", "--provider", "ollama",
                             "--model", "qwen3:8b", "--thinking", "low"]
    assert prompt["command"]["type"] == "prompt" and prompt["command"]["message"] == "Create hello.txt"
    # The same process serves the next message.
    assert bridge.post("/chats/chat-1/prompt", {"directory": folder, "provider": "ollama", "model": "qwen3:8b",
                                                "thinking": "low", "message": "again"})[0] == 202
    _until(q, "agent_settled")
    assert sum(1 for entry in _log(bridge) if "argv" in entry) == 1


def test_token_is_required_and_state_is_private(bridge):
    assert bridge.post("/chats/c/prompt", {"message": "x"}, token="wrong")[0] == 401
    with pytest.raises(urllib.error.HTTPError) as err:
        urllib.request.urlopen(bridge.base + "/chats/c/events", timeout=5)
    assert err.value.code == 401
    state = os.path.join(bridge.tmp, "data", "kdeaichat", "pi-bridge.json")
    assert stat.S_IMODE(os.stat(state).st_mode) == 0o600
    assert bridge.post("/chats/..%2F/prompt", {"message": "x"})[0] == 404
    assert bridge.post("/chats/c/prompt", {"message": "x", "directory": "/no/such/folder"})[0] == 400
    assert bridge.post("/chats/c/prompt", {"message": "x", "model": "--evil"})[0] == 400


@pytest.mark.parametrize("bridge", ["pi-0.84-ollama-permission-denied.jsonl"], indirect=True)
def test_dialog_waits_for_the_answer_and_busy_chat_refuses(bridge):
    q = bridge.events("chat-2")
    assert bridge.post("/chats/chat-2/prompt", {"directory": bridge.tmp, "message": "rm"})[0] == 202
    request = _until(q, "extension_ui_request")[-1]
    status, body = bridge.post("/chats/chat-2/prompt", {"directory": bridge.tmp, "message": "another"})
    assert status == 409 and "still working" in body["error"]
    assert bridge.post("/chats/chat-2/ui-response", {"id": request["id"], "value": "No", "extra": "dropped"})[0] == 200
    _until(q, "agent_settled")
    answer = [e["command"] for e in _log(bridge) if e.get("command", {}).get("type") == "extension_ui_response"]
    assert answer == [{"type": "extension_ui_response", "id": request["id"], "value": "No"}]


@pytest.mark.parametrize("bridge", ["pi-0.84-ollama-permission-denied.jsonl"], indirect=True)
def test_abort_and_close(bridge):
    q = bridge.events("chat-3")
    assert bridge.post("/chats/chat-3/prompt", {"directory": bridge.tmp, "message": "rm"})[0] == 202
    _until(q, "extension_ui_request")
    assert bridge.post("/chats/chat-3/abort")[0] == 200
    events = _until(q, "agent_settled")
    assert any(e.get("message", {}).get("stopReason") == "aborted" for e in events)
    # A new prompt right after Stop is accepted.
    assert bridge.post("/chats/chat-3/prompt", {"directory": bridge.tmp, "message": "next"})[0] == 202
    _until(q, "extension_ui_request")
    assert bridge.post("/chats/chat-3/close")[0] == 200
    assert _until(q, "bridge_exit")[-1]["type"] == "bridge_exit"


def test_instructions_reach_pi_from_a_private_file(bridge):
    q = bridge.events("chat-5")
    text = "--- Project instructions (Work) ---\nAnswer in French.\n--- End project instructions ---"
    assert bridge.post("/chats/chat-5/prompt", {"directory": bridge.tmp, "instructions": text, "message": "hi"})[0] == 202
    _until(q, "agent_settled")
    argv = [e for e in _log(bridge) if "argv" in e][0]["argv"]
    path = argv[argv.index("--append-system-prompt") + 1]
    assert path == os.path.join(bridge.tmp, "data", "kdeaichat", "pi-instructions", "chat-5.md")
    with open(path, encoding="utf-8") as f:
        assert f.read() == text
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode) == 0o700
    assert "Answer in French" not in " ".join(argv), "the text itself is never on a command line"
    # Same instructions: the same Pi. Changed ones: a new Pi; none: no flag.
    for instructions in (text, "Answer in German.", ""):
        assert bridge.post("/chats/chat-5/prompt", {"directory": bridge.tmp, "instructions": instructions, "message": "hi"})[0] == 202
        _until(q, "agent_settled")
    starts = [e["argv"] for e in _log(bridge) if "argv" in e]
    assert len(starts) == 3
    assert "--append-system-prompt" not in starts[2]
    assert bridge.post("/chats/chat-5/prompt", {"message": "x", "instructions": "a\x00b"})[0] == 400
    assert bridge.post("/chats/chat-5/prompt", {"message": "x", "instructions": "a" * 100001})[0] == 400


def test_changing_the_folder_restarts_pi(bridge):
    q = bridge.events("chat-4")
    other = os.path.join(bridge.tmp, "other")
    os.makedirs(other)
    for folder in (bridge.tmp, other):
        assert bridge.post("/chats/chat-4/prompt", {"directory": folder, "message": "hi"})[0] == 202
        _until(q, "agent_settled")
    starts = [e["cwd"] for e in _log(bridge) if "argv" in e]
    assert starts == [os.path.realpath(bridge.tmp), os.path.realpath(other)]


def test_start_reuses_a_running_bridge_and_stop_only_stops_ours(bridge):
    again = _run(pi_bridge.cmd_pi_bridge_start)
    assert again["status"] == "running" and again["token"] == bridge.token
    state_path = os.path.join(bridge.tmp, "data", "kdeaichat", "pi-bridge.json")
    with open(state_path) as f:
        state = json.load(f)
    assert procs.is_ours(state)
    foreign = dict(state, argv=state["argv"][:-1] + ["/somewhere/else.json"])
    with open(state_path, "w") as f:
        json.dump(foreign, f)
    assert _run(pi_bridge.cmd_pi_bridge_stop)["status"] == "not-running"
    with open(state_path, "w") as f:
        json.dump(state, f)


def test_idle_bridge_exits_on_its_own():
    with tempfile.TemporaryDirectory() as tmp:
        env = {"XDG_DATA_HOME": tmp, "KDEAICHAT_PI_SERVER_IDLE": "1", "KDEAICHAT_PI_AGENT_IDLE": "1"}
        with patch.dict(os.environ, env):
            started = _run(pi_bridge.cmd_pi_bridge_start)
            state_path = os.path.join(tmp, "kdeaichat", "pi-bridge.json")
            for _ in range(100):
                if not os.path.exists(state_path):
                    break
                time.sleep(0.1)
            assert not os.path.exists(state_path), started
