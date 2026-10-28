"""local_servers_scan: fake loopback servers only; the fixed port list is never used for real here."""
import json
import os
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from kdeaichat import local_servers

from tests.conftest import UI_DIR

HELPER = os.path.join(UI_DIR, "kde_ai_helper.py")


class _Server:
    """GET <path> -> (status, JSON body, or raw bytes); optional delay; records the requests."""

    def __init__(self, routes, delay=0.0):
        outer = self
        self.requests = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                outer.requests.append((self.path, dict(self.headers)))
                if delay:
                    time.sleep(delay)
                status, body = outer.routes.get(self.path, (404, {"error": "not found"}))
                data = body if isinstance(body, bytes) else json.dumps(body).encode()
                try:
                    self.send_response(status)
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                except OSError:
                    pass

        self.routes = routes
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


@pytest.fixture
def server():
    made = []

    def make(routes, delay=0.0):
        s = _Server(routes, delay)
        made.append(s)
        return s
    yield make
    for s in made:
        s.close()


def closed_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


OPENAI = {"/v1/models": (200, {"object": "list", "data": [{"id": "m1"}, {"id": "m2"}, {"id": "m3"}]})}


def test_ollama_by_its_own_endpoints(server, monkeypatch):
    s = server({"/api/version": (200, {"version": "0.5.1"}), "/api/tags": (200, {"models": [{"name": "llama3.2:3b"}, {"name": "qwen3:8b"}]})})
    monkeypatch.setattr(local_servers, "_get", _redirect(local_servers._get, s.port, 11434))
    found = local_servers.scan_port(11434, 0.7)
    assert found["kind"] == "ollama" and found["name"] == "Ollama"
    assert found["models"] == ["llama3.2:3b", "qwen3:8b"] and found["baseUrl"] == "http://127.0.0.1:11434/v1"


def test_ollama_server_details(server):
    s = server({"/api/version": (200, {"version": "0.5.1"}), "/api/tags": (200, {"models": [{"name": "a"}]}), **OPENAI})
    found = local_servers._ollama(s.port, 0.7)
    assert found["count"] == 1 and found["provider"] == "ollama"
    assert found["baseUrl"] == "http://127.0.0.1:%d/v1" % s.port and found["needsKey"] is False


def test_openai_compatible_falls_back_to_generic(server):
    s = server(OPENAI)
    found = local_servers.scan_port(s.port, 0.7)
    assert found["kind"] == "openai" and found["name"] == "OpenAI-compatible server"
    assert found["models"] == ["m1", "m2", "m3"] and found["count"] == 3 and found["provider"] == "custom"


@pytest.mark.parametrize("port,extra,kind,provider", [
    (1234, {"/api/v0/models": (200, {"data": [{"id": "m1", "state": "loaded"}]})}, "lmstudio", "lmstudio"),
    (8080, {"/props": (200, {"default_generation_settings": {}, "total_slots": 1})}, "llamacpp", "llamacpp"),
    (4000, {"/health/readiness": (200, {"status": "healthy", "litellm_version": "1.5"})}, "litellm", "litellm"),
])
def test_named_only_when_the_server_says_so(server, monkeypatch, port, extra, kind, provider):
    s = server({**OPENAI, **extra})
    # Pretend the fake's port is the well-known one for the identifying request.
    monkeypatch.setattr(local_servers, "_get", _redirect(local_servers._get, s.port, port))
    found = local_servers._kind_of(port, OPENAI["/v1/models"][1], 0.7)
    assert found == kind
    assert local_servers.PROVIDERS[found] == provider


def _redirect(real, to_port, from_port):
    return lambda port, path, timeout: real(to_port if port == from_port else port, path, timeout)


def test_well_known_port_without_the_marker_stays_generic(server, monkeypatch):
    s = server(OPENAI)
    monkeypatch.setattr(local_servers, "_get", _redirect(local_servers._get, s.port, 8080))
    assert local_servers._kind_of(8080, OPENAI["/v1/models"][1], 0.7) == "openai"
    assert local_servers._kind_of(1234, OPENAI["/v1/models"][1], 0.7) == "openai"


def test_vllm_by_owned_by():
    data = {"data": [{"id": "x", "owned_by": "vllm"}]}
    assert local_servers._kind_of(8000, data, 0.7) == "vllm"
    assert local_servers._kind_of(8000, {"data": [{"id": "x", "owned_by": "other"}]}, 0.7) == "openai"
    assert local_servers._kind_of(8000, {"data": []}, 0.7) == "openai"


def test_nothing_listening():
    assert local_servers.scan_port(closed_port(), 0.7) is None
    assert local_servers.scan([closed_port(), closed_port()], 0.7) == []


