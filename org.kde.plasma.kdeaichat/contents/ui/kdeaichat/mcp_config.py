"""The user's MCP servers: ~/.local/share/kdeaichat/mcp.json and importing from other apps.

mcp.json has the usual shape, {"mcpServers": {<id>: {command, args, env, cwd | url, headers, enabled}}}.
It holds no secrets: an env or header value is either a plain string or
{"secret": "<NAME>"}, a field of the KWallet entry `mcp-<id>` that the widget
fills in before talking to the bridge. Payloads travel in argv, so a secret's
value never comes through here: a "value" next to a placeholder is dropped.
"""
import json
import os
import re
from typing import Any, Dict, List
from urllib.parse import urlparse

from kdeaichat import chats

ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,39}\Z")
SECRET_NAME = re.compile(r"^[A-Za-z0-9_.-]{1,80}\Z")
SECRETISH = re.compile(r"key|token|secret|password|passwd|auth|credential", re.I)


def config_path() -> str:
    return os.path.join(chats.data_root(), "mcp.json")


def _load() -> Dict[str, Any]:
    try:
        with open(config_path(), encoding="utf-8") as f:
            data = json.load(f)
        servers = data.get("mcpServers")
        return servers if isinstance(servers, dict) else {}
    except (OSError, ValueError, AttributeError):
        return {}


def _store(servers: Dict[str, Any]) -> None:
    os.makedirs(chats.data_root(), mode=0o700, exist_ok=True)
    path = config_path()
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({"mcpServers": servers}, f, indent=2, sort_keys=True)
    os.replace(tmp, path)


def _text(value: Any, what: str, limit: int = 4096) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > limit or "\0" in value or "\n" in value:
        raise ValueError(f"{what} isn't valid.")
    return value.strip()


def _pairs(value: Any, what: str) -> Dict[str, Any]:
    if value in (None, ""):
        return {}
    if not isinstance(value, dict) or len(value) > 100:
        raise ValueError(f"{what} must be a set of names and values.")
    out: Dict[str, Any] = {}
    for key, item in value.items():
        if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", key):
            raise ValueError(f"{what}: {str(key)[:40]!r} isn't a valid name.")
        if isinstance(item, dict):
            name = item.get("secret")
            if not isinstance(name, str) or not SECRET_NAME.match(name):
                raise ValueError(f"{what}: the secret for {key} needs a plain name.")
            out[key] = {"secret": name}
        elif isinstance(item, (str, int, float)) and not isinstance(item, bool):
            out[key] = str(item)
        else:
            raise ValueError(f"{what}: the value of {key} isn't text.")
    return out


def validate(server: Any) -> Dict[str, Any]:
    """The cleaned definition to store, or ValueError with a message for the user."""
    if not isinstance(server, dict):
        raise ValueError("Not a server.")
    sid = server.get("id")
    if not isinstance(sid, str) or not ID_RE.match(sid):
        raise ValueError("The id must be 1-40 characters: lowercase letters, digits, - and _ (starting with a letter or digit).")
    out: Dict[str, Any] = {"id": sid, "enabled": server.get("enabled", True) is not False}
    if server.get("command") and server.get("url"):
        raise ValueError("A server has either a command or a url, not both.")
    if server.get("url"):
        url = _text(server["url"], "The url", 2048)
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            raise ValueError("The url must start with http:// or https://.")
        out.update(url=url, headers=_pairs(server.get("headers"), "Headers"))
    elif server.get("command"):
        args = server.get("args") or []
        if not isinstance(args, list) or len(args) > 200:
            raise ValueError("The arguments must be a list.")
        out.update(command=_text(server["command"], "The command", 1024), args=[_text(a, "An argument") if a != "" else "" for a in args],
                   env=_pairs(server.get("env"), "Environment"))
        if server.get("cwd"):
            out["cwd"] = _text(server["cwd"], "The folder", 1024)
    else:
        raise ValueError("A server needs a command or a url.")
    return out


def cmd_mcp_list(payload: Dict[str, Any]) -> None:
    servers = _load()
    print(json.dumps({"status": "ok", "servers": [dict(servers[k], id=k) for k in sorted(servers)]}))


def cmd_mcp_save(payload: Dict[str, Any]) -> None:
    try:
        server = validate(payload.get("server"))
    except ValueError as e:
        print(json.dumps({"status": "error", "message": str(e)}))
        return
    servers = _load()
    sid = server.pop("id")
    servers[sid] = server
    _store(servers)
    print(json.dumps({"status": "ok", "id": sid}))


