"""Installs the faster-whisper engine when the user presses Install in Settings → Voice.

``stt_install {gpu: "auto"|"cpu"|"gpu"}`` runs ``voice/venv_setup.sh`` for the
voice venv (``stt_settings.venv_dir``) without a terminal and prints one line:
``{"type": "stt_installed", "ok": true, "mode": "cpu"|"gpu"}`` or
``{"type": "stt_installed", "ok": false, "error": ..., "log": last lines}``.

The settings page shows ``stt_setup_size`` (what will be downloaded) before
the button can be pressed; models are downloaded separately
(``stt_download_model``). ``KDEAICHAT_STT_SETUP`` replaces the script in tests.
"""
import json
import os
import subprocess
from typing import Any, Dict, List

from kdeaichat.stt_settings import venv_dir

TIMEOUT = 3600
_UI_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def setup_script() -> str:
    return os.environ.get("KDEAICHAT_STT_SETUP") or os.path.join(_UI_DIR, "voice", "venv_setup.sh")


def _json_lines(text: str) -> List[Dict[str, Any]]:
    out = []
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                data = json.loads(line)
            except ValueError:
                continue
            if isinstance(data, dict):
                out.append(data)
    return out


def install(mode: str = "auto", timeout: float = TIMEOUT) -> Dict[str, Any]:
    if mode not in ("auto", "cpu", "gpu"):
        mode = "auto"
    folder = venv_dir({})
    os.makedirs(os.path.dirname(folder), mode=0o700, exist_ok=True)
    env = dict(os.environ, NON_INTERACTIVE="1")
    try:
        result = subprocess.run(["bash", setup_script(), folder, mode], stdin=subprocess.DEVNULL,
                                capture_output=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return {"type": "stt_installed", "ok": False, "error": "The install took longer than an hour and was stopped."}
    except OSError as e:
        return {"type": "stt_installed", "ok": False, "error": "Can't run the setup script: %s" % (e.strerror or e)}
    stdout = result.stdout.decode("utf-8", "replace")
    events = _json_lines(stdout)
    errors = [e for e in events if e.get("type") == "setup_error"]
    done = any(e.get("type") == "setup_status" and e.get("status") == "done" for e in events)
    tail = (stdout + result.stderr.decode("utf-8", "replace")).strip().splitlines()[-6:]
    if result.returncode == 0 and done and not errors:
        gpu = any(e.get("status") == "installing_gpu" for e in events) or "(gpu)" in stdout
        return {"type": "stt_installed", "ok": True, "venv": folder, "mode": "gpu" if gpu else "cpu"}
    message = errors[-1].get("error") if errors else "The setup script failed (exit %d)." % result.returncode
    return {"type": "stt_installed", "ok": False, "error": message, "log": "\n".join(tail)[-1500:]}


def cmd_stt_install(payload: Dict[str, Any]) -> None:
    print(json.dumps(install(str(payload.get("gpu") or "auto"))), flush=True)


COMMANDS = {
    "stt_install": cmd_stt_install,
}
