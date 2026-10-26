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
                "tts_model_path": "espeak-ng"
            }
            self.helper.check_env(payload)
            
            self.assertTrue(len(self.emitted_data) > 0)
            res = self.emitted_data[0]
            self.assertEqual(res["tts_model_path_ok"], True)

if __name__ == "__main__":
    unittest.main()
