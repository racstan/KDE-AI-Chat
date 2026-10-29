"""Setup checks for what a chat talks to: local model servers, OpenCode and Pi.

Each check returns rows ``{"id", "area", "status": ok|warn|error, "code",
"args"}``; the widget turns ``code`` + ``args`` into plain, translated words
(config/SetupChecks.js). Nothing here installs, starts or changes anything:
an OpenCode server or the Pi bridge that isn't running is reported, not
started. Stdlib only.
"""
import json
import os
import shutil
import socket
import subprocess
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlsplit

from kdeaichat import chats, opencode_server, pi_bridge, procs

TIMEOUT = 3.0
VERSION_TIMEOUT = 5.0
MAX_BODY = 256 * 1024


def row(check_id: str, area: str, status: str, code: str, *args: Any) -> Dict[str, Any]:
    return {"id": check_id, "area": area, "status": status, "code": code, "args": [str(a) for a in args]}


def valid_http_url(url: str) -> bool:
    try:
        parts = urlsplit(url)
    except ValueError:
        return False
    return parts.scheme in ("http", "https") and bool(parts.hostname) and "@" not in parts.netloc \
        and not any(c.isspace() or ord(c) < 32 for c in url)


def probe(url: str, timeout: float = TIMEOUT, headers: Optional[Dict[str, str]] = None) -> Tuple[str, int, Any]:
    """GET ``url`` -> (outcome, HTTP status, parsed JSON or None).

    outcome: ok (2xx), http (another status), refused, timeout, no-host,
    unreachable (anything else: TLS, reset, ...).
    """
    request = urllib.request.Request(url, headers=dict(headers or {}, Accept="application/json"))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read(MAX_BODY)
            try:
                data = json.loads(body.decode("utf-8", "replace"))
            except ValueError:
                data = None
            return "ok", response.status, data
    except urllib.error.HTTPError as e:
        return "http", e.code, None
    except urllib.error.URLError as e:
        reason = e.reason
        if isinstance(reason, ConnectionRefusedError):
            return "refused", 0, None
        if isinstance(reason, (socket.timeout, TimeoutError)):
            return "timeout", 0, None
        if isinstance(reason, socket.gaierror):
            return "no-host", 0, None
        return "unreachable", 0, str(reason)[:200]
    except (socket.timeout, TimeoutError):
        return "timeout", 0, None
    except ConnectionRefusedError:
        return "refused", 0, None
    except OSError as e:
        return "unreachable", 0, str(e)[:200]


def _version(argv: List[str], env: Optional[Dict[str, str]] = None) -> str:
    """First line of ``<program> --version`` (empty when it fails)."""
    try:
        result = subprocess.run(argv + ["--version"], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                timeout=VERSION_TIMEOUT, env=env)
    except (OSError, subprocess.SubprocessError):
        return ""
    lines = (result.stdout or result.stderr or "").strip().splitlines()
    return lines[0].strip()[:80] if result.returncode == 0 and lines else ""


def check_endpoint(endpoint: Dict[str, Any], timeout: float = TIMEOUT) -> Dict[str, Any]:
    """A local (or self-hosted) OpenAI-compatible server: does ``<url>/models`` answer?"""
    name = str(endpoint.get("name") or endpoint.get("id") or "?")[:80]
    url = str(endpoint.get("url") or "").strip().rstrip("/")
    check_id = "endpoint:" + str(endpoint.get("id") or name)[:80]
    if not valid_http_url(url):
        return row(check_id, "connection", "error", "url-bad", name, url)
    outcome, status, data = probe(url + "/models", timeout)
    if outcome == "ok":
        models = data.get("data") if isinstance(data, dict) else data
        count = len(models) if isinstance(models, list) else 0
        if count == 0 and isinstance(data, dict) and isinstance(data.get("models"), list):
            count = len(data["models"])
        return row(check_id, "connection", "ok", "local-ok", name, url, count)
    if outcome == "http" and status == 404:
        return row(check_id, "connection", "warn", "local-not-found", name, url)
    if outcome == "http" and status in (401, 403):
        return row(check_id, "connection", "ok", "local-needs-key", name, url)
    if outcome == "http":
        return row(check_id, "connection", "warn", "local-http", name, url, status)
    if outcome == "refused":
        return row(check_id, "connection", "error", "local-refused", name, url)
    if outcome == "timeout":
        return row(check_id, "connection", "error", "local-timeout", name, url)
    if outcome == "no-host":
        return row(check_id, "connection", "error", "local-no-host", name, url)
    return row(check_id, "connection", "error", "local-unreachable", name, url, data or "")


