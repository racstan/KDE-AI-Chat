#!/usr/bin/env python3
"""voice_helper.py - STT/TTS helper for KDE AI Chat.

Runs as a long-lived process, reading JSON commands from stdin
and writing JSON responses to stdout.

Requires a Python venv with: faster-whisper, kokoro, sounddevice, numpy, soundfile
"""

import sys
import os
import json
import shutil
import subprocess
import tempfile
import threading
import time
import base64


class VoiceHelper:
    def __init__(self):
        self.stt_model = None
        self.stt_model_name = None
        self.tts_pipeline = None
        self.recording = False
        self.stop_recording = False
        self.tts_playing = False
        self.stop_tts = False
        self.stt_thread = None
        self.tts_thread = None

    def emit(self, data):
        """Write a JSON response to stdout."""
        print(json.dumps(data), flush=True)

    def check_env(self, payload):
        """Check environment for voice capabilities."""
        stt_model_path = payload.get("stt_model_path", "")
        tts_model_path = payload.get("tts_model_path", "")

        result = {
            "type": "env_check",
            "mic_available": False,
            "paplay_available": False,
            "aplay_available": False,
            "espeak_available": False,
            "venv_ready": False,
            "stt_ready": False,
            "tts_ready": False,
            "sounddevice_ok": False,
            "faster_whisper_ok": False,
            "kokoro_ok": False,
            "numpy_ok": False,
            "stt_model_path_ok": False,
            "tts_model_path_ok": False,
        }

        # Check microphone (via sounddevice)
        try:
            import sounddevice as sd
            devices = sd.query_devices()
            input_devices = [d for d in devices if d.get("max_input_channels", 0) > 0]
            result["mic_available"] = len(input_devices) > 0
            result["sounddevice_ok"] = True
        except Exception:
            pass

        # Check audio players
        result["paplay_available"] = shutil.which("paplay") is not None
        result["aplay_available"] = shutil.which("aplay") is not None
        result["espeak_available"] = shutil.which("espeak-ng") is not None

        # Check venv packages
        try:
            import numpy
            result["numpy_ok"] = True
        except ImportError:
            pass

        try:
            from faster_whisper import WhisperModel
            result["faster_whisper_ok"] = True
        except ImportError:
            pass

        try:
            from kokoro import KPipeline
            result["kokoro_ok"] = True
        except ImportError:
            pass

        # Check custom model paths
        if stt_model_path and os.path.isdir(stt_model_path):
            result["stt_model_path_ok"] = True
        if tts_model_path and os.path.isdir(tts_model_path):
            result["tts_model_path_ok"] = True

        # Overall readiness
        result["venv_ready"] = result["sounddevice_ok"] and result["numpy_ok"]
        result["stt_ready"] = result["venv_ready"] and result["faster_whisper_ok"] and (result["stt_model_path_ok"] or not stt_model_path)
        result["tts_ready"] = result["kokoro_ok"] and result["espeak_available"] and (
            result["paplay_available"] or result["aplay_available"]
        ) and (result["tts_model_path_ok"] or not tts_model_path)

        self.emit(result)

    def list_models(self, payload):
        """List available and downloaded models."""
        cache_dir = os.path.expanduser("~/.cache/kdeaichat/models")
        result = {
            "type": "models_list",
            "stt_models": [],
            "tts_models": [],
        }

        # Check STT models
        stt_default = "large-v3-turbo"
        hf_cache = os.path.expanduser("~/.cache/huggingface/hub")
        stt_downloaded = False
        if os.path.isdir(hf_cache):
            for entry in os.listdir(hf_cache):
                if "faster-whisper" in entry and stt_default in entry:
                    stt_downloaded = True
                    break

        result["stt_models"].append({
            "name": stt_default,
            "downloaded": stt_downloaded,
            "size": "~1.5 GB",
        })

        # Check TTS models
        tts_default = "kokoro-82m"
        tts_downloaded = False
        try:
            from kokoro import KPipeline
            tts_downloaded = True
        except Exception:
            pass

        result["tts_models"].append({
            "name": tts_default,
            "downloaded": tts_downloaded,
            "size": "~150 MB",
        })

        self.emit(result)

    def download_stt(self, payload):
        """Download the STT model."""
        model_name = payload.get("model", "large-v3-turbo")
        progress_file = os.path.join(tempfile.gettempdir(), "kdeaichat_stt_download.json")

        def do_download():
            try:
                self.emit({"type": "download_progress", "target": "stt", "model": model_name, "pct": 0})
                from faster_whisper import WhisperModel
                self.emit({"type": "download_progress", "target": "stt", "model": model_name, "pct": 10})
                # This triggers the download
                model = WhisperModel(model_name, device="cpu", compute_type="int8")
                self.emit({"type": "download_progress", "target": "stt", "model": model_name, "pct": 100})
                self.emit({"type": "download_done", "target": "stt", "model": model_name})
                del model
            except Exception as e:
                self.emit({"type": "download_error", "target": "stt", "error": str(e)})

        thread = threading.Thread(target=do_download, daemon=True)
        thread.start()
        # Return immediately
        self.emit({"type": "download_started", "target": "stt", "model": model_name})

    def download_tts(self, payload):
        """Download the TTS model."""
        voice = payload.get("voice", "af_heart")
        progress_file = os.path.join(tempfile.gettempdir(), "kdeaichat_tts_download.json")

        def do_download():
            try:
                self.emit({"type": "download_progress", "target": "tts", "model": "kokoro-82m", "pct": 0})
                from kokoro import KPipeline
                self.emit({"type": "download_progress", "target": "tts", "model": "kokoro-82m", "pct": 50})
                # Initialize pipeline triggers download
                pipeline = KPipeline(lang_code="a")
                self.emit({"type": "download_progress", "target": "tts", "model": "kokoro-82m", "pct": 100})
                self.emit({"type": "download_done", "target": "tts", "model": "kokoro-82m"})
                del pipeline
            except Exception as e:
                self.emit({"type": "download_error", "target": "tts", "error": str(e)})

        thread = threading.Thread(target=do_download, daemon=True)
        thread.start()
        self.emit({"type": "download_started", "target": "tts", "model": "kokoro-82m"})

    def start_stt(self, payload):
        """Start speech-to-text recording."""
        if self.recording:
            self.emit({"type": "stt_error", "error": "Already recording"})
            return

        duration = payload.get("duration", 10)
        language = payload.get("language", "en")
        model_name = payload.get("model", "large-v3-turbo")
        custom_path = payload.get("model_path", "")

        self.recording = True
        self.stop_recording = False

        def do_stt():
            try:
                # Check microphone
                try:
                    import sounddevice as sd
                    import numpy as np
                except ImportError as e:
                    self.emit({"type": "stt_error", "error": "sounddevice/numpy not available: " + str(e)})
                    self.recording = False
                    return

                # Check mic availability
                try:
                    devices = sd.query_devices()
                    input_devices = [d for d in devices if d.get("max_input_channels", 0) > 0]
                    if not input_devices:
                        self.emit({"type": "stt_error", "error": "No microphone detected"})
                        self.recording = False
                        return
                except Exception as e:
                    self.emit({"type": "stt_error", "error": "Cannot query audio devices: " + str(e)})
                    self.recording = False
                    return

                # Load model
                if self.stt_model is None or self.stt_model_name != model_name:
                    self.emit({"type": "stt_status", "status": "loading_model"})
                    try:
                        from faster_whisper import WhisperModel
                        if custom_path and os.path.isdir(custom_path):
                            self.stt_model = WhisperModel(custom_path, device="cpu", compute_type="int8")
                        else:
                            self.stt_model = WhisperModel(model_name, device="cpu", compute_type="int8")
                        self.stt_model_name = model_name
                    except Exception as e:
                        self.emit({"type": "stt_error", "error": "Failed to load STT model: " + str(e)})
                        self.recording = False
                        return

                self.emit({"type": "stt_status", "status": "recording"})

                # Record audio in chunks, checking stop_recording
                sample_rate = 16000
                chunk_duration = 1.0  # seconds per chunk
                all_audio = []
                total_recorded = 0.0

                while total_recorded < duration and not self.stop_recording:
                    chunk = sd.rec(
                        int(chunk_duration * sample_rate),
                        samplerate=sample_rate,
                        channels=1,
                        dtype="float32",
                    )
                    sd.wait()
                    if not self.stop_recording:
                        all_audio.append(chunk.flatten())
                        total_recorded += chunk_duration
                    else:
                        break

                if not all_audio:
                    self.emit({"type": "stt_result", "text": "", "duration": 0})
                    self.recording = False
                    return

                self.emit({"type": "stt_status", "status": "transcribing"})

                # Concatenate and transcribe
                import numpy as np
                audio = np.concatenate(all_audio)

                # Save audio to temp file for playback
                import soundfile as sf
                audio_path = os.path.join(tempfile.gettempdir(), "kdeaichat_stt_test.wav")
                sf.write(audio_path, audio, sample_rate)

                # Skip very short audio
                if len(audio) < sample_rate * 0.5:
                    self.emit({"type": "stt_result", "text": "", "duration": total_recorded, "audio_path": audio_path})
                    self.recording = False
                    return

                segments, info = self.stt_model.transcribe(
                    audio,
                    beam_size=5,
                    language=language if language != "auto" else None,
                    vad_filter=True,
                )
                text = " ".join(seg.text for seg in segments).strip()

                self.emit({
                    "type": "stt_result",
                    "text": text,
                    "duration": total_recorded,
                    "language": info.language if hasattr(info, "language") else language,
                    "audio_path": audio_path,
                })

            except Exception as e:
                self.emit({"type": "stt_error", "error": str(e)})
            finally:
                self.recording = False

        self.stt_thread = threading.Thread(target=do_stt, daemon=True)
        self.stt_thread.start()

    def stop_stt(self, payload):
        """Stop the current recording."""
        if self.recording:
            self.stop_recording = True
            self.emit({"type": "stt_status", "status": "stopping"})
        else:
            self.emit({"type": "stt_stopped"})

    def play_audio(self, payload):
        """Play an audio file."""
        audio_path = payload.get("path", "")
        if not audio_path or not os.path.exists(audio_path):
            self.emit({"type": "play_error", "error": "Audio file not found"})
            return

        def do_play():
            try:
                # Try paplay first (PulseAudio)
                if shutil.which("paplay"):
                    subprocess.run(["paplay", audio_path], check=True, capture_output=True)
                # Fallback to aplay (ALSA)
                elif shutil.which("aplay"):
                    subprocess.run(["aplay", audio_path], check=True, capture_output=True)
                else:
                    self.emit({"type": "play_error", "error": "No audio player found (paplay or aplay)"})
                    return
                self.emit({"type": "play_done"})
            except Exception as e:
                self.emit({"type": "play_error", "error": str(e)})

        threading.Thread(target=do_play, daemon=True).start()

    def tts(self, payload):
        """Text-to-speech synthesis and playback."""
        text = payload.get("text", "")
        voice = payload.get("voice", "af_heart")
        lang_code = payload.get("lang_code", "a")
        custom_path = payload.get("model_path", "")

        if not text:
            self.emit({"type": "tts_error", "error": "No text provided"})
            return

        if self.tts_playing:
            self.stop_tts = True
            time.sleep(0.2)

        self.tts_playing = True
        self.stop_tts = False

        def do_tts():
            try:
                # Check espeak-ng
                if not shutil.which("espeak-ng"):
                    self.emit({"type": "tts_error", "error": "espeak-ng not installed. Install with: sudo apt install espeak-ng"})
                    return

                # Check audio player
                player = None
                if shutil.which("paplay"):
                    player = "paplay"
                elif shutil.which("aplay"):
                    player = "aplay"
                elif shutil.which("ffplay"):
                    player = "ffplay"
                else:
                    self.emit({"type": "tts_error", "error": "No audio player found. Install pulseaudio-utils or alsa-utils."})
                    return

                self.emit({"type": "tts_status", "status": "synthesizing"})

                # Load pipeline
                from kokoro import KPipeline
                import soundfile as sf
                import numpy as np

                if self.tts_pipeline is None:
                    if custom_path:
                        self.tts_pipeline = KPipeline(lang_code=lang_code, repo_id=custom_path)
                    else:
                        self.tts_pipeline = KPipeline(lang_code=lang_code)

                self.emit({"type": "tts_status", "status": "playing"})

                # Synthesize and play in segments
                for _, _, audio in self.tts_pipeline(text, voice=voice):
                    if self.stop_tts:
                        break

                    # Normalize audio
                    audio = np.asarray(audio, dtype=np.float32)
                    if audio.max() > 0:
                        audio = audio / max(abs(audio.max()), abs(audio.min())) * 0.9

                    # Write to temp file and play
                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                        tmp_path = f.name
                        sf.write(tmp_path, audio, 24000)

                    if player == "paplay":
                        proc = subprocess.Popen(
                            ["paplay", "--rate=24000", "--channels=1", "--format=s16le", tmp_path],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                    elif player == "aplay":
                        proc = subprocess.Popen(
                            ["aplay", "-r", "24000", "-c", "1", "-f", "S16_LE", tmp_path],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                    else:
                        proc = subprocess.Popen(
                            ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )

                    # Wait for playback to finish, checking stop_tts
                    while proc.poll() is None:
                        if self.stop_tts:
                            proc.terminate()
                            break
                        time.sleep(0.1)

                    # Cleanup temp file
                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass

                self.emit({"type": "tts_done"})

            except Exception as e:
                self.emit({"type": "tts_error", "error": str(e)})
            finally:
                self.tts_playing = False

        self.tts_thread = threading.Thread(target=do_tts, daemon=True)
        self.tts_thread.start()

    def stop_tts_cmd(self, payload):
        """Stop TTS playback."""
        if self.tts_playing:
            self.stop_tts = True
            self.emit({"type": "tts_status", "status": "stopping"})
        else:
            self.emit({"type": "tts_stopped"})

    def process_command(self, line):
        """Process a single JSON command from stdin."""
        try:
            cmd_data = json.loads(line)
        except json.JSONDecodeError as e:
            self.emit({"type": "error", "error": "Invalid JSON: " + str(e)})
            return

        cmd = cmd_data.get("cmd", "")
        handlers = {
            "check_env": self.check_env,
            "list_models": self.list_models,
            "download_stt": self.download_stt,
            "download_tts": self.download_tts,
            "start_stt": self.start_stt,
            "stop_stt": self.stop_stt,
            "play_audio": self.play_audio,
            "tts": self.tts,
            "stop_tts": self.stop_tts_cmd,
        }

        handler = handlers.get(cmd)
        if handler:
            handler(cmd_data)
        else:
            self.emit({"type": "error", "error": "Unknown command: " + cmd})

    def run(self):
        """Main loop: read commands from stdin."""
        self.emit({"type": "ready"})
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            self.process_command(line)
        # Wait for any running threads before exiting
        if self.stt_thread and self.stt_thread.is_alive():
            self.stt_thread.join(timeout=120)
        if self.tts_thread and self.tts_thread.is_alive():
            self.tts_thread.join(timeout=120)


if __name__ == "__main__":
    helper = VoiceHelper()
    helper.run()
