import os
import sys
import json
import unittest
from unittest.mock import patch, MagicMock

# Insert contents/ui/voice to sys.path so we can import voice_helper
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui", "voice"))

from voice_helper import VoiceHelper

class TestVoiceHelper(unittest.TestCase):
    def setUp(self):
        self.helper = VoiceHelper()
        self.emitted_data = []
        self.helper.emit = self.emitted_data.append

    def test_check_env_kokoro_default(self):
        with patch('shutil.which', return_value="/usr/bin/espeak"), \
             patch('os.path.isdir', return_value=True), \
             patch('os.path.exists', return_value=True), \
             patch('os.path.isfile', return_value=True), \
             patch('os.listdir', return_value=["snapshot_file"]):
            
            payload = {
                "stt_model_path": "/path/to/stt",
                "tts_model_path": "/path/to/tts"
            }
            self.helper.check_env(payload)
            
            self.assertTrue(len(self.emitted_data) > 0)
            res = self.emitted_data[0]
            self.assertEqual(res["tts_model_path_ok"], True)
            self.assertEqual(res["stt_model_path_ok"], True)

    def test_check_env_piper(self):
        with patch('shutil.which', return_value="/usr/bin/piper"), \
             patch('os.path.isfile', return_value=True), \
             patch('os.path.exists', return_value=True):
            
            payload = {
                "tts_model_path": "/path/to/tts.onnx"
            }
            self.helper.check_env(payload)
            
            self.assertTrue(len(self.emitted_data) > 0)
            res = self.emitted_data[0]
            self.assertEqual(res["tts_model_path_ok"], True)

    def test_check_env_espeak_ng(self):
        with patch('shutil.which', return_value="/usr/bin/espeak-ng"):
            payload = {
                "tts_model_path": ""
            }
            self.helper.check_env(payload)
            
            self.assertTrue(len(self.emitted_data) > 0)
            res = self.emitted_data[0]
            self.assertEqual(res["tts_model_path_ok"], False)

    @patch('subprocess.Popen')
    @patch('shutil.which')
    def test_do_tts_espeak_ng(self, mock_which, mock_popen):
        # Setup mock for which
        mock_which.side_effect = lambda x: "/usr/bin/" + x if x in ("espeak-ng", "paplay") else None
        
        # Setup mock for Popen process
        mock_proc = MagicMock()
        mock_proc.poll.side_effect = [None, 0] # running first check, done second check
        mock_popen.return_value = mock_proc

        payload = {
            "text": "Hello world",
            "model": "espeak-ng",
            "voice": "en-us"
        }

        # Run inside the helper's tts method
        with patch('subprocess.run') as mock_run:
            self.helper.tts(payload)
            # Wait for thread to finish
            if self.helper.tts_thread:
                self.helper.tts_thread.join(timeout=5.0)

        # We expect it to emit status playing, then tts_done
        statuses = [d["type"] for d in self.emitted_data]
        self.assertIn("tts_status", statuses)
        self.assertIn("tts_done", statuses)

if __name__ == "__main__":
    unittest.main()
