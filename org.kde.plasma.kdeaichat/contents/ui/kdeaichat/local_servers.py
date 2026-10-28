"""``local_servers_scan``: which AI servers answer on this computer.

Only 127.0.0.1, only the fixed ports below, only read-only GETs, with short
timeouts, in parallel; no key or other credential is ever sent, no proxy or
redirect is followed, and nothing is started or changed. Prints::

    {"servers": [{"id", "kind", "name", "port", "baseUrl", "models": [str],
                  "count": int, "needsKey": bool, "provider": preset id}]}

``kind`` is ollama | lmstudio | llamacpp | litellm | vllm | openai; a server
that doesn't clearly identify itself is "openai" (an OpenAI-compatible
server). Gitea and other things on other ports are never asked. Stdlib only.
"""
import json
import os
import socket
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List, Optional, Tuple

HOST = "127.0.0.1"
TIMEOUT = 0.7
MAX_BODY = 512 * 1024
MAX_MODELS = 200

# The fixed ports: Ollama, LM Studio, llama.cpp / LocalAI, LiteLLM, vLLM, Jan.
PORTS = [11434, 1234, 8080, 4000, 8000, 1337]
NAMES = {"ollama": "Ollama", "lmstudio": "LM Studio", "llamacpp": "llama.cpp server", "litellm": "LiteLLM proxy",
         "vllm": "vLLM", "openai": "OpenAI-compatible server"}
# The provider preset (ProviderService.js) each kind fills in.
PROVIDERS = {"ollama": "ollama", "lmstudio": "lmstudio", "llamacpp": "llamacpp", "litellm": "litellm",
             "vllm": "custom", "openai": "custom"}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


# No proxy from the environment, no redirects: this must stay on the loopback port.
_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())


def _get(port: int, path: str, timeout: float) -> Tuple[str, Any]:
    """GET http://127.0.0.1:<port><path> -> (``ok`` | ``auth`` | ``none``, parsed JSON or None)."""
    request = urllib.request.Request("http://%s:%d%s" % (HOST, port, path), headers={"Accept": "application/json"})
    try:
        with _OPENER.open(request, timeout=timeout) as response:
            body = response.read(MAX_BODY)
    except urllib.error.HTTPError as e:
        return ("auth" if e.code in (401, 403) else "none"), None
    except (urllib.error.URLError, socket.timeout, TimeoutError, OSError, ValueError):
        return "none", None
    try:
        return "ok", json.loads(body.decode("utf-8", "replace"))
    except ValueError:
        return "ok", None


def _ids(items: Any, key: str) -> List[str]:
    out = []
    if isinstance(items, list):
        for item in items:
            value = item.get(key) if isinstance(item, dict) else None
            if isinstance(value, str) and value:
                out.append(value[:200])
    return out[:MAX_MODELS]


def _server(kind: str, port: int, models: List[str], needs_key: bool = False) -> Dict[str, Any]:
    return {"id": "%s-%d" % (kind, port), "kind": kind, "name": NAMES[kind], "port": port,
            "baseUrl": "http://%s:%d/v1" % (HOST, port), "models": models, "count": len(models),
            "needsKey": needs_key, "provider": PROVIDERS[kind]}


def _ollama(port: int, timeout: float) -> Optional[Dict[str, Any]]:
    state, data = _get(port, "/api/version", timeout)
    if state != "ok" or not isinstance(data, dict) or not isinstance(data.get("version"), str):
        return None
    state, tags = _get(port, "/api/tags", timeout)
    models = _ids(tags.get("models"), "name") if isinstance(tags, dict) else []
    return _server("ollama", port, models)


def _kind_of(port: int, models_data: Any, timeout: float) -> str:
    """Name the server only when it says so itself; otherwise "openai"."""
    if port == 1234:
        state, data = _get(port, "/api/v0/models", timeout)      # LM Studio's own model list
        if state == "ok" and isinstance(data, dict) and isinstance(data.get("data"), list):
            return "lmstudio"
    elif port == 8080:
        state, data = _get(port, "/props", timeout)              # llama.cpp's server settings
        if state == "ok" and isinstance(data, dict) and ("default_generation_settings" in data or "total_slots" in data):
            return "llamacpp"
    elif port == 4000:
        # LiteLLM's health endpoints need no key, even when /v1/models does.
        state, data = _get(port, "/health/readiness", timeout)
        if state == "ok" and isinstance(data, dict) and "litellm_version" in data:
            return "litellm"
        state, data = _get(port, "/health/liveliness", timeout)
        if state == "ok" and isinstance(data, str) and data.strip().lower().startswith("i'm alive"):
            return "litellm"
    elif port == 8000:
        items = models_data.get("data") if isinstance(models_data, dict) else None
        if isinstance(items, list) and items and all(isinstance(i, dict) and i.get("owned_by") == "vllm" for i in items):
            return "vllm"
    return "openai"


def scan_port(port: int, timeout: float = TIMEOUT) -> Optional[Dict[str, Any]]:
    if port == 11434:
        found = _ollama(port, timeout)
        if found:
            return found
    state, data = _get(port, "/v1/models", timeout)
    if state == "auth":
        # Wants a key: it is there. Say what it is only when its open endpoints tell.
        return _server(_kind_of(port, None, timeout), port, [], True)
    items = data.get("data") if isinstance(data, dict) else None
    if state != "ok" or not isinstance(items, list):
        return None
    return _server(_kind_of(port, data, timeout), port, _ids(items, "id"))


def _ports_from_env() -> List[int]:
    """KDEAICHAT_LOCAL_PORTS="18765,1234" replaces the fixed ports (tests and the docs media,
    so a real local server never shows up there); unset means PORTS."""
    raw = os.environ.get("KDEAICHAT_LOCAL_PORTS")
    if raw is None:
        return PORTS
    return [int(p) for p in raw.split(",") if p.strip().isdigit() and 0 < int(p) < 65536]


def scan(ports: Optional[List[int]] = None, timeout: float = TIMEOUT) -> List[Dict[str, Any]]:
    ports = _ports_from_env() if ports is None else ports
    with ThreadPoolExecutor(max_workers=len(ports) or 1) as pool:
        results = list(pool.map(lambda p: _safe(p, timeout), ports))
    return [r for r in results if r]


def _safe(port: int, timeout: float) -> Optional[Dict[str, Any]]:
    try:
        return scan_port(port, timeout)
    except Exception:  # one odd server must not hide the others
        return None


def cmd_local_servers_scan(payload: Dict[str, Any]) -> None:
    print(json.dumps({"servers": scan()}, ensure_ascii=False))


COMMANDS = {"local_servers_scan": cmd_local_servers_scan}
