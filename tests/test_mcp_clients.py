"""Stdio MCP client details: concurrent writes, and requests the server sends to the client."""
import json
import os
import sys
import textwrap
import threading

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui"))
from kdeaichat import mcp_clients  # noqa: E402

FAKE = os.path.join(ROOT, "tests", "fake_mcp_stdio.py")

ASKING_SERVER = textwrap.dedent("""
    import json, sys

    def send(obj):
        sys.stdout.write(json.dumps(obj) + "\\n")
        sys.stdout.flush()

    for line in sys.stdin:
        msg = json.loads(line)
        method, rid = msg.get("method"), msg.get("id")
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": rid, "result": {"protocolVersion": "2025-06-18", "capabilities": {}}})
        elif method == "tools/call":
            send({"jsonrpc": "2.0", "id": "srv-ping", "method": "ping"})
            send({"jsonrpc": "2.0", "id": "srv-other", "method": "sampling/createMessage", "params": {}})
            got = [json.loads(sys.stdin.readline()), json.loads(sys.stdin.readline())]
            send({"jsonrpc": "2.0", "id": rid, "result": {"content": [{"type": "text", "text": json.dumps(got, sort_keys=True)}]}})
""")


def test_server_ping_gets_an_empty_result_and_other_requests_method_not_found(tmp_path):
    script = tmp_path / "asking.py"
    script.write_text(ASKING_SERVER)
    client = mcp_clients.make_client({"id": "a", "command": sys.executable, "args": [str(script)]})
    try:
        result = client.call("ask", {}, 10)
    finally:
        client.close()
    got = {m["id"]: m for m in json.loads(result["content"][0]["text"])}
    assert got["srv-ping"]["result"] == {}
    assert "error" not in got["srv-ping"]
    assert got["srv-other"]["error"]["code"] == -32601


def test_concurrent_calls_write_whole_lines():
    client = mcp_clients.make_client({"id": "c", "command": sys.executable, "args": [FAKE]})
    assert isinstance(client, mcp_clients.StdioClient)
    results, errors = {}, []

    def work(n):
        try:
            text = f"{n}:" + "y" * 300000
            results[n] = client.call("echo", {"text": text}, 20)["content"][0]["text"]
        except Exception as e:  # noqa: BLE001
            errors.append(e)

    try:
        threads = [threading.Thread(target=work, args=(n,)) for n in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(30)
    finally:
        client.close()
    assert not errors
    for n in range(8):
        assert results[n].startswith(f"echo: {n}:") and len(results[n]) == len(f"echo: {n}:") + 300000


def test_writes_take_the_lock():
    client = mcp_clients.StdioClient({"id": "l", "command": "x"})
    assert hasattr(client.write_lock, "acquire")
