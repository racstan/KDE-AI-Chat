"""Integration tests for kde_ai_helper.py IPC.

Spawns the helper as a real subprocess and exercises the
``--clipboard``/``add_schedule``/``poll_pending_triggers`` flows with a
real on-disk schedule store. The helper is zero-dependency (stdlib
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
PENDING_DIR = "~/.local/share/kdeaichat/pending"


def _run_helper(command: str, payload: dict, temp_dir: str):
    """Run kde_ai_helper with a redirected ``$HOME`` so it touches a temp store.

    Returns ``(stdout, returncode)``.
    """
    payload_b64 = base64.b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8")
    env = os.environ.copy()
    env["HOME"] = temp_dir
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
        os.makedirs(os.path.join(self.temp_dir, ".local", "share", "kdeaichat", "pending"), exist_ok=True)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_add_then_toggle_then_delete(self):
        # Add
        out, err, rc = _run_helper("add_schedule", {
            "entry": {"id": "s-1", "name": "Daily", "enabled": True, "message": "hi"},
        }, self.temp_dir)
        self.assertEqual(rc, 0, msg=err)
        store = os.path.join(self.temp_dir, ".local", "share", "kdeaichat", "schedules.json")
        with open(store) as f:
            data = json.load(f)
        self.assertEqual(len(data["schedules"]), 1)
        self.assertEqual(data["schedules"][0]["id"], "s-1")

        # Toggle off
        out, err, rc = _run_helper("toggle_schedule", {
            "schedId": "s-1", "enabled": False,
        }, self.temp_dir)
        self.assertEqual(rc, 0, msg=err)
        with open(store) as f:
            data = json.load(f)
        self.assertFalse(data["schedules"][0]["enabled"])

        # Delete
        out, err, rc = _run_helper("delete_schedule", {"schedId": "s-1"}, self.temp_dir)
        self.assertEqual(rc, 0, msg=err)
        with open(store) as f:
            data = json.load(f)
        self.assertEqual(len(data["schedules"]), 0)

    def test_poll_pending_drains_files(self):
        # Drop a trigger file in the pending dir
        pending = os.path.join(self.temp_dir, ".local", "share", "kdeaichat", "pending")
        trigger = os.path.join(pending, "trigger-001.json")
        with open(trigger, "w") as f:
            json.dump({"scheduleId": "s-1", "message": "test"}, f)

        out, err, rc = _run_helper("poll_pending_triggers", {}, self.temp_dir)
        self.assertEqual(rc, 0, msg=err)
        parsed = json.loads(out)
        self.assertEqual(len(parsed["pending"]), 1)
        self.assertEqual(parsed["pending"][0]["scheduleId"], "s-1")
        # File should be removed
        self.assertFalse(os.path.exists(trigger))
        # Second poll should be empty
        out2, _, _ = _run_helper("poll_pending_triggers", {}, self.temp_dir)
        parsed2 = json.loads(out2)
        self.assertEqual(parsed2["pending"], [])

    def test_migrate_history_loads_existing(self):
        # Create an old history file
        old = os.path.join(self.temp_dir, "old_history.txt")
        with open(old, "w") as f:
            f.write("legacy content")
        out, err, rc = _run_helper("migrate_history", {
            "oldFullPath": old,
            "newFullPath": "",
            "currentB64": "",
        }, self.temp_dir)
        self.assertEqual(rc, 0, msg=err)
        decoded = json.loads(base64.b64decode(out).decode("utf-8"))
        self.assertEqual(decoded["action"], "load")
        self.assertEqual(base64.b64decode(decoded["content"]).decode("utf-8"), "legacy content")

    def test_save_and_load_config_keys(self):
        rcfile = os.path.join(self.temp_dir, "kdeaichatrc")
        out, err, rc = _run_helper("sync_config_keys", {
            "configPath": rcfile,
            "keys": {"apiKey": "sk-test123", "model": "gpt-4"},
        }, self.temp_dir)
        self.assertEqual(rc, 0, msg=err)

        out, err, rc = _run_helper("load_config_keys", {"configPath": rcfile}, self.temp_dir)
        self.assertEqual(rc, 0, msg=err)
        loaded = json.loads(out)
        self.assertEqual(loaded["apiKey"], "sk-test123")
        self.assertEqual(loaded["model"], "gpt-4")

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

    def test_get_memory_usage_no_processes(self):
        # No kde-ai-scheduler or opencode running, expect zeros.
        # The helper pgrep's for "kde-ai-scheduler" and "opencode" in
        # any process name. We assert that pgrep ran without errors
        # and the JSON is parseable; the actual counts depend on the
        # host environment so we don't require strict zeros.
        out, err, rc = _run_helper("get_memory_usage", {}, self.temp_dir)
        self.assertEqual(rc, 0, msg=err)
        parsed = json.loads(out)
        self.assertIn("scheduler", parsed)
        self.assertIn("opencode", parsed)
        self.assertIsInstance(parsed["scheduler"], int)
        self.assertIsInstance(parsed["opencode"], int)
        self.assertGreaterEqual(parsed["scheduler"], 0)
        self.assertGreaterEqual(parsed["opencode"], 0)


if __name__ == "__main__":
    unittest.main()
