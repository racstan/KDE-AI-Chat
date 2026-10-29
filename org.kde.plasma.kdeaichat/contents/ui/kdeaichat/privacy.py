"""Where API keys and chat history sit on disk, for the 1.4.0 migration.

Older versions stored API keys in plaintext in Plasma's applet config
(plasma-org.kde.plasma.desktop-appletsrc), in ~/.config/kdeaichatrc and in
custom provider JSON, and kept all chats in one config entry. The widget now
keeps keys in KWallet and chats in per-chat files. This module finds what is
left behind.

Reports name keys but never include their values.
"""
import json
import os
import re
from typing import Any, Dict, Iterator, Tuple

PLUGIN_IDS = ("org.kde.plasma.kdeaichat", "org.kde.plasma.kdeaichat.dev")
KEY_NAME = re.compile(r"^(apiKey|[A-Za-z]+ApiKey)\Z")
MAX_FILE_BYTES = 64 * 1024 * 1024

# Every API-key setting the widget has ever declared, mapped to the provider
# id its key is stored under in KWallet (folder "KDEAIChat").
LEGACY_KEY_PROVIDERS = {
    "apiKey": "openai",
    "anthropicApiKey": "anthropic",
    "groqApiKey": "groq",
    "deepSeekApiKey": "deepseek",
    "miniMaxApiKey": "minimax",
    "fireworksApiKey": "fireworks",
    "googleApiKey": "google",
    "openRouterApiKey": "openrouter",
    "mistralApiKey": "mistral",
    "cloudflareApiKey": "cloudflare",
    "nvidiaApiKey": "nvidia",
    "huggingFaceApiKey": "huggingface",
    "xaiApiKey": "xai",
    "litellmApiKey": "litellm",
    "maritacaApiKey": "maritaca",
    "perplexityApiKey": "perplexity",
    "qwenApiKey": "qwen",
    "moonshotApiKey": "moonshot",
    "mimoApiKey": "mimo",
    "huggingfaceImageApiKey": "huggingface-image",
    "replicateApiKey": "replicate",
    "stabilityApiKey": "stability",
    "togetherImageApiKey": "together-image",
}

_ESCAPES = {"s": " ", "t": "\t", "n": "\n", "r": "\r", "\\": "\\", ";": ";", ",": ","}


def _config_dir() -> str:
    return os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")


def _unescape(value: str) -> str:
    """Undo KConfig value escaping (\\s, \\n, \\xNN, ...)."""
    out = []
    i = 0
    while i < len(value):
        ch = value[i]
        if ch == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            if nxt == "x" and i + 3 < len(value):
                try:
                    out.append(chr(int(value[i + 2:i + 4], 16)))
                    i += 4
                    continue
                except ValueError:
                    pass
            out.append(_ESCAPES.get(nxt, nxt))
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def parse_kconfig(path: str) -> Iterator[Tuple[str, Dict[str, str]]]:
    """Yield (group, entries) for a KConfig INI file. Values are unescaped."""
    if not os.path.isfile(path) or os.path.getsize(path) > MAX_FILE_BYTES:
        return
    group, entries = "", {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line.startswith("[") and line.endswith("]"):
                if entries or group:
                    yield group, entries
                group, entries = line, {}
            elif "=" in line and not line.startswith("#"):
                key, value = line.split("=", 1)
                key = re.sub(r"\[\$[a-z]+\]$", "", key.strip())
                entries[key] = _unescape(value)
    if entries or group:
        yield group, entries


def read_kdeaichatrc_keys(path: str = "") -> Dict[str, str]:
    """{provider id: key} from kdeaichatrc, for moving into KWallet."""
    path = path or os.path.join(_config_dir(), "kdeaichatrc")
    keys = {}
    for _group, entries in parse_kconfig(path):
        for name, value in entries.items():
            provider = LEGACY_KEY_PROVIDERS.get(name)
            if provider and value.strip():
                keys[provider] = value.strip()
    return keys


def remove_kdeaichatrc(path: str = "") -> bool:
    """Delete kdeaichatrc. Nothing in the widget reads it any more."""
    path = path or os.path.join(_config_dir(), "kdeaichatrc")
    try:
        os.unlink(path)
        return True
    except FileNotFoundError:
        return False


def cmd_read_legacy_keyfile(payload: Dict[str, Any]) -> None:
    print(json.dumps({"keys": read_kdeaichatrc_keys()}))


def cmd_remove_legacy_keyfile(payload: Dict[str, Any]) -> None:
    print(json.dumps({"removed": remove_kdeaichatrc()}))


COMMANDS = {
    "read_legacy_keyfile": cmd_read_legacy_keyfile,
    "remove_legacy_keyfile": cmd_remove_legacy_keyfile,
}
