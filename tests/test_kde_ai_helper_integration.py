"""Integration tests for kde_ai_helper.py IPC.

Spawns the helper as a real subprocess and exercises the
``export_chat`` flow and the command dispatch. The helper is zero-dependency (stdlib
only) so we can run it directly.
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import unittest

HELPER_PATH = os.path.join(
    os.path.dirname(__file__),
    "..", "org.kde.plasma.kdeaichat", "contents", "ui",
    "kde_ai_helper.py",
)
SCHEDULES_PATH = "~/.local/share/kdeaichat/schedules.json"


def _run_helper(command: str, payload: dict, temp_dir: str):
    """Run kde_ai_helper with a redirected ``$HOME`` so it touches a temp store.

    Returns ``(stdout, returncode)``.
    """
    payload_b64 = base64.b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8")
    env = os.environ.copy()
    env["HOME"] = temp_dir
    env["XDG_DATA_HOME"] = os.path.join(temp_dir, ".local", "share")
    r = subprocess.run(
        [sys.executable, HELPER_PATH, command, payload_b64],
        capture_output=True, text=True, env=env, timeout=15,
    )
    return r.stdout.strip(), r.stderr.strip(), r.returncode


class TestKdeAiHelperIPC(unittest.TestCase):
    """End-to-end IPC tests for the helper's command dispatch."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        # Pre-create the data dir
        os.makedirs(os.path.join(self.temp_dir, ".local", "share", "kdeaichat"), exist_ok=True)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_export_chat(self):
        dest = os.path.join(self.temp_dir, "exported.md")
        b64 = base64.b64encode(b"# Hello").decode("utf-8")
        out, err, rc = _run_helper("export_chat", {
            "filePath": dest, "b64Content": b64,
        }, self.temp_dir)
        self.assertEqual(rc, 0, msg=err)
        self.assertTrue(os.path.exists(dest))
        with open(dest) as f:
            self.assertEqual(f.read(), "# Hello")

    def test_unknown_command_fails(self):
        out, err, rc = _run_helper("nonexistent_command", {}, self.temp_dir)
        self.assertNotEqual(rc, 0)
        # Helper prints "Unknown command" to stdout (not stderr) in main()
        combined = (out + err).lower()
        self.assertIn("unknown command", combined)

if __name__ == "__main__":
    unittest.main()
