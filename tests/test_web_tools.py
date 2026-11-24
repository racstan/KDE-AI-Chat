"""web_search and fetch_url (the tool bridge's web tools), and the search keys in KWallet."""
import contextlib
import io
import json
import os
import socket
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)
sys.path.insert(0, os.path.join(UI, "kdeaichat"))  # the bridge imports its helpers by plain name
import net_guard  # noqa: E402
import web_tools  # noqa: E402
from kdeaichat import schedule_wallet, tool_bridge  # noqa: E402

KEY = "SECRET-KEY-0123456789"
FIXTURES = os.path.join(ROOT, "tests", "fixtures")


class FakeResponse:
    def __init__(self, body):
        self.body = json.dumps(body).encode() if not isinstance(body, bytes) else body

    def read(self, n=-1):
        return self.body if n < 0 else self.body[:n]

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def fake_open(body, seen):
    def urlopen(request, timeout=None):
        seen.append(request)
        return FakeResponse(body)
    return urlopen


def search(provider, body, **kwargs):
    seen = []
    with patch.object(web_tools.http_safe, "urlopen", fake_open(body, seen)):
        return web_tools.web_search(provider, **kwargs), seen[0]


# --- web_search ---------------------------------------------------------------------

def test_searxng_request_and_results():
    (text, is_error), request = search("searxng", {"results": [
        {"title": "First", "url": "https://a.example/1", "content": "About   first\nthing"},
        {"title": "Second", "url": "https://b.example/2", "content": ""}, {"title": "no url"}]},
        query="hello world", count=5, searxng_url="http://192.168.1.5:8080/")
    assert request.full_url == "http://192.168.1.5:8080/search?q=hello+world&format=json"
    assert not is_error
    assert text == "1. First\n   https://a.example/1\n   About first thing\n2. Second\n   https://b.example/2"


def test_searxng_needs_an_http_address():
    for url in ("", "file:///etc/passwd", "ftp://x.example", "http://user:pw@x.example", "not a url"):
        text, is_error = web_tools.web_search("searxng", "q", 5, url)
        assert is_error and "SearXNG" in text


def test_brave_request_and_results():
    (text, is_error), request = search("brave", {"web": {"results": [{"title": "T", "url": "https://t.example", "description": "D"}] * 3}},
                                       query="cats", count=2, key=KEY)
    assert request.full_url == "https://api.search.brave.com/res/v1/web/search?q=cats&count=2"
    assert request.get_header("X-subscription-token") == KEY and request.get_method() == "GET"
    assert not is_error and text.count("https://t.example") == 2 and KEY not in text


def test_tavily_request_and_results():
    (text, is_error), request = search("tavily", {"results": [{"title": "T", "url": "https://t.example", "content": "C"}]},
                                       query="cats", count=99, key=KEY)
    assert request.full_url == "https://api.tavily.com/search" and request.get_method() == "POST"
    assert request.get_header("Authorization") == "Bearer " + KEY
    assert json.loads(request.data) == {"query": "cats", "max_results": 10}
    assert text == "1. T\n   https://t.example\n   C" and not is_error


def test_empty_results_and_bad_input():
    assert search("brave", {"web": {}}, query="x", key=KEY)[0] == ("No results.", False)
    assert web_tools.web_search("brave", "  ", 5, "", KEY)[1] is True
    assert web_tools.web_search("none", "x")[1] is True
    assert search("tavily", {"results": [{"title": "T", "url": "https://t"}]}, query="x", count="abc", key=KEY)[0][1] is False


def test_errors_never_contain_the_key():
    def failing(error):
        def urlopen(request, timeout=None):
            raise error
        return urlopen
    for error in (OSError(f"connection broke {KEY}"), urllib.error.URLError(f"no route {KEY}"), ValueError(KEY)):
        with patch.object(web_tools.http_safe, "urlopen", failing(error)):
            text, is_error = web_tools.web_search("brave", "x", 5, "", KEY)
        assert is_error and KEY not in text and text.startswith("The search failed")
    http = urllib.error.HTTPError("https://api", 401, "Unauthorized", {}, None)
    with patch.object(web_tools.http_safe, "urlopen", failing(http)):
        text, is_error = web_tools.web_search("tavily", "x", 5, "", KEY)
    assert is_error and "401" in text and KEY not in text
    with patch.object(web_tools.http_safe, "urlopen", fake_open(b"not json", [])):
        assert web_tools.web_search("brave", "x", 5, "", KEY)[1] is True


# --- fetch_url ----------------------------------------------------------------------

class Site:
    """A local web server; `pages` maps a path to (status, content type, body, extra headers)."""

    def __init__(self, pages):
        self.pages, self.hosts = pages, []
        site = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                site.hosts.append(self.headers.get("Host"))
                status, kind, body, extra = site.pages[self.path]
                body = body.encode() if isinstance(body, str) else body
                self.send_response(status)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(body)))
                for name, value in extra.items():
                    self.send_header(name, value)
                self.end_headers()
                self.wfile.write(body)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


