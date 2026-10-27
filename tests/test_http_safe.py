"""kdeaichat/http_safe.py: redirects never carry a key to another origin; the image downloader's redirect guard."""
import http.server
import json
import os
import sys
import threading
import urllib.error
import urllib.request

import pytest

UI = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)

from kdeaichat import http_safe, images, schedule_direct, stt_http, tts  # noqa: E402

KEY = "sk-test-SECRET-never-shown"


class Handler(http.server.BaseHTTPRequestHandler):
    """/echo answers with the key headers it saw; /to?u=URL&c=CODE redirects there."""

    def log_message(self, *a):
        pass

    def _answer(self):
        if self.path.startswith("/to"):
            query = dict(p.split("=", 1) for p in self.path.split("?", 1)[1].split("&"))
            self.send_response(int(query["c"]))
            self.send_header("Location", urllib.request.unquote(query["u"]))
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        seen = {h: self.headers.get(h) for h in ("Authorization", "x-api-key", "x-goog-api-key")}
        data = json.dumps(seen).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = _answer


def start():
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, "http://127.0.0.1:%d" % httpd.server_port


@pytest.fixture
def two_servers():
    a, base_a = start()
    b, base_b = start()
    yield base_a, base_b
    a.shutdown()
    b.shutdown()


def call(url, code_to=None, data=None):
    request = urllib.request.Request(url, data=data, headers={"Authorization": "Bearer " + KEY, "x-api-key": KEY, "x-goog-api-key": KEY})
    with http_safe.urlopen(request, timeout=5) as response:
        return json.loads(response.read())


@pytest.mark.parametrize("code", [301, 302, 307, 308])
def test_cross_origin_redirect_drops_the_key(two_servers, code):
    base_a, base_b = two_servers
    seen = call(f"{base_a}/to?c={code}&u={base_b}/echo")
    assert seen == {"Authorization": None, "x-api-key": None, "x-goog-api-key": None}


def test_same_origin_redirect_keeps_the_key(two_servers):
    base_a, _ = two_servers
    seen = call(f"{base_a}/to?c=302&u={base_a}/echo")
    assert seen["Authorization"] == "Bearer " + KEY and seen["x-api-key"] == KEY


def test_plain_urllib_would_leak(two_servers):
    """Guards the premise: the default opener does copy the key to the other port."""
    base_a, base_b = two_servers
    request = urllib.request.Request(f"{base_a}/to?c=302&u={base_b}/echo", headers={"Authorization": "Bearer " + KEY})
    with urllib.request.urlopen(request, timeout=5) as response:
        assert json.loads(response.read())["Authorization"] == "Bearer " + KEY


def test_https_to_http_with_a_key_is_refused():
    handler = http_safe._KeepKeysHome()
    request = urllib.request.Request("https://api.example.com/v1", headers={"Authorization": "Bearer " + KEY})
    with pytest.raises(urllib.error.HTTPError) as e:
        handler.redirect_request(request, None, 302, "x", {}, "http://api.example.com/v1")
    assert KEY not in str(e.value)
    # the same hop without a key is not this helper's business
    plain = urllib.request.Request("https://api.example.com/v1")
    assert handler.redirect_request(plain, None, 302, "x", {}, "http://api.example.com/v1") is not None


def test_https_cross_host_redirect_drops_the_key():
    handler = http_safe._KeepKeysHome()
    request = urllib.request.Request("https://a.example.com/v1", headers={"Authorization": "Bearer " + KEY, "Api-Key": KEY})
    new = handler.redirect_request(request, None, 302, "x", {}, "https://b.example.com/v1")
    assert not [n for n in new.headers if n.lower() in http_safe.CREDENTIAL_HEADERS]
    same = handler.redirect_request(request, None, 302, "x", {}, "https://a.example.com/other")
    assert same.get_header("Authorization") == "Bearer " + KEY


