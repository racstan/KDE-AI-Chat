"""Speech Note (the dsnote app by Michal Kosciesza) as the widget's dictation and read-aloud engine.

Speech Note's *service* is driven over D-Bus (see ``speechnote_bus``). Each
command prints one JSON line: a result below, or
``{"type": "speechnote_error", "error": <plain message>, "code": <code>}`` with
code one of not_installed, service_failed_to_start, not_configured, timeout,
busy, bus_error (or bad_request, mic_error, engine_error). Transcribed and
spoken text is never logged.

  speechnote_status       {start?: bool} -> {"type": "speechnote_status", installed, kind: "native"|"flatpak"|"",
                          running, state, ready, models_known, stt_models: [{id, name, lang}], tts_models: [...],
                          default_stt_model, default_tts_model, default_stt_lang, default_tts_lang}
                          Reads only, unless start is true (then it starts the service first and may report an error).
  speechnote_start        -> {"type": "speechnote_started", state, started: bool}; waits for State 3 (idle)
  speechnote_keepalive_service -> {"type": "speechnote_service_kept", running}; postpones the service's idle exit
                          (KeepAliveService); does nothing, and never starts it, when it is not running.
  speechnote_listen_start {model?, lang?} -> {"type": "speechnote_listening", task}; starts the service if needed and
                          uses the microphone. model is a model id from stt_models (it goes where the D-Bus API takes
                          a language or model id); empty means Speech Note's default.
  speechnote_keepalive    {task} -> {"type": "speechnote_keepalive", task, alive}; call every <= 8 s while listening
                          or reading (Speech Note cancels a task not kept alive for 10 s); alive false = task is over.
  speechnote_listen_stop  {task, timeout?: 20} -> {"type": "speechnote_text", text, lang, task}
  speechnote_listen_cancel {task} -> {"type": "speechnote_cancelled", task}
  speechnote_speak        {text, model?} -> {"type": "speechnote_speaking", task}; text goes in the private payload
                          file ("@..." argument), and the call to the service avoids the command line too.
  speechnote_pause / speechnote_resume / speechnote_stop {task} -> {"type": "speechnote_paused"|..., task, result}
  speechnote_wait_spoken  {task, timeout?: 3600, sentences?: bool} -> {"type": "speechnote_spoken", task}; returns when
                          the task is over (finished, stopped, or replaced). It keeps the task alive while it waits.
                          With sentences, it returns sooner with {"type": "speechnote_sentence", task, text} when
                          Speech Note starts reading a sentence (TtsPartialSpeechPlaying); the caller waits again.
"""
import json
import os
import re
import time
from typing import Any, Callable, Dict, Tuple

from kdeaichat import speechnote_bus as bus
from kdeaichat import minidbus
from kdeaichat.speechnote_bus import SpeechNoteError

MAX_TEXT = 500_000
_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$")
POLL = 1.0
KEEPALIVE_EVERY = 4.0
ENGINE_ERRORS = {1: ("mic_error", "Speech Note could not use the microphone"),
                 3: ("engine_error", "Speech Note's speech-to-text engine failed"),
                 4: ("engine_error", "Speech Note's text-to-speech engine failed")}


def _emit(data: Dict[str, Any]) -> None:
    print(json.dumps(data), flush=True)


def _command(fn: Callable[[Dict[str, Any]], Dict[str, Any]]) -> Callable[[Dict[str, Any]], None]:
    def run(payload: Dict[str, Any]) -> None:
        try:
            _emit(fn(payload))
        except SpeechNoteError as e:
            _emit({"type": "speechnote_error", "error": str(e), "code": e.code})
        except (minidbus.DBusError, OSError) as e:
            _emit({"type": "speechnote_error", "error": "D-Bus: %s" % (str(e) or "connection failed"), "code": "bus_error"})
        except ValueError as e:
            _emit({"type": "speechnote_error", "error": str(e), "code": "bad_request"})
    run.__doc__ = fn.__doc__
    return run


def _model(payload: Dict[str, Any]) -> str:
    """A model id (or language code) for the D-Bus ``lang`` argument; "" for the default."""
    value = str(payload.get("model") or payload.get("lang") or "")
    if value and not _ID.match(value):
        raise ValueError("bad model id")
    return value


def _task(payload: Dict[str, Any]) -> int:
    try:
        return int(payload["task"])
    except (KeyError, TypeError, ValueError):
        raise ValueError("task is required") from None