@contextlib.contextmanager
def public_internet(site, internal=("internal.example",)):
    """public.example resolves to a public address (really connecting to `site`), internal.example to 10.0.0.5."""
    real_getaddrinfo, real_connect = socket.getaddrinfo, socket.create_connection
    connected = []

    def getaddrinfo(host, port, *args, **kwargs):
        if host == "public.example":
            return [(2, 1, 6, "", ("93.184.216.34", port))]
        if host in internal:
            return [(2, 1, 6, "", ("10.0.0.5", port))]
        return real_getaddrinfo(host, port, *args, **kwargs)

    def create_connection(address, *args, **kwargs):
        connected.append(address[0])
        return real_connect(("127.0.0.1", site.port), *args, **kwargs)

    with patch.object(socket, "getaddrinfo", getaddrinfo), patch.object(socket, "create_connection", create_connection):
        yield connected


@pytest.fixture
def site():
    pages = {}
    s = Site(pages)
    yield s
    s.close()


def test_fetch_refuses_bad_links_and_private_addresses():
    for url in ("", "file:///etc/passwd", "ftp://x.example/", "https://user:pw@x.example/", "http://", "javascript:alert(1)", "http://a b"):
        assert web_tools.fetch_url(url)[1] is True
    for url in ("http://127.0.0.1:1/", "http://localhost:1/", "http://[::1]:1/", "http://10.1.2.3/", "http://169.254.169.254/latest/", "http://192.168.0.1/"):
        text, is_error = web_tools.fetch_url(url)
        assert is_error and text.startswith("Refused"), (url, text)


def test_fetch_connects_only_to_public_addresses_and_refuses_private_redirects(site):
    site.pages.update({
        "/ok": (200, "text/plain", "hello", {}),
        "/to-internal": (302, "text/html", "", {"Location": "http://internal.example/secret"}),
        "/to-loopback": (302, "text/html", "", {"Location": "http://127.0.0.1:1/"}),
        "/to-file": (302, "text/html", "", {"Location": "file:///etc/passwd"}),
    })
    with public_internet(site) as connected:
        assert web_tools.fetch_url("http://public.example/ok") == ("hello", False)
        assert connected == ["93.184.216.34"]
        for path in ("/to-internal", "/to-loopback", "/to-file"):
            text, is_error = web_tools.fetch_url("http://public.example" + path)
            assert is_error and "hello" not in text, (path, text)
        assert "10.0.0.5" not in connected and "127.0.0.1" not in connected
        assert web_tools.fetch_url("http://internal.example/")[0].startswith("Refused")


def test_fetch_follows_at_most_five_redirects(site):
    for n in range(8):
        site.pages[f"/r{n}"] = (302, "text/html", "", {"Location": f"/r{n + 1}"})
    site.pages["/r8"] = (200, "text/plain", "end", {})
    site.pages["/s0"] = (302, "text/html", "", {"Location": "/s1"})
    site.pages["/s1"] = (302, "text/html", "", {"Location": "/s2"})
    site.pages["/s2"] = (200, "text/plain", "arrived", {})
    with public_internet(site):
        assert web_tools.fetch_url("http://public.example/s0") == ("arrived", False)
        text, is_error = web_tools.fetch_url("http://public.example/r0")
    assert is_error and "end" != text


def test_html_becomes_readable_text(site):
    site.pages["/page"] = (200, "text/html; charset=utf-8", """<!doctype html><html><head><title>My  Page</title>
        <style>p{color:red}</style><script>var secret = 1;</script></head><body>
        <nav><a href="/">Home</a> <ul><li>Menu item</li></ul></nav>
        <h1>Heading</h1><p>First   paragraph with <b>bold</b> &amp; entities.</p>
        <noscript>Enable JS</noscript><svg><text>logo</text></svg>
        <ul><li>one</li><li>two</li></ul><h2>Sub</h2><p>Last<br>line</p></body></html>""", {})
    with public_internet(site):
        text, is_error = web_tools.fetch_url("https://public.example/page".replace("https", "http"))
    assert not is_error
    assert text == "My Page\n\n# Heading\n\nFirst paragraph with bold & entities.\n\n- one\n- two\n\n## Sub\n\nLast\nline"


def test_text_json_and_other_types(site):
    site.pages.update({"/t": (200, "text/plain; charset=latin-1", b"caf\xe9", {}), "/j": (200, "application/json", '{"a":  1}', {}),
                       "/img": (200, "image/png", b"\x89PNG", {}), "/missing": (404, "text/html", "nope", {})})
    with public_internet(site):
        assert web_tools.fetch_url("http://public.example/t") == ("caf\xe9", False)
        assert web_tools.fetch_url("http://public.example/j") == ('{"a":  1}', False)
        text, is_error = web_tools.fetch_url("http://public.example/img")
        assert is_error and text.startswith("Unsupported content type")
        text, is_error = web_tools.fetch_url("http://public.example/missing")
        assert is_error and "404" in text


