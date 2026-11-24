"""The web tools through the tool bridge (see test_tool_bridge.py for the fixtures)."""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from tests.test_tool_bridge import start, stdio  # noqa: F401  (start is a fixture)


class FakeSearx:
    def __init__(self):
        outer = self
        self.paths = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                outer.paths.append(self.path)
                body = json.dumps({"results": [{"title": "Cats", "url": "https://a.example/cats", "content": "Fluffy"}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()


def test_web_tools_are_listed_and_called(start):  # noqa: F811
    searx = FakeSearx()
    bridge = start()
    body = bridge.tools({"fake": stdio()}, web={"search": "searxng", "searxngUrl": searx.url, "fetch": True})
    web = [t for t in body["tools"] if t["server"] == "web"]
    assert [t["name"] for t in web] == ["web_search", "fetch_url"] and body["errors"] == []
    assert web[0]["inputSchema"]["required"] == ["query"] and web[1]["inputSchema"]["required"] == ["url"]
    result = bridge.call("web_search", query="cats", count=3)
    assert result["isError"] is False and result["output"] == "1. Cats\n   https://a.example/cats\n   Fluffy"
    assert searx.paths == ["/search?q=cats&format=json"]
    local = bridge.call("fetch_url", url=searx.url)  # a local address is not reachable through fetch_url
    assert local["isError"] is True and local["output"].startswith("Refused") and searx.paths == ["/search?q=cats&format=json"]
    assert bridge.call("fetch_url")["isError"] is True
    assert [t["name"] for t in bridge.tools({}, web={"search": "none", "fetch": True})["tools"]] == ["fetch_url"]
    assert bridge.tools({}, web={"search": "none", "fetch": False})["tools"] == []
    assert bridge.call("web_search", query="x")["status"] == 404


def test_keyed_search_needs_a_key_in_the_wallet(start, tmp_path):  # noqa: F811
    bridge = start()
    secret = "BRAVE-SECRET-XYZ"
    body = bridge.tools({}, web={"search": "brave"})
    assert body["tools"] == [] and body["errors"][0]["server"] == "web" and "brave" in body["errors"][0]["message"]
    (tmp_path / "wallet.json").write_text(json.dumps({"KDEAIChat-tools": {"brave": secret, "tavily": "T"}}))
    body = bridge.tools({}, web={"search": "brave"})
    assert [t["name"] for t in body["tools"]] == ["web_search"] and body["errors"] == []
    assert [t["name"] for t in bridge.tools({}, web={"search": "tavily"})["tools"]] == ["web_search"]
    assert secret not in json.dumps(body)
    assert bridge.tools({}, web={"search": "searxng", "searxngUrl": ""})["errors"][0]["server"] == "web"
    assert secret not in (tmp_path / "data" / "kdeaichat" / "tool-bridge.log").read_text()


def test_locked_wallet_is_reported_not_asked(start, tmp_path):  # noqa: F811
    (tmp_path / "wallet.json").write_text(json.dumps({"KDEAIChat-tools": {"brave": "k"}}))
    bridge = start(FAKE_WALLET="closed")
    body = bridge.tools({}, web={"search": "brave"})
    assert body["tools"] == [] and "locked" in body["errors"][0]["message"]