def cmd_mcp_delete(payload: Dict[str, Any]) -> None:
    sid = payload.get("id")
    servers = _load()
    if not isinstance(sid, str) or sid not in servers:
        print(json.dumps({"status": "error", "message": "No such server."}))
        return
    del servers[sid]
    _store(servers)
    print(json.dumps({"status": "ok", "id": sid}))


# ---- import ------------------------------------------------------------------

def parse_jsonc(text: str) -> Any:
    """JSON with // and /* */ comments and trailing commas (OpenCode's .jsonc)."""
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        else:
            out.append(c)
        i += 1
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))


def _read_json(path: str) -> Any:
    try:
        with open(path, encoding="utf-8") as f:
            return parse_jsonc(f.read())
    except (OSError, ValueError):
        return None


def _candidate(name: str, raw: Any, source: str, opencode: bool) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        return {}
    sid = re.sub(r"[^a-z0-9_-]+", "-", str(name).lower()).strip("-_")[:40] or "server"
    if opencode:
        remote = raw.get("type") == "remote"
        command = raw.get("command") if not remote else None
        parts = [str(p) for p in command] if isinstance(command, list) else ([command] if isinstance(command, str) else [])
        env, headers = raw.get("environment"), raw.get("headers")
        enabled = raw.get("enabled", True) is not False
    else:
        remote = bool(raw.get("url"))
        parts = [str(raw["command"])] + [str(a) for a in raw.get("args") or []] if raw.get("command") else []
        env, headers = raw.get("env"), raw.get("headers")
        enabled = True
    out: Dict[str, Any] = {"id": sid, "name": str(name), "source": source, "enabled": enabled}
    if remote and raw.get("url"):
        out.update(url=raw["url"], headers=_import_pairs(headers, True))
    elif parts:
        out.update(command=parts[0], args=parts[1:], env=_import_pairs(env, False))
        if raw.get("cwd"):
            out["cwd"] = raw["cwd"]
    else:
        return {}
    try:
        validate(_checkable(out))
    except ValueError as e:
        out["problem"] = str(e)
    return out


def _import_pairs(value: Any, headers: bool) -> Dict[str, Any]:
    """Likely secrets become {"secret": NAME, "value": v} so the widget can put v in the wallet; others stay text."""
    out: Dict[str, Any] = {}
    for key, item in (value if isinstance(value, dict) else {}).items():
        if isinstance(item, (str, int, float)) and not isinstance(item, bool):
            secret = SECRETISH.search(str(key)) or (headers and str(key).lower() == "authorization")
            out[str(key)] = {"secret": re.sub(r"[^A-Za-z0-9_.-]", "_", str(key))[:80], "value": str(item)} if secret else str(item)
    return out


def _checkable(candidate: Dict[str, Any]) -> Dict[str, Any]:
    """The candidate without secret values, as mcp_save would be given it."""
    out = dict(candidate)
    for key in ("env", "headers"):
        if key in out:
            out[key] = {k: ({"secret": v["secret"]} if isinstance(v, dict) else v) for k, v in out[key].items()}
    return out


def cmd_mcp_import(payload: Dict[str, Any]) -> None:
    """Candidates from Claude Desktop and OpenCode configs; nothing is saved."""
    home = os.path.expanduser("~")
    found: List[Dict[str, Any]] = []
    desktop = _read_json(os.path.join(home, ".config", "Claude", "claude_desktop_config.json"))
    for name, raw in ((desktop or {}).get("mcpServers") or {}).items() if isinstance(desktop, dict) else []:
        found.append(_candidate(name, raw, "Claude Desktop", False))
    for filename in ("opencode.json", "opencode.jsonc"):
        config = _read_json(os.path.join(home, ".config", "opencode", filename))
        for name, raw in (config.get("mcp") or {}).items() if isinstance(config, dict) and isinstance(config.get("mcp"), dict) else []:
            found.append(_candidate(name, raw, "OpenCode", True))
    existing = _load()
    found = [c for c in found if c]
    for c in found:
        c["exists"] = c["id"] in existing
    print(json.dumps({"status": "ok", "servers": found}))


COMMANDS = {
    "mcp_list": cmd_mcp_list,
    "mcp_save": cmd_mcp_save,
    "mcp_delete": cmd_mcp_delete,
    "mcp_import": cmd_mcp_import,
}
