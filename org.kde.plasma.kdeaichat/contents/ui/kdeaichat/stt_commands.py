"""Speech-to-text helper commands (the widget's and the Voice settings' back end).

Every command takes the widget's ``stt*`` settings in its payload (see
``stt_settings.from_payload``) and prints exactly one JSON line:

  stt_engines         {"type": "stt_engines", "engines": [{id, available, reason, ...}], "recorder", "cached_models", "gpu"}
  stt_transcribe      {wav} -> {"type": "stt_result", "text", "engine", ...} | {"type": "stt_error", "error", "code"}
  stt_test            transcribes the bundled voice/stt-test.wav; adds "expected"
  stt_dictate         records until stt_stop (max 5 min), then like stt_transcribe; or {"type": "stt_stopped"}
  stt_stop            {cancel?} -> {"type": "stt_stopping"} | {"type": "stt_stopped"}
  stt_models          -> {"type": "stt_models", "faster_whisper": [{name, mb, downloaded, recommended, note}],
                         "parakeet": [{name, label, mb, downloaded, path, source, ...}],
                         "found": [{engine, model, path, name, source, mb}]} (Speech Note, Handy, HF cache, whisper.cpp)
  stt_setup_size      {sttEngine, sttModel, gpu: "auto"|true|false} -> {"type": "stt_setup_size", "total_mb", "items", ...}
  stt_download_model  {sttEngine, sttModel} -> {"type": "stt_downloaded", "path"} (only after the UI showed the size)
  stt_sync_units      {sttEnabled, sttEngine} -> {"type": "stt_units", ...} (widget start; see stt_units)
  stt_service_status  -> the service's /status (this starts it if it is socket-activated)
"""
import json
import os
import shutil
import tempfile
from typing import Any, Callable, Dict

from kdeaichat import (stt_engines, stt_http, stt_models, stt_parakeet, stt_record, stt_setup, stt_units, voice_data,
                       voice_services)
from kdeaichat.common import safe_path
from kdeaichat.stt_http import EngineError
from kdeaichat.stt_settings import SettingsError, from_payload, port, runtime_dir

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


def engines(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """Which engines can work here, for the settings dropdown (starts nothing)."""
    return {"type": "stt_engines", "engines": stt_engines.available(settings), "recorder": stt_record.recorder_name(),
            "cached_models": stt_setup.cached_models(), "gpu": stt_engines.nvidia_gpu(), "selected": settings["engine"]}


def transcribe(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """Transcribe a WAV file the user has (16 kHz mono works with every engine)."""
    wav = safe_path(payload.get("wav"))
    if not os.path.isfile(wav):
        raise ValueError("WAV file not found")
    return stt_engines.transcribe(wav, settings)


def test(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """Transcribe the bundled sample, so a choice can be tried before saving."""
    folder = tempfile.mkdtemp(prefix="stt-test-", dir=runtime_dir())
    try:
        wav = os.path.join(folder, "speech.wav")
        shutil.copyfile(TEST_WAV, wav)  # a private copy the service may read
        reply = stt_engines.transcribe(wav, settings)
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    reply["expected"] = TEST_TEXT
    return reply


def dictate(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """Record until stt_stop, then transcribe with the chosen engine."""
    return stt_record.dictate(settings, stt_engines.transcribe)


def models(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """The faster-whisper model list and models other apps already downloaded."""
    gpu = stt_engines.nvidia_gpu()
    return {"type": "stt_models", "gpu": gpu, "faster_whisper": stt_models.catalogue(gpu),
            "parakeet": stt_parakeet.catalogue(), "found": stt_models.discover()}


def setup_size(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """What installing the chosen local engine and its model would download."""
    if settings["engine"] == "parakeet":
        return stt_setup.estimate_parakeet(settings["parakeet_model"], settings["venv"],
                                           stt_parakeet.resolve(settings["parakeet_model"]))
    return stt_setup.estimate(settings["model"], settings["venv"], payload.get("gpu", "auto"), stt_engines.nvidia_gpu())


def download_model(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    """Download the chosen model: Parakeet's here (checked against its SHA-256), a faster-whisper
    model through the service (HuggingFace cache).

    A faster-whisper model that was not on disk before is recorded as ours, so "Remove" may delete
    it later; Parakeet's download folder is entirely ours.
    """
    if settings["engine"] == "parakeet":
        if settings["parakeet_model"] != stt_parakeet.NAME:
            raise ValueError("only the default Parakeet model can be downloaded")
        try:
            return stt_parakeet.download()
        except stt_parakeet.DownloadError as e:
            raise EngineError(str(e), "download_failed") from None
    model = settings["model"]
    had_it = bool(stt_setup.cached_model(model))
    token = voice_services.ensure_voice_http_token(stt_engines.token_path())
    reply = stt_http.service_call("/download", {"model": model}, token, port(), timeout=3600)
    if reply.get("type") == "stt_downloaded" and not had_it and stt_setup.cached_model(model):
        voice_data.record_download(model)
    return reply


def service_status(payload: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    token = voice_services.ensure_voice_http_token(stt_engines.token_path())
    status = stt_http.service_status(token, port())
    return dict(status or {}, type="stt_service", running=status is not None)


def cmd_stt_stop(payload: Dict[str, Any]) -> None:
    _emit(stt_record.stop(payload.get("cancel") is True))


def cmd_stt_sync_units(payload: Dict[str, Any]) -> None:
    _emit(dict(stt_units.sync(payload), type="stt_units"))


COMMANDS = {
    "stt_engines": _with_settings(engines),
    "stt_transcribe": _with_settings(transcribe),
    "stt_test": _with_settings(test),
    "stt_dictate": _with_settings(dictate),
    "stt_stop": cmd_stt_stop,
    "stt_models": _with_settings(models),
    "stt_setup_size": _with_settings(setup_size),
    "stt_download_model": _with_settings(download_model),
    "stt_sync_units": cmd_stt_sync_units,
    "stt_service_status": _with_settings(service_status),
}