@pytest.mark.parametrize("url,expected", [
    ("http://example.com/v1", True), ("http://192.168.1.5:8000", True), ("HTTP://Host.lan/x", True),
    ("http://localhost:11434", False), ("http://127.0.0.1:8000", False), ("http://127.1.2.3", False),
    ("http://[::1]:8000/v1", False), ("https://example.com", False), ("", False), ("ftp://example.com", False),
])
def test_insecure_key_url(url, expected):
    assert http_safe.insecure_key_url(url) is expected


# --- the image downloader --------------------------------------------------------------

def test_image_opener_has_only_the_guarded_https_handler():
    seen = []

    class Spy(urllib.request.OpenerDirector):
        def add_handler(self, handler):
            seen.append(type(handler))
            super().add_handler(handler)

    original = urllib.request.OpenerDirector
    urllib.request.OpenerDirector = Spy
    try:
        with pytest.raises(Exception):
            images._open_url("https://localhost:1/x.png")  # refused: not a public address (or no server)
    finally:
        urllib.request.OpenerDirector = original
    assert images._GuardedHandler in seen and images._CheckedRedirects in seen
    assert not {urllib.request.HTTPHandler, urllib.request.FTPHandler, urllib.request.FileHandler,
                urllib.request.ProxyHandler, urllib.request.HTTPRedirectHandler} & set(seen)


@pytest.mark.parametrize("target", ["http://127.0.0.1:11434/api/x", "https://user:pw@example.com/a.png", "file:///etc/passwd", "ftp://example.com/a.png"])
def test_image_redirect_to_an_unsafe_link_is_refused(target):
    request = urllib.request.Request("https://cdn.example.com/a.png")
    with pytest.raises(urllib.error.HTTPError):
        images._CheckedRedirects().redirect_request(request, None, 302, "Found", {}, target)


def test_image_redirect_https_to_https_and_relative_still_work():
    request = urllib.request.Request("https://cdn.example.com/a.png")
    handler = images._CheckedRedirects()
    assert handler.redirect_request(request, None, 302, "Found", {}, "https://img.example.net/b.png").full_url == "https://img.example.net/b.png"
    assert handler.redirect_request(request, None, 302, "Found", {}, "/b.png").full_url == "https://cdn.example.com/b.png"


# --- callers: redirects and the warning --------------------------------------------------

def test_scheduled_call_warns_about_a_key_over_lan_http(monkeypatch):
    class Reply:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def read(self, n=-1):
            return json.dumps({"choices": [{"message": {"content": "hi"}}]}).encode()

    cfg = {"type": "openai", "baseUrl": "http://192.168.1.5:8000/v1", "model": "m", "authType": "bearer", "headers": {}}
    opener = lambda request, timeout=None: Reply()  # noqa: E731
    result = schedule_direct.send(cfg, KEY, "m", "", [{"role": "user", "content": "x"}], 100, 5, opener=opener)
    assert result["warning"] == http_safe.INSECURE_KEY_WARNING and KEY not in json.dumps(result)
    cfg["baseUrl"] = "http://127.0.0.1:8000/v1"
    assert "warning" not in schedule_direct.send(cfg, KEY, "m", "", [{"role": "user", "content": "x"}], 100, 5, opener=opener)


def test_tts_and_stt_use_the_safe_opener(two_servers, monkeypatch, tmp_path):
    base_a, base_b = two_servers
    # post() follows a cross-origin redirect to /echo (JSON), which must not see the key
    reply = stt_http.post(f"{base_a}/to?c=302&u={base_b}/echo", b"x", "audio/wav", {"Authorization": "Bearer " + KEY})
    assert reply["Authorization"] is None
    monkeypatch.setattr(tts.schedule_wallet, "read_key", lambda entry: KEY)
    result = tts.synthesize({"engine": "remote", "text": "hi", "options": {"voiceTtsRemoteUrl": f"{base_a}/to?c=302&u={base_b}/echo#"}})
    assert result["ok"] is False and KEY not in json.dumps(result)
