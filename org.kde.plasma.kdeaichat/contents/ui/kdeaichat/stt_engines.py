"""Speech-to-text through the speech server: a WAV file in, text out.

``remote``: an OpenAI-compatible ``/audio/transcriptions`` URL; the key is read from KWallet (entry
``stt-remote``) here, never passed in argv. Speech Note (the default dictation engine) listens with
its own microphone through the ``speechnote_*`` commands, so it has no adapter here.
"""
import time
from typing import Any, Callable, Dict
from urllib.parse import urlsplit

from kdeaichat import schedule_wallet, stt_http
from kdeaichat.stt_http import EngineError
from kdeaichat.stt_settings import WALLET_ENTRY


def remote(wav: str, s: Dict[str, Any], read_key: Callable[[str], str] = None) -> Dict[str, Any]:
    try:
        key = (read_key or schedule_wallet.read_key)(WALLET_ENTRY)
    except schedule_wallet.WalletUnavailable as e:
        # A server on this computer usually needs no key; anything else does.
        if urlsplit(s["remote_url"]).hostname not in ("localhost", "127.0.0.1", "::1"):
            raise EngineError("Can't read the speech server's key: %s." % e.reason, "wallet") from None
        key = ""
    return stt_http.remote(wav, s, key)


ADAPTERS = {"remote": remote}


def transcribe(wav: str, settings: Dict[str, Any]) -> Dict[str, Any]:
    """{"type": "stt_result", "text", "engine", ...} or {"type": "stt_error", "error", "code"}."""
    engine = settings["engine"]
    started = time.monotonic()
    if engine not in ADAPTERS:   # Speech Note listens through the speechnote_* commands
        return {"type": "stt_error", "engine": engine, "error": "this engine is not run by stt_* commands", "code": "bad_request"}
    try:
        reply = dict(ADAPTERS[engine](wav, settings))
    except EngineError as e:
        return {"type": "stt_error", "engine": engine, "error": str(e), "code": e.code}
    reply.update({"type": "stt_result", "engine": engine, "seconds": round(time.monotonic() - started, 2)})
    reply["text"] = str(reply.get("text", "")).strip()
    return reply
