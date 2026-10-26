"""``setup_check``: what the current settings need, checked on this computer.

Payload (built by config/SetupChecks.js from the widget's settings; never a
key or any other secret)::

    {"mode": "direct"|"opencode"|"pi", "openCodeUrl": str,
     "endpoints": [{"id", "name", "url"}],     # local/self-hosted chat providers
     "stt": {sttEnabled, sttEngine, ...},       # the stt* settings
     "tts": {voiceTtsEnabled, voiceTtsEngine, ...},
     "timeout": seconds (optional)}

Prints ``{"checks": [{id, area, status: ok|warn|error, code, args}]}``. The
checks only look: nothing is installed, started, downloaded or rewritten.
The key and KWallet checks are done in the widget (it knows the wallet's
state without reading any key here).
"""
import json
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Dict, List

from kdeaichat import diag_agents, diag_system

MAX_ENDPOINTS = 20


def run_checks(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    try:
        timeout = min(10.0, max(0.2, float(payload.get("timeout") or diag_agents.TIMEOUT)))
    except (TypeError, ValueError):
        timeout = diag_agents.TIMEOUT
    mode = str(payload.get("mode") or "direct")
    jobs = []
    if mode == "opencode":
        jobs.append(lambda: diag_agents.check_opencode(str(payload.get("openCodeUrl") or ""), timeout))
    elif mode == "pi":
        jobs.append(diag_agents.check_pi)
    else:
        endpoints = [e for e in (payload.get("endpoints") or []) if isinstance(e, dict)][:MAX_ENDPOINTS]
        for endpoint in endpoints:
            jobs.append(lambda e=endpoint: [diag_agents.check_endpoint(e, timeout)])
    jobs.append(diag_system.check_attachments)
    stt = payload.get("stt") if isinstance(payload.get("stt"), dict) else {}
    if stt.get("sttEnabled") is True:
        jobs.append(lambda: diag_system.check_dictation(stt))
    tts = payload.get("tts") if isinstance(payload.get("tts"), dict) else {}
    if tts.get("voiceTtsEnabled") is True:
        jobs.append(lambda: diag_system.check_read_aloud(tts))
    jobs.append(diag_system.check_schedules)
    # Network probes wait; run them side by side so a few slow servers don't add up.
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(_safe, jobs))
    return [r for rows in results for r in rows]


def _safe(job) -> List[Dict[str, Any]]:
    try:
        return job()
    except Exception as e:  # one broken check must not hide the others
        return [diag_agents.row("internal", "other", "warn", "check-failed", str(e)[:200])]


def cmd_setup_check(payload: Dict[str, Any]) -> None:
    print(json.dumps({"checks": run_checks(payload)}, ensure_ascii=False))


COMMANDS = {"setup_check": cmd_setup_check}
