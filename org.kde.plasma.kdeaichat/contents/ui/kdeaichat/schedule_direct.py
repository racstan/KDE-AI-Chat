"""A direct-mode scheduled run: one non-streaming request to the chat's provider.

Request shapes follow backends/DirectBackend.js ``buildRequest`` (OpenAI-
compatible ``/chat/completions``, which also covers Gemini's endpoint, and
Anthropic ``/messages``); no tools, no streaming. The answer's
``<think>...</think>`` part becomes the reasoning, as in the widget.
"""
import json
import re
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional

from kdeaichat import http_safe

MAX_RESPONSE_BYTES = 20_000_000


class RunError(Exception):
    """A run that failed with a message for the user (never contains the key)."""


def build_request(cfg: Dict[str, Any], key: str, model: str, system: str,
                  messages: List[Dict[str, str]], max_tokens: int) -> Dict[str, Any]:
    headers = {"Content-Type": "application/json"}
    base = cfg["baseUrl"].rstrip("/")
    if cfg["type"] == "anthropic":
        url = (base or "https://api.anthropic.com/v1")
        if not url.endswith("/messages"):
            url += "/messages"
        headers["x-api-key"] = key
        headers["anthropic-version"] = "2023-06-01"
        body: Dict[str, Any] = {"model": model, "max_tokens": max_tokens, "messages": messages, "stream": False}
        if system:
            body["system"] = system
    else:
        url = base + "/chat/completions"
        if key:
            headers["Authorization"] = "Bearer " + key
        body = {"model": model, "messages": ([{"role": "system", "content": system}] if system else []) + messages,
                "max_tokens": max_tokens, "stream": False}
        if re.match(r"^https?://([^/]*\.)?openrouter\.ai(/|$)", base, re.I):
            body["usage"] = {"include": True}
    for name, value in (cfg.get("headers") or {}).items():
        if value:
            headers[str(name)] = str(value)
    return {"url": url, "headers": headers, "body": body}


def _error_message(status: int, text: str, url: str) -> str:
    detail = ""
    try:
        obj = json.loads(text)
        err = obj.get("error", obj) if isinstance(obj, dict) else obj
        if isinstance(err, str):
            detail = err
        elif isinstance(err, dict) and err.get("message"):
            detail = str(err["message"])
        elif isinstance(obj, dict) and obj.get("message"):
            detail = str(obj["message"])
    except ValueError:
        detail = text[:300].strip()
    if status in (401, 403):
        return f"The provider rejected the API key (HTTP {status})." + (f" {detail}" if detail else "")
    return f"Request to {url} failed (HTTP {status})" + (f": {detail}" if detail else "")


def split_think(text: str) -> Dict[str, str]:
    """``<think>…</think>`` blocks out of the answer, into the reasoning."""
    reasoning = "\n".join(m.strip() for m in re.findall(r"<think>(.*?)(?:</think>|$)", text, re.S))
    answer = re.sub(r"<think>.*?(?:</think>|$)", "", text, flags=re.S).strip()
    return {"content": answer, "reasoning": reasoning}


def _text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(str(p.get("text", "")) for p in content if isinstance(p, dict) and p.get("type") == "text")
    return ""


def parse_response(kind: str, obj: Dict[str, Any]) -> Dict[str, Any]:
    """{content, reasoning, tokens?, cost?} from a full (non-streaming) response."""
    usage = obj.get("usage") if isinstance(obj.get("usage"), dict) else {}
    if kind == "anthropic":
        blocks = [b for b in obj.get("content") or [] if isinstance(b, dict)]
        out = split_think("".join(str(b.get("text", "")) for b in blocks if b.get("type") == "text"))
        thinking = "\n".join(str(b.get("thinking", "")) for b in blocks if b.get("type") == "thinking")
        out["reasoning"] = "\n".join(t for t in (thinking, out["reasoning"]) if t)
        if usage:
            out["tokens"] = {"input": int(usage.get("input_tokens") or 0) + int(usage.get("cache_read_input_tokens") or 0)
                             + int(usage.get("cache_creation_input_tokens") or 0), "output": int(usage.get("output_tokens") or 0)}
    else:
        choice = (obj.get("choices") or [{}])[0] or {}
        message = choice.get("message") or {}
        out = split_think(_text(message.get("content")))
        extra = message.get("reasoning") or message.get("reasoning_content") or ""
        out["reasoning"] = "\n".join(t for t in (str(extra), out["reasoning"]) if t)
        if usage:
            out["tokens"] = {"input": int(usage.get("prompt_tokens") or usage.get("input_tokens") or 0),
                             "output": int(usage.get("completion_tokens") or usage.get("output_tokens") or 0)}
            if isinstance(usage.get("cost"), (int, float)) and usage["cost"] >= 0:
                out["cost"] = usage["cost"]
    if obj.get("error"):
        err = obj["error"]
        raise RunError(str(err.get("message") if isinstance(err, dict) else err))
    return out


def send(cfg: Dict[str, Any], key: str, model: str, system: str, messages: List[Dict[str, str]],
         max_tokens: int, timeout: float, opener: Optional[Any] = None) -> Dict[str, Any]:
    """Sends the request; returns parse_response's dict. Raises RunError."""
    req = build_request(cfg, key, model, system, messages, max_tokens)
    data = json.dumps(req["body"]).encode("utf-8")
    request = urllib.request.Request(req["url"], data=data, headers=req["headers"], method="POST")
    try:
        with (opener or http_safe.urlopen)(request, timeout=timeout) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as e:
        body = e.read(100000).decode("utf-8", "replace")
        raise RunError(_error_message(e.code, body, req["url"])) from None
    except (urllib.error.URLError, OSError) as e:
        reason = getattr(e, "reason", e)
        if "timed out" in str(reason):
            raise RunError(f"Request to {req['url']} timed out after {int(timeout)} seconds.") from None
        raise RunError(f"Could not reach {req['url']}: {reason}") from None
    if len(raw) > MAX_RESPONSE_BYTES:
        raise RunError("The provider's response was too large.")
    try:
        obj = json.loads(raw.decode("utf-8"))
    except ValueError:
        raise RunError("Could not read the provider's response.") from None
    if not isinstance(obj, dict):
        raise RunError("Could not read the provider's response.")
    result = parse_response(cfg["type"], obj)
    if key and http_safe.insecure_key_url(req["url"]):
        result["warning"] = http_safe.INSECURE_KEY_WARNING
    return result
