"""The MCP bridge: stdio and Streamable HTTP servers behind token-protected loopback HTTP. No network."""
import contextlib
import io
import json
import os
import stat
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui"))
from kdeaichat import mcp_bridge  # noqa: E402

FAKE = os.path.join(ROOT, "tests", "fake_mcp_stdio.py")


def _run(fn, payload=None):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        fn(payload or {})
    return json.loads(out.getvalue())


class FakeHttp(BaseHTTPRequestHandler):
    """Streamable HTTP MCP: initialize hands out a session id; echo answers JSON, sse answers an event stream."""
    seen = []

    def log_message(self, *a):
        pass

    def do_POST(self):
        msg = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        FakeHttp.seen.append((msg.get("method"), self.headers.get("Mcp-Session-Id"), self.headers.get("Accept"),
                              self.headers.get("X-Test")))
        method, rid = msg.get("method"), msg.get("id")
        if rid is None:
            self.send_response(202)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if method == "initialize":
            return self._json(rid, {"protocolVersion": "2025-06-18", "capabilities": {}}, {"Mcp-Session-Id": "sess-1"})
        if method == "tools/list":
            return self._json(rid, {"tools": [{"name": "echo", "description": "d", "inputSchema": {"type": "object"}}]})
        if msg["params"]["name"] == "sse":
            body = ("event: message\ndata: " + json.dumps({"jsonrpc": "2.0", "method": "notifications/progress", "params": {}})
                    + "\n\nevent: message\ndata: " + json.dumps({"jsonrpc": "2.0", "id": rid, "result": {
                        "content": [{"type": "text", "text": "from sse"}]}}) + "\n\n").encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            return self.wfile.write(body)
        self._json(rid, {"content": [{"type": "text", "text": "from json"}]})

    def _json(self, rid, result, extra=None):
        body = json.dumps({"jsonrpc": "2.0", "id": rid, "result": result}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)


@pytest.fixture
def http_server():
    FakeHttp.seen = []
    srv = ThreadingHTTPServer(("127.0.0.1", 0), FakeHttp)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_address[1]}/mcp"
    srv.shutdown()


class Bridge:
    def __init__(self, port, token):
        self.base, self.token = f"http://127.0.0.1:{port}", token

    def post(self, path, body=None, token=None):
        req = urllib.request.Request(self.base + path, data=json.dumps(body or {}).encode(), method="POST",
                                     headers={"Authorization": "Bearer " + (self.token if token is None else token)})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())


@pytest.fixture
def bridge():
    with tempfile.TemporaryDirectory() as tmp:
        with patch.dict(os.environ, {"XDG_DATA_HOME": os.path.join(tmp, "data"), "FAKE_LOG_DIR": tmp,
                                     "KDEAICHAT_FAKE_MCP_LOG": os.path.join(tmp, "starts.log")}):
            started = mcp_bridge.ensure_bridge()
            assert started["status"] == "started", started
            b = Bridge(started["port"], started["token"])
            b.tmp = tmp
            try:
                yield b
            finally:
                _run(mcp_bridge.cmd_mcp_bridge_stop)


def stdio(**extra):
    return {"id": "fake", "command": sys.executable, "args": [FAKE], "env": {}, **extra}


def test_lists_tools_from_both_kinds_following_cursor(bridge, http_server):
    status, out = bridge.post("/tools", {"servers": [stdio(), {"id": "web", "url": http_server},
                                                     {"id": "bad", "command": "/nonexistent/mcp"}]})
    assert status == 200
    names = [t["name"] for t in out["servers"]["fake"]["tools"]]
    assert names == ["echo", "boom", "slow", "big", "crash"]
    assert out["servers"]["fake"]["tools"][0]["inputSchema"]["type"] == "object"
    assert [t["name"] for t in out["servers"]["web"]["tools"]] == ["echo"]
    assert "Couldn't start" in out["servers"]["bad"]["error"]
    methods = [m for m, *_ in FakeHttp.seen]
    assert methods == ["initialize", "notifications/initialized", "tools/list"]
    assert FakeHttp.seen[2][1] == "sess-1" and "text/event-stream" in FakeHttp.seen[2][2]


def test_call_describes_images_and_reports_errors(bridge):
    status, out = bridge.post("/call", {"server": stdio(), "tool": "echo", "arguments": {"text": "hi"}})
    assert status == 200 and out["isError"] is False
    assert out["content"].splitlines()[0] == "echo: hi"
    assert out["content"].splitlines()[1].startswith("[image: image/png") and "AAAA" not in out["content"]
    _, out = bridge.post("/call", {"server": stdio(), "tool": "boom"})
    assert out == {"content": "it broke", "isError": True}