def opencode_base(raw: str) -> str:
    """The configured OpenCode URL without its /v1 (like main.qml's openCodeBaseUrl)."""
    url = str(raw or "http://127.0.0.1:4096/v1").strip()
    if url.endswith("/"):
        url = url[:-1]
    if url.endswith("/v1"):
        url = url[:-3]
    return url.rstrip("/")


def _is_local(url: str) -> bool:
    try:
        return (urlsplit(url).hostname or "") in ("127.0.0.1", "localhost", "::1")
    except ValueError:
        return False


def check_opencode(raw_url: str, timeout: float = TIMEOUT) -> List[Dict[str, Any]]:
    """OpenCode mode: the program, and the server at the configured address."""
    url = opencode_base(raw_url)
    if not valid_http_url(url):
        return [row("opencode-server", "opencode", "error", "opencode-bad-url", raw_url)]
    binary = opencode_server.find_binary()
    version = _version([binary]) if binary else ""
    port = urlsplit(url).port or 0
    auth = opencode_server.auth_for_port(port) if _is_local(url) and port else ""  # the widget's own server has a password
    outcome, status, data = probe(url + "/global/health", timeout, {"Authorization": auth} if auth else None)
    if outcome == "ok":
        server_version = str(data.get("version") or "") if isinstance(data, dict) else ""
        found = server_version or version
        return [row("opencode-server", "opencode", "ok", "opencode-running", url, found) if found
                else row("opencode-server", "opencode", "ok", "opencode-running-plain", url)]
    rows = []
    if not binary and _is_local(url):
        rows.append(row("opencode-program", "opencode", "error", "opencode-missing"))
    if outcome == "http":
        rows.append(row("opencode-server", "opencode", "error", "opencode-not-server", url, status))
    elif outcome in ("refused", "timeout") and _is_local(url) and binary:
        # The widget starts `opencode serve` itself for a local address (chat/OpenCodeMode.qml).
        rows.append(row("opencode-server", "opencode", "ok", "opencode-starts", url, version) if version
                    else row("opencode-server", "opencode", "ok", "opencode-starts-plain", url))
    elif outcome == "timeout":
        rows.append(row("opencode-server", "opencode", "error", "opencode-timeout", url))
    elif binary or not _is_local(url):
        rows.append(row("opencode-server", "opencode", "error", "opencode-unreachable", url))
    return rows


def find_pi() -> str:
    return shutil.which("pi", path=pi_env_path()) or ""


def pi_env_path() -> str:
    extra = [os.path.expanduser(p) for p in ("~/.npm-global/bin", "~/.local/bin", "~/bin")]
    return os.pathsep.join([os.environ.get("PATH", "")] + extra)


def check_pi() -> List[Dict[str, Any]]:
    """Pi mode: the `pi` program and the bridge (reported, never started here)."""
    rows = []
    binary = find_pi()
    if binary:
        env = dict(os.environ, PATH=pi_env_path())
        version = _version([binary], env)
        rows.append(row("pi-program", "pi", "ok", "pi-ok", binary, version) if version
                    else row("pi-program", "pi", "ok", "pi-ok-plain", binary))
    else:
        rows.append(row("pi-program", "pi", "error", "pi-missing"))
    state = pi_bridge._read_state()
    if procs.is_ours(state) and pi_bridge._healthy(int(state.get("port") or 0)):
        rows.append(row("pi-bridge", "pi", "ok", "pi-bridge-running"))
        return rows
    problem = ""
    if not os.path.isfile(pi_bridge.SERVER):
        problem = "pi_bridge_server.py is missing"
    else:
        root = parent = chats.data_root()
        while not os.path.isdir(parent) and os.path.dirname(parent) != parent:
            parent = os.path.dirname(parent)  # the folder is made on first start
        if not os.access(parent, os.W_OK):
            problem = root + " isn't writable"
    if problem:
        rows.append(row("pi-bridge", "pi", "error", "pi-bridge-broken", problem))
    else:
        rows.append(row("pi-bridge", "pi", "ok", "pi-bridge-starts"))
    return rows