def test_slow_server_times_out_quickly(server):
    s = server(OPENAI, delay=2.0)
    start = time.time()
    assert local_servers.scan_port(s.port, 0.3) is None
    assert time.time() - start < 1.5


def test_garbage_and_wrong_shapes(server):
    assert local_servers.scan_port(server({"/v1/models": (200, b"<html>not json</html>")}).port, 0.7) is None
    assert local_servers.scan_port(server({"/v1/models": (200, [1, 2])}).port, 0.7) is None
    assert local_servers.scan_port(server({"/v1/models": (200, {"data": "nope"})}).port, 0.7) is None
    assert local_servers.scan_port(server({"/v1/models": (500, {"error": "x"})}).port, 0.7) is None
    odd = local_servers.scan_port(server({"/v1/models": (200, {"data": [1, None, {"id": 5}, {"id": "ok"}]})}).port, 0.7)
    assert odd["models"] == ["ok"]


def test_server_that_wants_a_key_is_listed_without_models(server):
    found = local_servers.scan_port(server({"/v1/models": (401, {"error": "key"})}).port, 0.7)
    assert found["needsKey"] is True and found["count"] == 0 and found["kind"] == "openai"


def test_litellm_with_a_master_key_is_found_and_needs_its_key(server, monkeypatch):
    # Health endpoints are open; /v1/models answers 401 without the key.
    s = server({"/v1/models": (401, {"error": "no key"}), "/health/liveliness": (200, "I'm alive!")})
    monkeypatch.setattr(local_servers, "_get", _redirect(local_servers._get, s.port, 4000))
    found = local_servers.scan_port(4000, 0.7)
    assert found["kind"] == "litellm" and found["name"] == "LiteLLM proxy" and found["provider"] == "litellm"
    assert found["needsKey"] is True and found["models"] == [] and found["baseUrl"] == "http://127.0.0.1:4000/v1"
    assert all(path in ("/v1/models", "/health/readiness", "/health/liveliness") for path, _ in s.requests)


def test_litellm_identified_by_readiness_when_it_answers(server, monkeypatch):
    s = server({"/v1/models": (401, {}), "/health/readiness": (200, {"status": "healthy", "litellm_version": "1.5"})})
    monkeypatch.setattr(local_servers, "_get", _redirect(local_servers._get, s.port, 4000))
    assert local_servers.scan_port(4000, 0.7)["kind"] == "litellm"


def test_unknown_server_on_the_litellm_port_asking_for_a_key_stays_generic(server, monkeypatch):
    s = server({"/v1/models": (401, {}), "/health/liveliness": (200, "ok")})
    monkeypatch.setattr(local_servers, "_get", _redirect(local_servers._get, s.port, 4000))
    found = local_servers.scan_port(4000, 0.7)
    assert found["kind"] == "openai" and found["needsKey"] is True


def test_no_credentials_are_sent(server):
    s = server(OPENAI)
    local_servers.scan_port(s.port, 0.7)
    for _path, headers in s.requests:
        assert not any(k.lower() in ("authorization", "x-api-key", "cookie") for k in headers)


def test_redirects_and_proxies_are_not_followed(server, monkeypatch):
    elsewhere = server(OPENAI)
    redirecting = server({"/v1/models": (302, b"")})
    # a 302 would need a Location header; a bare one is a failure either way, and never reaches `elsewhere`
    assert local_servers.scan_port(redirecting.port, 0.7) is None
    assert elsewhere.requests == []
    monkeypatch.setenv("http_proxy", "http://127.0.0.1:%d" % closed_port())
    assert local_servers.scan_port(elsewhere.port, 0.7)["kind"] == "openai"


def test_fixed_ports_do_not_include_gitea_or_anything_else():
    assert local_servers.PORTS == [11434, 1234, 8080, 4000, 8000, 1337]
    assert 3000 not in local_servers.PORTS and local_servers.HOST == "127.0.0.1"


def test_command_prints_json_through_the_helper():
    import base64
    arg = base64.b64encode(b"{}").decode()
    out = subprocess.run([sys.executable, HELPER, "local_servers_scan", arg], capture_output=True, text=True, timeout=30)
    assert out.returncode == 0
    assert isinstance(json.loads(out.stdout)["servers"], list)


def test_local_ports_env_replaces_the_fixed_ports(monkeypatch):
    monkeypatch.setenv("KDEAICHAT_LOCAL_PORTS", "18765, x,70000,1234")
    assert local_servers._ports_from_env() == [18765, 1234]
    monkeypatch.setenv("KDEAICHAT_LOCAL_PORTS", "")
    assert local_servers._ports_from_env() == []
    monkeypatch.delenv("KDEAICHAT_LOCAL_PORTS")
    assert local_servers._ports_from_env() == local_servers.PORTS
