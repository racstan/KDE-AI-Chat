"""Speech-to-text helper commands for the speech server engine (the widget's and the Voice settings' back end).

Every command takes the widget's ``stt*`` settings in its payload (see
``stt_settings.from_payload``) and prints exactly one JSON line:

  stt_transcribe      {wav} -> {"type": "stt_result", "text", "engine", ...} | {"type": "stt_error", "error", "code"}
  stt_test            transcribes the bundled voice/stt-test.wav; adds "expected"
  stt_dictate         records until stt_stop (max 5 min), then like stt_transcribe; or {"type": "stt_stopped"}
  stt_stop            {cancel?} -> {"type": "stt_stopping"} | {"type": "stt_stopped"}

Speech Note, the default engine, has its own ``speechnote_*`` commands (kdeaichat/speechnote.py).
"""
import json
import os
import shutil
import tempfile
from typing import Any, Callable, Dict

from kdeaichat import stt_engines, stt_record
from kdeaichat.common import safe_path
from kdeaichat.stt_http import EngineError
from kdeaichat.stt_settings import SettingsError, from_payload, runtime_dir

TEST_WAV = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "voice", "stt-test.wav")
TEST_TEXT = "Hello, this is a speech test."


def _emit(data: Dict[str, Any]) -> None:
    print(json.dumps(data), flush=True)


def _with_settings(fn: Callable[[Dict[str, Any], Dict[str, Any]], Dict[str, Any]]) -> Callable[[Dict[str, Any]], None]:
    def command(payload: Dict[str, Any]) -> None:
        try:
            settings = from_payload(payload)
        except SettingsError as e:
            _emit({"type": "stt_error", "error": str(e), "code": "bad_settings"})
            return
        try:
            _emit(fn(payload, settings))
        except (SettingsError, ValueError) as e:
            _emit({"type": "stt_error", "error": str(e), "code": "bad_request"})
        except EngineError as e:
            _emit({"type": "stt_error", "error": str(e), "code": e.code})
    command.__doc__ = fn.__doc__
    return command


def transcribe(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """Transcribe a WAV file the user has (16 kHz mono works with every server)."""
    wav = safe_path(payload.get("wav"))
    if not os.path.isfile(wav):
        raise ValueError("WAV file not found")
    return stt_engines.transcribe(wav, settings)


def test(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """Transcribe the bundled sample, so the server can be tried before saving."""
    folder = tempfile.mkdtemp(prefix="stt-test-", dir=runtime_dir())
    try:
        wav = os.path.join(folder, "speech.wav")
        shutil.copyfile(TEST_WAV, wav)  # a private copy
        reply = stt_engines.transcribe(wav, settings)
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    reply["expected"] = TEST_TEXT
    return reply


def dictate(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """Record until stt_stop, then transcribe with the speech server."""
    return stt_record.dictate(settings, stt_engines.transcribe)


def cmd_stt_stop(payload: Dict[str, Any]) -> None:
    _emit(stt_record.stop(payload.get("cancel") is True))


COMMANDS = {
    "stt_transcribe": _with_settings(transcribe),
    "stt_test": _with_settings(test),
    "stt_dictate": _with_settings(dictate),
    "stt_stop": cmd_stt_stop,
}
