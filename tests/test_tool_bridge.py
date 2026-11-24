"""The tool bridge: the user's MCP servers (stdio and Streamable HTTP) behind token-protected loopback HTTP.

Uses tests/fixtures/fake_mcp_stdio.py as the stdio MCP server and a fake Streamable HTTP server defined here.
"""
import contextlib
import io
import json
import os
import re
import signal
import stat
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui"))
from kdeaichat import tool_bridge  # noqa: E402

FIXTURES = os.path.join(ROOT, "tests", "fixtures")
FAKE_MCP = os.path.join(FIXTURES, "fake_mcp_stdio.py")


def run_command(fn, payload=None):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        fn(payload or {})
    return json.loads(out.getvalue())


def alive(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            return f.read().rsplit(")", 1)[1].split()[0] != "Z"
    except OSError:
        return False


def wait_gone(pid, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not alive(pid):
            return True
        time.sleep(0.1)
    return False


class Bridge:
    def __init__(self, port, token, tmp):
        self.base, self.token, self.tmp = f"http://127.0.0.1:{port}", token, tmp

    def post(self, path, body=None, token=None):
        req = urllib.request.Request(self.base + path, data=json.dumps(body or {}).encode(), method="POST",
                                     headers={"Authorization": "Bearer " + (self.token if token is None else token)})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def tools(self, servers=None, web=None):
        status, body = self.post("/tools", {"servers": servers or {}, "web": web or {}})
        assert status == 200, body
        return body

    def call(self, name, **arguments):
        status, body = self.post("/call", {"name": name, "arguments": arguments})
        return body if status == 200 else dict(body, status=status)


@pytest.fixture
def start(tmp_path, monkeypatch):
    """start(**env) -> Bridge, with a fake KWallet; the bridge is stopped at the end."""
    busctl = tmp_path / "busctl"
    busctl.write_text(f"#!{sys.executable}\nimport runpy\nrunpy.run_path({os.path.join(FIXTURES, 'fake_busctl_tools.py')!r}, run_name='__main__')\n")
    busctl.chmod(0o755)
    for name, value in {"XDG_DATA_HOME": str(tmp_path / "data"), "KDEAICHAT_BUSCTL": str(busctl), "FAKE_WALLET_FILE": str(tmp_path / "wallet.json"),
                        "KDEAICHAT_TOOL_INIT_TIMEOUT": "5", "KDEAICHAT_TOOL_CALL_TIMEOUT": "5"}.items():
        monkeypatch.setenv(name, value)
    started = []

    def make(**env):
        for name, value in env.items():
            monkeypatch.setenv(name, str(value))
        result = run_command(tool_bridge.cmd_tools_bridge_start)
        assert result["status"] == "started", result
        bridge = Bridge(result["port"], result["token"], str(tmp_path))
        started.append(bridge)
        return bridge

    yield make
    run_command(tool_bridge.cmd_tools_bridge_stop)


def stdio(log=None, **env):
    spec_env = dict(env)
    if log:
        spec_env["FAKE_MCP_LOG"] = log
    return {"command": sys.executable, "args": [FAKE_MCP], "env": spec_env}


def pid_of(bridge, name):
    return int(bridge.call(name)["output"])


def test_state_file_is_private_and_health_needs_no_token(start, tmp_path):
    bridge = start()
    path = tmp_path / "data" / "kdeaichat" / "tool-bridge.json"
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    state = json.loads(path.read_text())
    assert state["token"] == bridge.token and state["port"] > 0
    with urllib.request.urlopen(bridge.base + "/health", timeout=5) as r:
        assert json.loads(r.read()) == {"ok": True}
    assert run_command(tool_bridge.cmd_tools_bridge_start)["status"] == "running"


def test_every_route_but_health_needs_the_token(start):
    bridge = start()
    for path in ("/tools", "/call", "/shutdown"):
        assert bridge.post(path, {}, token="wrong")[0] == 401
        assert bridge.post(path, {}, token="")[0] == 401
    req = urllib.request.Request(bridge.base + "/tools")
    with pytest.raises(urllib.error.HTTPError) as err:
        urllib.request.urlopen(req, timeout=5)
    assert err.value.code == 401
    assert bridge.tools({})["tools"] == []  # still running


def test_lists_all_pages_with_safe_unique_names(start):
    bridge = start()
    body = bridge.tools({"fake": stdio()})
    assert body["errors"] == []
    names = [t["name"] for t in body["tools"]]
    assert len(names) == 10 and "fake__echo" in names and "fake__odd_name_v2" in names
    assert all(re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", n) for n in names)
    echo = next(t for t in body["tools"] if t["name"] == "fake__echo")
    assert echo["server"] == "fake" and echo["description"] == "Echoes text back" and echo["inputSchema"]["type"] == "object"


def test_names_that_collide_get_a_number_and_long_ones_are_cut(start):
    bridge = start()
    body = bridge.tools({"a.b": stdio(), "a_b": stdio()})
    names = [t["name"] for t in body["tools"]]
    assert "a_b__echo" in names and "a_b__echo_2" in names and len(set(names)) == 20
    long_name = "n" * 60
    body = bridge.tools({long_name: stdio()})
    assert all(len(t["name"]) <= 64 for t in body["tools"])
    assert bridge.call(body["tools"][0]["name"])["isError"] is False


def test_mcp_servers_wrapper_is_accepted(start):
    bridge = start()
    assert len(bridge.tools({"mcpServers": {"fake": stdio()}})["tools"]) == 10


def test_call_results_and_server_requests(start, tmp_path):
    bridge = start()
    log = str(tmp_path / "mcp.log")
    bridge.tools({"fake": stdio(log=log, FAKE_MCP_VAR="hello")})
    assert bridge.call("fake__echo", text="hi") == {"output": "echo: hi", "isError": False}
    assert bridge.call("fake__fail") == {"output": "boom", "isError": True}
    assert bridge.call("fake__env")["output"] == "hello"
    assert bridge.call("fake__structured")["output"] == '{"a": 1}'
    assert bridge.call("fake__image")["output"] == "here\n[image: image/png, 12 KB]"
    assert bridge.call("fake__odd_name_v2")["output"] == "called odd name.v2"
    replies = [json.loads(line.split(" ", 1)[1]) for line in open(log) if line.startswith("client-reply")]
    assert replies and replies[0]["id"] == "srv-1" and replies[0]["error"]["code"] == -32601


def test_unknown_tool_is_404(start):
    bridge = start()
    bridge.tools({"fake": stdio()})
    result = bridge.call("nope__echo")
    assert result["status"] == 404 and result["isError"] is True and "Unknown tool" in result["output"]


def test_output_is_capped(start):
    bridge = start()
    bridge.tools({"fake": stdio()})
    output = bridge.call("fake__big", size=250000)["output"]
    assert output.startswith("x" * 100000) and output.count("x") == 100000
    assert "truncated" in output and "150000" in output


def test_bad_entries_are_reported_and_good_ones_still_work(start):
    bridge = start()
    body = bridge.tools({"good": stdio(), "bad name!": stdio(), "nocmd": {}, "badtype": {"type": "sse", "url": "https://x.example"},
                         "args": {"command": "x", "args": "nope"}, "creds": {"url": "https://u:p@x.example/"},
                         "missing": {"command": "/no/such/command-here"}, "str": "x", "http": {"type": "http"}})
    assert {t["server"] for t in body["tools"]} == {"good"}
    assert {e["server"] for e in body["errors"]} == {"bad name!", "nocmd", "badtype", "args", "creds", "missing", "str", "http"}
    assert all(e["message"] for e in body["errors"])
    assert next(e for e in body["errors"] if e["server"] == "missing")["message"].startswith("the command wasn't found")
    assert bridge.post("/tools", {"servers": [1, 2]})[1]["errors"]
    assert bridge.post("/tools", {"servers": {"x": {"command": 5}}, "web": "no"})[0] == 200


def test_changed_servers_restart_unchanged_keep_running(start):
    bridge = start()
    bridge.tools({"one": stdio(), "two": stdio()})
    one, two = pid_of(bridge, "one__pid"), pid_of(bridge, "two__pid")
    bridge.tools({"one": stdio(), "two": stdio(FAKE_MCP_VAR="changed")})
    assert pid_of(bridge, "one__pid") == one
    assert pid_of(bridge, "two__pid") != two and not alive(two)
    assert bridge.call("two__env")["output"] == "changed"
    bridge.tools({"two": stdio(FAKE_MCP_VAR="changed")})  # `one` removed: its process stops
    assert wait_gone(one)
    assert bridge.call("one__echo")["status"] == 404


def test_a_dead_server_is_restarted_once(start):
    bridge = start()
    bridge.tools({"fake": stdio()})
    first = pid_of(bridge, "fake__pid")
    assert bridge.call("fake__crash")["isError"] is True
    assert wait_gone(first)
    assert bridge.call("fake__echo", text="again")["output"] == "echo: again"  # restarted
    second = pid_of(bridge, "fake__pid")
    assert second != first
    assert bridge.call("fake__crash")["isError"] is True
    assert wait_gone(second)
    failed = bridge.call("fake__echo")
    assert failed["isError"] is True and "stopped" in failed["output"]
    bridge.tools({"fake": stdio()})  # reloading the tools starts it fresh
    assert bridge.call("fake__echo", text="x")["isError"] is False


def test_slow_call_times_out(start):
    bridge = start(KDEAICHAT_TOOL_CALL_TIMEOUT=1)
    bridge.tools({"fake": stdio()})
    started = time.time()
    result = bridge.call("fake__slow", seconds=10)
    assert result["isError"] is True and "timed out" in result["output"] and time.time() - started < 6


def test_server_that_never_answers_the_handshake(start):
    bridge = start(KDEAICHAT_TOOL_INIT_TIMEOUT=1)
    hang = {"command": sys.executable, "args": ["-c", "import time; time.sleep(60)"]}
    body = bridge.tools({"hang": hang, "fake": stdio()})
    assert [e["server"] for e in body["errors"]] == ["hang"] and "timed out" in body["errors"][0]["message"]
    assert any(t["server"] == "fake" for t in body["tools"])


def test_server_that_exits_at_start(start):
    bridge = start()
    body = bridge.tools({"quit": {"command": sys.executable, "args": ["-c", "import sys; print('bad config', file=sys.stderr); sys.exit(2)"]}})
    assert "stopped" in body["errors"][0]["message"] or "isn't running" in body["errors"][0]["message"]


def test_shutdown_stops_the_mcp_processes_and_removes_the_state(start, tmp_path):
    bridge = start()
    bridge.tools({"fake": stdio()})
    pid = pid_of(bridge, "fake__pid")
    state = json.loads((tmp_path / "data" / "kdeaichat" / "tool-bridge.json").read_text())
    assert bridge.post("/shutdown")[0] == 200
    assert wait_gone(pid) and wait_gone(state["pid"])
    assert not (tmp_path / "data" / "kdeaichat" / "tool-bridge.json").exists()


def test_sigterm_stops_the_mcp_processes(start, tmp_path):
    bridge = start()
    bridge.tools({"fake": stdio()})
    pid = pid_of(bridge, "fake__pid")
    bridge_pid = json.loads((tmp_path / "data" / "kdeaichat" / "tool-bridge.json").read_text())["pid"]
    os.kill(bridge_pid, signal.SIGTERM)
    assert wait_gone(pid) and wait_gone(bridge_pid)


def test_bridge_exits_when_idle(start, tmp_path):
    bridge = start(KDEAICHAT_TOOL_SERVER_IDLE=1.5)
    bridge.tools({"fake": stdio()})
    pid = pid_of(bridge, "fake__pid")
    bridge_pid = json.loads((tmp_path / "data" / "kdeaichat" / "tool-bridge.json").read_text())["pid"]
    time.sleep(0.8)
    assert alive(bridge_pid)
    assert wait_gone(bridge_pid, 15) and wait_gone(pid)


# --- Remote (Streamable HTTP) servers ---------------------------------------------

class FakeHttpMcp:
    """A Streamable HTTP MCP server answering with JSON or an SSE stream."""

    def __init__(self, mode="json", token=None):
        self.requests = []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                msg = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                outer.requests.append((msg, dict(self.headers)))
                if token and self.headers.get("Authorization") != "Bearer " + token:
                    return self.reply(401, b"{}", "application/json")
                if msg.get("method") != "initialize" and self.headers.get("Mcp-Session-Id") != "sess-1":
                    return self.reply(404, b"{}", "application/json")
                if "id" not in msg:
                    return self.reply(202, b"", "application/json")
                method = msg["method"]
                if method == "initialize":
                    result = {"protocolVersion": "2025-06-18", "capabilities": {}, "serverInfo": {"name": "remote"}}
                elif method == "tools/list":
                    result = {"tools": [{"name": "echo", "description": "Echo", "inputSchema": {"type": "object"}}]}
                else:
                    result = {"content": [{"type": "text", "text": "remote " + str(msg["params"]["arguments"].get("text"))}]}
                body = json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": result})
                if mode == "sse":
                    note = json.dumps({"jsonrpc": "2.0", "method": "notifications/message", "params": {}})
                    stream = f": hi\nevent: message\ndata: {note}\n\nevent: message\ndata: {body}\n\n"
                    return self.reply(200, stream.encode(), "text/event-stream", msg["method"] == "initialize")
                self.reply(200, body.encode(), "application/json", method == "initialize")

            def reply(self, status, body, kind, session=False):
                self.send_response(status)
                self.send_header("Content-Type", kind)
                if session:
                    self.send_header("Mcp-Session-Id", "sess-1")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_DELETE(self):
                outer.requests.append(({"method": "DELETE"}, dict(self.headers)))
                self.reply(200, b"", "application/json")

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/mcp"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


@pytest.fixture(params=["json", "sse"])
def remote(request):
    server = FakeHttpMcp(request.param, token="s3cret")
    yield server
    server.close()


def test_remote_server_json_and_sse(start, remote):
    bridge = start()
    body = bridge.tools({"remote": {"url": remote.url, "headers": {"Authorization": "Bearer s3cret", "X-Extra": "1"}}})
    assert body["errors"] == [] and [t["name"] for t in body["tools"]] == ["remote__echo"]
    assert bridge.call("remote__echo", text="hi") == {"output": "remote hi", "isError": False}
    methods = [m.get("method") for m, _ in remote.requests]
    assert methods[:3] == ["initialize", "notifications/initialized", "tools/list"]
    init_headers, later = remote.requests[0][1], remote.requests[-1][1]
    assert "application/json" in init_headers["Accept"] and "text/event-stream" in init_headers["Accept"]
    assert later["Mcp-Session-Id"] == "sess-1" and later["X-Extra"] == "1" and later["Content-Type"] == "application/json"
    assert remote.requests[0][0]["params"]["clientInfo"]["name"] == "kde-ai-chat"
    assert remote.requests[0][0]["params"]["protocolVersion"] == "2025-06-18"
    bridge.post("/shutdown")
    deadline = time.time() + 5
    while time.time() < deadline and remote.requests[-1][0].get("method") != "DELETE":
        time.sleep(0.1)
    assert remote.requests[-1][0]["method"] == "DELETE"


def test_remote_server_refusing_the_key_is_reported(start, remote):
    bridge = start()
    body = bridge.tools({"remote": {"url": remote.url, "type": "streamable-http", "headers": {"Authorization": "Bearer wrong"}}})
    assert body["tools"] == [] and "401" in body["errors"][0]["message"]
    assert "wrong" not in json.dumps(body)


def test_remote_server_that_is_down(start):
    bridge = start()
    body = bridge.tools({"remote": {"url": "http://127.0.0.1:9/mcp"}})
    assert body["errors"][0]["server"] == "remote" and "reach" in body["errors"][0]["message"]