def test_http_call_json_and_sse_and_headers(bridge, http_server):
    server = {"id": "web", "url": http_server, "headers": {"X-Test": "s3cret"}}
    assert bridge.post("/call", {"server": server, "tool": "json"})[1] == {"content": "from json", "isError": False}
    assert bridge.post("/call", {"server": server, "tool": "sse"})[1] == {"content": "from sse", "isError": False}
    assert all(h == "s3cret" for *_, h in FakeHttp.seen)


def test_timeout_is_an_error_result(bridge):
    t = time.time()
    _, out = bridge.post("/call", {"server": stdio(), "tool": "slow", "timeout": 0.5})
    assert out["isError"] and "didn't answer" in out["content"] and time.time() - t < 4


def test_crashed_server_restarts(bridge):
    _, out = bridge.post("/call", {"server": stdio(), "tool": "crash"})
    assert out["isError"] and "ended" in out["content"]
    _, out = bridge.post("/call", {"server": stdio(), "tool": "echo", "arguments": {"text": "again"}})
    assert out["isError"] is False and out["content"].startswith("echo: again")
    with open(os.path.join(bridge.tmp, "starts.log")) as f:
        assert len(f.read().splitlines()) == 2


def test_env_reaches_the_server_but_not_the_log_or_argv(bridge):
    bridge.post("/call", {"server": stdio(env={"FAKE_SECRET": "hunter2"}), "tool": "echo"})
    with open(os.path.join(bridge.tmp, "starts.log")) as f:
        assert "hunter2" in f.read()
    state = json.load(open(os.path.join(bridge.tmp, "data", "kdeaichat", "mcp-bridge.json")))
    assert "hunter2" not in " ".join(open(f"/proc/{state['pid']}/cmdline").read().split("\0"))
    assert "hunter2" not in open(os.path.join(bridge.tmp, "data", "kdeaichat", "mcp-bridge.log")).read()


def test_token_required(bridge):
    assert bridge.post("/tools", {"servers": []}, token="wrong")[0] == 401
    assert bridge.post("/call", {}, token="")[0] == 401
    req = urllib.request.Request(bridge.base + "/health")
    assert urllib.request.urlopen(req, timeout=5).status == 200


def test_result_text_is_cut_at_32_kb(bridge):
    _, out = bridge.post("/call", {"server": stdio(), "tool": "big"})
    assert len(out["content"].encode()) < 33 * 1024 and out["content"].startswith("x" * 32768)
    assert "cut" in out["content"].splitlines()[-1] and "50000" in out["content"]


def test_stop_ends_server_processes(bridge):
    bridge.post("/call", {"server": stdio(), "tool": "echo"})
    pid = int(open(os.path.join(bridge.tmp, "starts.log")).read().split()[0])
    assert bridge.post("/stop")[0] == 200
    time.sleep(0.5)
    assert not os.path.exists(f"/proc/{pid}") or "Z" in open(f"/proc/{pid}/stat").read().split(")")[-1][:3]


def test_start_returns_running_bridge_and_state_is_private(bridge):
    again = mcp_bridge.ensure_bridge()
    assert again["status"] == "running" and again["port"] == int(bridge.base.rsplit(":", 1)[1]) and again["token"] == bridge.token
    data = os.path.join(bridge.tmp, "data", "kdeaichat")
    for name in ("mcp-bridge.json", "mcp-bridge.log"):
        assert stat.S_IMODE(os.stat(os.path.join(data, name)).st_mode) == 0o600


def test_concurrent_starts_make_one_bridge():
    with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"XDG_DATA_HOME": tmp}):
        results = []
        threads = [threading.Thread(target=lambda: results.append(mcp_bridge.ensure_bridge())) for _ in range(4)]
        [t.start() for t in threads]
        [t.join() for t in threads]
        try:
            assert sorted(r["status"] for r in results) == ["running"] * 3 + ["started"]
            assert len({r["port"] for r in results}) == 1
        finally:
            _run(mcp_bridge.cmd_mcp_bridge_stop)


def test_log_is_rotated_when_large():
    with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"XDG_DATA_HOME": tmp}):
        data = os.path.join(tmp, "kdeaichat")
        os.makedirs(data)
        log = os.path.join(data, "mcp-bridge.log")
        with open(log, "wb") as f:
            f.write(b"x" * (mcp_bridge.LOG_LIMIT + 1))
        handle, _ = mcp_bridge._open_log()
        handle.close()
        assert os.path.getsize(log + ".1") > mcp_bridge.LOG_LIMIT and os.path.getsize(log) == 0
        assert stat.S_IMODE(os.stat(log).st_mode) == 0o600