def _seconds(payload: Dict[str, Any], key: str, default: float) -> float:
    try:
        return max(1.0, min(float(payload.get(key) or default), 7200.0))
    except (TypeError, ValueError):
        return default


def _models(raw: Any) -> list:
    out = []
    if isinstance(raw, dict):
        for key, entry in sorted(raw.items()):
            parts = entry.get("data") if isinstance(entry, dict) else None
            if isinstance(parts, list) and len(parts) >= 4:  # [id, "name / lang", options, lang]
                out.append({"id": str(key), "name": str(parts[1]), "lang": str(parts[3])})
    return out


def _string_property(name: str) -> str:
    try:
        value = bus.get_property(name)
    except SpeechNoteError:
        return ""
    return value if isinstance(value, str) else ""


def status(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Is Speech Note installed and running, and which speech models does it have."""
    if payload.get("start"):
        bus.ensure_ready()
    now = bus.state()
    kind = bus.install_kind()
    reply: Dict[str, Any] = {"type": "speechnote_status", "installed": bool(kind) or now is not None, "kind": kind,
                             "running": now is not None, "state": now, "ready": now is not None and now >= bus.STATE_IDLE,
                             "models_known": False, "stt_models": [], "tts_models": [], "default_stt_model": "",
                             "default_tts_model": "", "default_stt_lang": "", "default_tts_lang": ""}
    if now is None:
        return reply
    try:
        reply["stt_models"] = _models(bus.get_property("SttModels"))
        reply["tts_models"] = _models(bus.get_property("TtsModels"))
        reply["models_known"] = True
    except SpeechNoteError:
        pass
    for key, prop in (("default_stt_model", "DefaultSttModel"), ("default_tts_model", "DefaultTtsModel"),
                      ("default_stt_lang", "DefaultSttLang"), ("default_tts_lang", "DefaultTtsLang")):
        reply[key] = _string_property(prop)
    return reply


def start(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Start the service if it is not running and wait until it is idle."""
    was_running = bus.state() is not None
    return {"type": "speechnote_started", "state": bus.ensure_ready(), "started": not was_running}


def keepalive_service(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Postpone the service's idle exit. Never starts it: when it is not running nothing happens."""
    if bus.state() is None:
        return {"type": "speechnote_service_kept", "running": False}
    bus.call("KeepAliveService")
    return {"type": "speechnote_service_kept", "running": True}


def listen_start(payload: Dict[str, Any]) -> Dict[str, Any]:
    model = _model(payload)
    bus.ensure_ready()
    task = bus.call("SttStartListen", "iss", 1, model, "")  # mode 1 = manual: one text after the stop
    if not isinstance(task, int) or task < 0:
        raise bus.refused(task)
    return {"type": "speechnote_listening", "task": task}


def keepalive(payload: Dict[str, Any]) -> Dict[str, Any]:
    task = _task(payload)
    remaining = bus.call("KeepAliveTask", "i", task)  # 0 when that task is not the current one
    return {"type": "speechnote_keepalive", "task": task, "alive": bool(remaining)}


def listen_stop(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Stop listening and wait for the one decoded text (the signal comes after SttStopListen)."""
    task = _task(payload)
    limit = _seconds(payload, "timeout", 20.0)
    with bus.Monitor() as monitor:
        monitor.ready()
        if bus.call("SttStopListen", "i", task) != 0:
            raise SpeechNoteError("bus_error", "Speech Note could not stop listening (is the task over?)")
        for message in monitor.messages(limit):
            args = bus.signal_args(message, "SttTextDecoded")
            if args is not None and len(args) >= 3 and args[2] == task:
                return {"type": "speechnote_text", "text": str(args[0]), "lang": str(args[1]), "task": task}
            args = bus.signal_args(message, "ErrorOccured")
            if args:
                code, text = ENGINE_ERRORS.get(args[0], ("engine_error", "Speech Note reported an error"))
                raise SpeechNoteError(code, text)
    raise SpeechNoteError("timeout", "Speech Note did not return the text in time")


def listen_cancel(payload: Dict[str, Any]) -> Dict[str, Any]:
    task = _task(payload)
    bus.call("Cancel", "i", task)
    return {"type": "speechnote_cancelled", "task": task}


def speak(payload: Dict[str, Any]) -> Dict[str, Any]:
    text = payload.get("text")
    if not isinstance(text, str) or not text.strip():
        raise ValueError("text is required")
    if len(text) > MAX_TEXT:
        raise ValueError("text is too long")
    model = _model(payload)
    bus.ensure_ready()
    task = _call_privately("TtsPlaySpeech", "ss", (text, model))
    if not isinstance(task, int) or task < 0:
        raise bus.refused(task)
    return {"type": "speechnote_speaking", "task": task}


def _call_privately(member: str, sig: str, args: Tuple[Any, ...]) -> Any:
    """A call whose arguments must not show up in a process list (busctl puts them
    on its command line): straight over the session bus socket. Returns the first
    reply value. ``KDEAICHAT_SPEECHNOTE_BUS`` overrides the bus address (the docs media
    point it at nothing, so the demo can never read aloud through the real service)."""
    conn = minidbus.Connection(os.environ.get("KDEAICHAT_SPEECHNOTE_BUS") or None)
    try:
        reply = conn.call(bus.NAME, bus.PATH, bus.IFACE, member, sig, args, timeout=15.0)
        return reply.body[0] if reply.body else None
    finally:
        conn.close()


def _playback(method: str, kind: str) -> Callable[[Dict[str, Any]], Dict[str, Any]]:
    def run(payload: Dict[str, Any]) -> Dict[str, Any]:
        task = _task(payload)
        return {"type": kind, "task": task, "result": bus.call(method, "i", task)}
    run.__doc__ = "%s for a read-aloud task." % method
    return run


def wait_spoken(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Wait until the task is no longer Speech Note's current task.

    Polling CurrentTask (rather than watching for TtsPlaySpeechFinished) cannot
    miss the end if the task was over before this process started, and the
    loop doubles as the keepalive Speech Note needs while it plays. With
    ``sentences``, the bus is watched meanwhile and the first sentence Speech
    Note starts reading ends the wait (without a watch, it only polls).
    """
    task = _task(payload)
    deadline = time.monotonic() + _seconds(payload, "timeout", 3600.0)
    monitor = None
    if payload.get("sentences") is True:
        try:
            monitor = bus.Monitor()
            monitor.ready()
        except SpeechNoteError:
            if monitor:
                monitor.__exit__()
            monitor = None
    try:
        return _wait_spoken(task, deadline, monitor)
    finally:
        if monitor:
            monitor.__exit__()


def _wait_spoken(task: int, deadline: float, monitor: Any) -> Dict[str, Any]:
    last_keepalive = 0.0
    failures = 0
    while time.monotonic() < deadline:
        try:
            current = bus.get_property("CurrentTask")
            failures = 0
        except SpeechNoteError:
            failures += 1
            if failures >= 3:  # the service is gone: the speech has stopped too
                return {"type": "speechnote_spoken", "task": task}
            time.sleep(POLL)
            continue
        if current != task:
            return {"type": "speechnote_spoken", "task": task}
        if time.monotonic() - last_keepalive >= KEEPALIVE_EVERY:
            last_keepalive = time.monotonic()
            bus.call("KeepAliveTask", "i", task)
        if monitor is None:
            time.sleep(POLL)
            continue
        for message in monitor.messages(POLL):
            args = bus.signal_args(message, "TtsPartialSpeechPlaying")
            if args and len(args) >= 2 and args[1] == task and isinstance(args[0], str):
                return {"type": "speechnote_sentence", "task": task, "text": args[0]}
    raise SpeechNoteError("timeout", "Speech Note was still reading when the wait ended")


COMMANDS = {
    "speechnote_status": _command(status),
    "speechnote_start": _command(start),
    "speechnote_keepalive_service": _command(keepalive_service),
    "speechnote_listen_start": _command(listen_start),
    "speechnote_keepalive": _command(keepalive),
    "speechnote_listen_stop": _command(listen_stop),
    "speechnote_listen_cancel": _command(listen_cancel),
    "speechnote_speak": _command(speak),
    "speechnote_pause": _command(_playback("TtsPauseSpeech", "speechnote_paused")),
    "speechnote_resume": _command(_playback("TtsResumeSpeech", "speechnote_resumed")),
    "speechnote_stop": _command(_playback("TtsStopSpeech", "speechnote_stopped")),
    "speechnote_wait_spoken": _command(wait_spoken),
}
