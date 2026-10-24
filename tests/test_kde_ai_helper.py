import os
import io
import json
import base64
import tempfile
import unittest
import contextlib
from unittest.mock import patch
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kde_ai_helper import (
    cmd_toggle_schedule,
    cmd_delete_schedule,
    cmd_add_schedule,
    cmd_export_chat
)

class TestKdeAiHelper(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        # The helper keeps its data in $XDG_DATA_HOME/kdeaichat.
        data_dir = os.path.join(self.temp_dir.name, 'kdeaichat')
        self.schedules_json_path = os.path.join(data_dir, 'schedules.json')
        self.config_rc_path = os.path.join(self.temp_dir.name, 'kdeaichatrc')
        self.pending_dir = os.path.join(data_dir, 'pending')
        os.makedirs(self.pending_dir, exist_ok=True)

        self.patchers = [
            patch('os.path.expanduser', self.mock_expanduser),
            patch.dict(os.environ, {'XDG_DATA_HOME': self.temp_dir.name}),
        ]
        for p in self.patchers:
            p.start()

    def tearDown(self):
        for p in self.patchers:
            p.stop()
        self.temp_dir.cleanup()

    def mock_expanduser(self, path):
        if 'schedules.json' in path:
            return self.schedules_json_path
        if 'kdeaichatrc' in path:
            return self.config_rc_path
        if 'pending' in path:
            return self.pending_dir
        if 'kde-ai-scheduler.py' in path:
            return os.path.join(self.temp_dir.name, 'kde-ai-scheduler.py')
        if 'kde-ai-scheduler.service' in path:
            return os.path.join(self.temp_dir.name, 'kde-ai-scheduler.service')
        return path

    def test_add_and_delete_schedule(self):
        # Add a schedule
        entry = {
            "id": "s-123",
            "name": "Daily test",
            "enabled": True,
            "message": "Hello world"
        }
        cmd_add_schedule({"entry": entry})
        
        # Check added
        with open(self.schedules_json_path) as f:
            data = json.load(f)
        self.assertEqual(len(data['schedules']), 1)
        self.assertEqual(data['schedules'][0]['id'], "s-123")

        # Toggle schedule
        cmd_toggle_schedule({"schedId": "s-123", "enabled": False})
        with open(self.schedules_json_path) as f:
            data = json.load(f)
        self.assertFalse(data['schedules'][0]['enabled'])

        # Delete schedule
        cmd_delete_schedule({"schedId": "s-123"})
        with open(self.schedules_json_path) as f:
            data = json.load(f)
        self.assertEqual(len(data['schedules']), 0)

    def test_export_chat(self):
        dest_path = os.path.join(self.temp_dir.name, 'exported_chat.md')
        content = "Hello, this is a test export."
        b64_content = base64.b64encode(content.encode('utf-8')).decode('utf-8')
        
        cmd_export_chat({
            "filePath": dest_path,
            "b64Content": b64_content
        })
        
        self.assertTrue(os.path.exists(dest_path))
        with open(dest_path) as f:
            self.assertEqual(f.read(), content)
