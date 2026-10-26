"""Removes the pre-1.4.0 read-aloud service once, after an upgrade.

Before 1.4.0, read aloud ran in an always-on ``kde-ai-tts.service`` (the
voice venv's ``voice_helper.py --tts-server`` on port 9016). Read aloud now
runs in the widget (QtTextToSpeech) or per request through the helper, so
``voice_startup`` stops and disables that unit, deletes its file and stops a
server started by hand. The speech-to-text unit is left alone.

Idempotent and cheap: with no unit file and no such process it does nothing.
The unit folder and systemctl can be redirected (``KDEAICHAT_UNIT_DIR``,
``KDEAICHAT_SYSTEMCTL``) like the schedule units.
"""
import json
import os
import signal
import tempfile
from typing import Any, Dict, List

from kdeaichat import schedule_units

LEGACY_TTS_UNIT = "kde-ai-tts.service"


def _tts_server_pids() -> List[int]:
    """Our processes running ``voice_helper.py --tts-server``, from /proc."""
    pids = []
    uid = os.getuid()
    for name in os.listdir("/proc") if os.path.isdir("/proc") else []:
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            if os.stat(f"/proc/{name}").st_uid != uid:
                continue
            with open(f"/proc/{name}/cmdline", "rb") as f:
                argv = [a.decode("utf-8", "replace") for a in f.read().split(b"\0")]
        except OSError:
            continue
        if "--tts-server" in argv and any(a.endswith("voice_helper.py") for a in argv):
            pids.append(int(name))
    return pids


def cleanup_legacy_tts(run=None, allow_kill: bool = False) -> Dict[str, Any]:
    run = run or schedule_units.systemctl
    done: Dict[str, Any] = {"unit": False, "killed": 0, "marker": False}
    unit = os.path.join(schedule_units.unit_dir(), LEGACY_TTS_UNIT)
    if os.path.lexists(unit):
        run(["disable", "--now", LEGACY_TTS_UNIT])
        os.remove(unit)
        run(["daemon-reload"])
        run(["reset-failed", LEGACY_TTS_UNIT])
        done["unit"] = True
    # A sandbox (dev run, tests) with its own unit folder leaves the user's processes alone.
    sandboxed = bool(os.environ.get("KDEAICHAT_UNIT_DIR")) and not allow_kill
    for pid in [] if sandboxed else _tts_server_pids():
        try:
            os.kill(pid, signal.SIGTERM)
            done["killed"] += 1
        except OSError:
            pass
    marker = os.path.join(tempfile.gettempdir(), "kdeaichat_stop_tts")
    if os.path.isfile(marker) and not os.path.islink(marker):
        try:
            os.remove(marker)
            done["marker"] = True
        except OSError:
            pass
    done["changed"] = bool(done["unit"] or done["killed"] or done["marker"])
    return done


def cmd_voice_startup(payload: Dict[str, Any]) -> None:
    print(json.dumps({"ok": True, "legacyTts": cleanup_legacy_tts()}))


COMMANDS = {
    "voice_startup": cmd_voice_startup,
}
