"""Reading the user's MCP server list (the common `mcpServers` format) for the tool bridge.

stdlib only; imported by tool_bridge_server.py by plain name. Bad entries are
reported, never raised: parse_servers returns the usable ones and the errors.
"""
import re
from typing import Any, Dict, List, Tuple
from urllib.parse import urlsplit

from mcp_clients import HEADER_NAME, SERVER_NAME

MAX_SERVERS = 64
MAX_STRING = 8192
TYPES = (None, "", "stdio", "http", "streamable-http")


def _strings(value: Any, what: str, limit: int) -> Dict[str, str]:
    if value is None:
        return {}
    if not isinstance(value, dict) or len(value) > limit:
        raise ValueError(f"{what} must be an object with at most {limit} entries")
    for key, item in value.items():
        if not isinstance(item, str) or len(item) > MAX_STRING or "\x00" in item:
            raise ValueError(f"{what} values must be text")
    return dict(value)


def parse_server(raw: Any) -> Dict[str, Any]:
    """The normalised definition of one server, or ValueError with the reason."""
    if not isinstance(raw, dict):
        raise ValueError("the entry must be an object")
    kind = raw.get("type")
    if kind not in TYPES:
        raise ValueError(f"the type \"{str(kind)[:30]}\" isn't supported (use stdio or http)")
    url = raw.get("url")
    if url not in (None, ""):
        if not isinstance(url, str) or len(url) > 4096 or re.search(r"[\x00-\x20\x7f]", url):
            raise ValueError("the url isn't valid")
        parts = urlsplit(url)
        if parts.scheme not in ("http", "https") or not parts.hostname:
            raise ValueError("the url must start with http:// or https://")
        if parts.username is not None or parts.password is not None:
            raise ValueError("the url must not contain a user name or password (use headers)")
        headers = _strings(raw.get("headers"), "headers", 50)
        for name, value in headers.items():
            if not HEADER_NAME.fullmatch(name) or re.search(r"[\r\n]", value):
                raise ValueError("a header name or value isn't valid")
        return {"kind": "http", "url": url, "headers": headers}
    if kind in ("http", "streamable-http"):
        raise ValueError("an http server needs a url")
    command = raw.get("command")
    if not isinstance(command, str) or not command.strip() or len(command) > 4096 or "\x00" in command:
        raise ValueError("the entry needs a command (stdio) or a url (http)")
    args = raw.get("args", [])
    if (not isinstance(args, list) or len(args) > 200
            or any(not isinstance(a, str) or len(a) > MAX_STRING or "\x00" in a for a in args)):
        raise ValueError("args must be a list of text")
    env = _strings(raw.get("env"), "env", 100)
    if any(not k or "=" in k or "\x00" in k for k in env):
        raise ValueError("an environment variable name isn't valid")
    cwd = raw.get("cwd")
    if cwd is not None and (not isinstance(cwd, str) or len(cwd) > 4096 or "\x00" in cwd):
        raise ValueError("cwd must be a folder path")
    return {"kind": "stdio", "command": command.strip(), "args": list(args), "env": env, "cwd": cwd or ""}


def parse_servers(value: Any) -> Tuple[Dict[str, Dict[str, Any]], List[Dict[str, str]]]:
    """({name: definition}, [{server, message}]) from the object in the `mcpServers` format."""
    if value is None:
        return {}, []
    if not isinstance(value, dict):
        return {}, [{"server": "", "message": "the servers must be an object"}]
    if "mcpServers" in value and isinstance(value["mcpServers"], dict):
        value = value["mcpServers"]
    servers: Dict[str, Dict[str, Any]] = {}
    errors: List[Dict[str, str]] = []
    for index, (name, raw) in enumerate(value.items()):
        label = str(name)[:64]
        if index >= MAX_SERVERS:
            errors.append({"server": label, "message": f"only {MAX_SERVERS} servers are used"})
            continue
        if not isinstance(name, str) or not SERVER_NAME.fullmatch(name):
            errors.append({"server": label, "message": "the name may only use letters, digits, . _ - (up to 64)"})
            continue
        try:
            servers[name] = parse_server(raw)
        except ValueError as exc:
            errors.append({"server": name, "message": str(exc)})
    return servers, errors