def test_text_caps(site):
    site.pages["/long"] = (200, "text/plain", "y" * 120000, {})
    with public_internet(site):
        text, _ = web_tools.fetch_url("http://public.example/long")
        assert text == "y" * 50000 + "\n\n[truncated]"
        assert web_tools.fetch_url("http://public.example/long", 1000)[0] == "y" * 1000 + "\n\n[truncated]"
        assert len(web_tools.fetch_url("http://public.example/long", 10 ** 9)[0]) == 100000 + len("\n\n[truncated]")
        with patch.object(web_tools, "MAX_DOWNLOAD", 3000):
            text, _ = web_tools.fetch_url("http://public.example/long", 50000)
            assert text == "y" * 3000 + "\n\n[truncated]"


def test_the_guard_module_is_stdlib_only():
    source = open(os.path.join(UI, "kdeaichat", "net_guard.py"), encoding="utf-8").read()
    assert "kdeaichat" not in source.replace("`kdeaichat` package", "")
    assert net_guard.GuardedHTTPHandler and net_guard.GuardedHTTPSHandler


# --- Search keys in KWallet ---------------------------------------------------------

def run(fn, payload):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        fn(payload)
    return out.getvalue()


@pytest.fixture
def wallet(tmp_path, monkeypatch):
    busctl = tmp_path / "busctl"
    busctl.write_text(f"#!{sys.executable}\nimport runpy\nrunpy.run_path({os.path.join(FIXTURES, 'fake_busctl_tools.py')!r}, run_name='__main__')\n")
    busctl.chmod(0o755)
    monkeypatch.setenv("KDEAICHAT_BUSCTL", str(busctl))
    monkeypatch.setenv("FAKE_WALLET_FILE", str(tmp_path / "wallet.json"))
    monkeypatch.delenv("KDEAICHAT_WALLET_FOLDER", raising=False)
    monkeypatch.setenv("FAKE_WALLET", "open")
    return tmp_path / "wallet.json"


def test_key_set_status_and_remove(wallet):
    assert json.loads(run(tool_bridge.cmd_tools_key_status, {})) == {"brave": False, "tavily": False}
    output = run(tool_bridge.cmd_tools_key_set, {"name": "brave", "key": "  " + KEY + " "})
    assert json.loads(output) == {"status": "saved", "message": ""} and KEY not in output
    assert json.loads(wallet.read_text()) == {"KDEAIChat-tools": {"brave": KEY}}
    status = run(tool_bridge.cmd_tools_key_status, {})
    assert json.loads(status) == {"brave": True, "tavily": False} and KEY not in status
    assert json.loads(run(tool_bridge.cmd_tools_key_set, {"name": "brave", "key": ""}))["status"] == "removed"
    assert json.loads(run(tool_bridge.cmd_tools_key_status, {})) == {"brave": False, "tavily": False}
    assert schedule_wallet.read_key("brave", folder="KDEAIChat-tools") == ""


def test_key_folder_follows_the_wallet_folder_override(wallet, monkeypatch):
    monkeypatch.setenv("KDEAICHAT_WALLET_FOLDER", "KDEAIChat-dev")
    run(tool_bridge.cmd_tools_key_set, {"name": "tavily", "key": KEY})
    assert json.loads(wallet.read_text()) == {"KDEAIChat-dev-tools": {"tavily": KEY}}


def test_key_set_rejects_bad_input_and_a_missing_wallet(wallet, monkeypatch):
    for payload in ({"name": "google", "key": KEY}, {"name": "brave", "key": "a\nb"}, {"name": "brave", "key": "k" * 600}, {}):
        assert json.loads(run(tool_bridge.cmd_tools_key_set, payload))["status"] == "error"
    monkeypatch.setenv("FAKE_WALLET", "down")
    output = run(tool_bridge.cmd_tools_key_set, {"name": "brave", "key": KEY})
    assert json.loads(output)["status"] == "error" and KEY not in output
    assert json.loads(run(tool_bridge.cmd_tools_key_status, {})) == {"brave": False, "tavily": False}


def test_locked_wallet_is_not_read_but_can_be_written(wallet, monkeypatch):
    run(tool_bridge.cmd_tools_key_set, {"name": "brave", "key": KEY})
    monkeypatch.setenv("FAKE_WALLET", "closed")
    assert json.loads(run(tool_bridge.cmd_tools_key_status, {})) == {"brave": False, "tavily": False}
    assert json.loads(run(tool_bridge.cmd_tools_key_set, {"name": "tavily", "key": "other"}))["status"] == "saved"


def test_commands_are_registered_but_the_stop_is_not():
    assert set(tool_bridge.COMMANDS) == {"tools_bridge_start", "tools_key_set", "tools_key_status"}
