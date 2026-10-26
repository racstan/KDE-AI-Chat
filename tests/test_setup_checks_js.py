"""Runs tests/js/setup_checks.test.js (config/SetupChecks.js) in node, and checks that every
code the helper's setup checks can report has words in SetupChecks.js."""
import json
import os
import re
import subprocess

from tests.conftest import UI_DIR

SCRIPT = os.path.join(os.path.dirname(__file__), "js", "setup_checks.test.js")
# Row ids (not codes) that look like codes.
ROW_IDS = {"opencode-server", "opencode-program", "pi-program", "pi-bridge", "stt-recorder", "stt-engine", "stt-model",
           "tts-engine", "attach-pdf", "attach-docx"}


def test_setup_checks_js():
    result = subprocess.run(["node", SCRIPT], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr


def test_every_helper_code_has_words():
    result = subprocess.run(["node", SCRIPT, "--codes"], capture_output=True, text=True, timeout=60)
    known = set(json.loads(result.stdout))
    emitted = set()
    for name in ("diag_agents.py", "diag_system.py", "diagnostics.py"):
        with open(os.path.join(UI_DIR, "kdeaichat", name), encoding="utf-8") as f:
            source = f.read()
        emitted |= set(re.findall(r'"((?:local|opencode|pi|pdf|docx|stt|tts|sched|url|check)-[a-z0-9-]+)"', source))
    emitted -= ROW_IDS
    assert len(emitted) > 40
    assert emitted <= known, sorted(emitted - known)
