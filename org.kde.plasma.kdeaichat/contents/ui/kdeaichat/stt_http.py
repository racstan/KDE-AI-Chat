"""HTTP speech-to-text: the OpenAI-compatible speech server (``/audio/transcriptions``).

stdlib only (urllib). The remote key comes from KWallet and only lives in
this process's memory: it is sent in the Authorization header and never
logged, printed or put in an error message.
"""
import json
import os
import secrets
import urllib.error
import urllib.request
from typing import Any, Dict, Optional, Tuple

from kdeaichat import http_safe

MAX_REPLY = 2 * 1024 * 1024


class EngineError(Exception):
    def __init__(self, message: str, code: str = "failed"):
        super().__init__(message)
        self.code = code


def multipart(fields: Dict[str, str], wav: str) -> Tuple[bytes, str]:
    boundary = "kdeaichat-" + secrets.token_hex(12)
    parts = []
    for name, value in fields.items():
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n"
                      % (boundary, name, value)).encode("utf-8"))
    with open(wav, "rb") as f:
        audio = f.read()
    parts.append(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n"
                  "Content-Type: audio/wav\r\n\r\n" % boundary).encode("ascii") + audio + b"\r\n")
    parts.append(("--%s--\r\n" % boundary).encode("ascii"))
    return b"".join(parts), "multipart/form-data; boundary=" + boundary


def _error_detail(body: bytes) -> str:
    try:
        data = json.loads(body.decode("utf-8", "replace"))
        if isinstance(data, dict):
            err = data.get("error")
            if isinstance(err, dict):
                err = err.get("message")
            if err:
                return str(err)[:300]
    except ValueError:
        pass
    return body.decode("utf-8", "replace").strip()[:200]


def post(url: str, body: bytes, content_type: str, headers: Optional[Dict[str, str]] = None,
         timeout: float = 120) -> Dict[str, Any]:
    request = urllib.request.Request(url, data=body, method="POST")
    request.add_header("Content-Type", content_type)
    for name, value in (headers or {}).items():
        request.add_header(name, value)
    try:
        with http_safe.urlopen(request, timeout=timeout) as response:
            raw = response.read(MAX_REPLY + 1)
    except urllib.error.HTTPError as e:
        detail = _error_detail(e.read(4096) if e.fp else b"")
        code = "auth" if e.code in (401, 403) else "http"
        raise EngineError("HTTP %d%s" % (e.code, (": " + detail) if detail else ""), code) from None
    except (urllib.error.URLError, OSError) as e:
        reason = getattr(e, "reason", e)
        raise EngineError("can't reach %s (%s)" % (url.split("?")[0], reason), "unreachable") from None
    if len(raw) > MAX_REPLY:
        raise EngineError("the reply is too large", "bad_reply")
    text = raw.decode("utf-8", "replace")
    try:
        data = json.loads(text)
    except ValueError:
        return {"text": text.strip()}  # response_format=text servers
    if not isinstance(data, dict):
        raise EngineError("unexpected reply", "bad_reply")
    return data


def transcriptions_url(base: str) -> str:
    return base if base.endswith("/audio/transcriptions") else base + "/audio/transcriptions"


def remote(wav: str, settings: Dict[str, Any], key: str) -> Dict[str, Any]:
    """OpenAI-compatible ``POST {url}/audio/transcriptions`` (OpenAI, Groq, local whisper servers)."""
    if not settings["remote_url"]:
        raise EngineError("no server URL is set", "not_configured")
    fields = {"model": settings["remote_model"], "response_format": "json"}
    if settings["language"] != "auto":
        fields["language"] = settings["language"].split("-")[0]
    body, ctype = multipart(fields, wav)
    headers = {"Authorization": "Bearer " + key} if key else {}
    url = transcriptions_url(settings["remote_url"])
    data = post(url, body, ctype, headers)
    reply = {"text": str(data.get("text", "")).strip(), "model": settings["remote_model"]}
    if key and http_safe.insecure_key_url(url):
        reply["warning"] = http_safe.INSECURE_KEY_WARNING
    return reply


def wav_exists(path: str) -> bool:
    return bool(path) and os.path.isfile(path)
