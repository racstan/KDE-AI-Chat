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

from kdeaichat.maintenance import (
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
