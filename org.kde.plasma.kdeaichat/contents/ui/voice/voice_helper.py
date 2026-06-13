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
        self.last_emitted = None
        self.stt_result = None
        self.tts_result = None
        self.current_status = "idle"
        self.current_countdown = 0
        self.temp_audio_path = os.path.join(tempfile.gettempdir(), "kdeaichat_stt_test.wav")

    def emit(self, data):
        """Write a JSON response to stdout and track results for HTTP mode."""
        print(json.dumps(data), flush=True)
        self.last_emitted = data
        dtype = data.get("type", "")
        if dtype in ("stt_result", "stt_error"):
            self.stt_result = data
        elif dtype in ("tts_done", "tts_error", "tts_stopped"):
            self.tts_result = data

        # Write human-readable messages to stderr if stdout is running in a terminal
        if sys.stdout.isatty():
            if dtype == "download_started":
                sys.stderr.write(f"\n>>> Starting download for {data.get('target', '').upper()} model ({data.get('model', '')})...\n")
                sys.stderr.flush()
            elif dtype == "download_progress":
                sys.stderr.write(f"\r>>> Progress: {data.get('pct', 0)}% completed.")
                sys.stderr.flush()
            elif dtype == "download_done":
                sys.stderr.write(f"\n>>> Success! {data.get('target', '').upper()} model downloaded successfully.\n")
                sys.stderr.flush()
            elif dtype == "download_error":
                sys.stderr.write(f"\n>>> ERROR: Failed to download {data.get('target', '').upper()} model: {data.get('error', '')}\n")
                sys.stderr.flush()

    def check_env(self, payload):
        """Check environment for voice capabilities."""
        stt_model_path = payload.get("stt_model_path", "")
        tts_model_path = payload.get("tts_model_path", "")
        venv_path = payload.get("venv_path", "")

        result = {
            "type": "env_check",
            "mic_available": False,
            "paplay_available": False,
            "aplay_available": False,
            "espeak_available": False,
            "venv_ready": False,
            "venv_exists": False,
            "stt_ready": False,
            "tts_ready": False,
            "sounddevice_ok": False,
            "faster_whisper_ok": False,
            "kokoro_ok": False,
            "numpy_ok": False,
            "stt_model_path_ok": False,
            "tts_model_path_ok": False,
            "stt_model_downloaded": False,
            "tts_model_downloaded": False,
        }

        # Check venv path existence
        if venv_path:
            venv_path = os.path.expanduser(venv_path)
            result["venv_exists"] = os.path.isdir(venv_path) and (
                os.path.exists(os.path.join(venv_path, "bin", "python")) or
                os.path.exists(os.path.join(venv_path, "bin", "python3"))
            )

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

        espeak_path = payload.get("espeak_path", "")
        if espeak_path:
            espeak_path = os.path.expanduser(espeak_path)
            if os.path.isdir(espeak_path):
                espeak_dir = espeak_path
            else:
                espeak_dir = os.path.dirname(espeak_path)
            if espeak_dir and espeak_dir not in os.environ.get("PATH", "").split(os.pathsep):
                os.environ["PATH"] = espeak_dir + os.pathsep + os.environ.get("PATH", "")
                os.environ["PHONEMIZER_ESPEAK_PATH"] = espeak_dir

        result["espeak_available"] = (shutil.which("espeak-ng") is not None) or (shutil.which("espeak") is not None)

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

        # Check if selected default models are downloaded in cache
        stt_model = payload.get("stt_model", "large-v3-turbo")
        stt_downloaded = False
        hf_cache = os.path.expanduser("~/.cache/huggingface/hub")
        if os.path.isdir(hf_cache):
            entry = f"models--Systran--faster-whisper-{stt_model}"
            repo_dir = os.path.join(hf_cache, entry)
            if os.path.isdir(repo_dir) and os.path.exists(os.path.join(repo_dir, "snapshots")):
                snapshots_dir = os.path.join(repo_dir, "snapshots")
                if os.path.exists(snapshots_dir) and os.listdir(snapshots_dir):
                    stt_downloaded = True
        result["stt_model_downloaded"] = stt_downloaded

        tts_model = payload.get("tts_model", "kokoro-82m")
        tts_downloaded = False
        if tts_model == "espeak-ng":
            tts_downloaded = bool(shutil.which("espeak-ng") or shutil.which("espeak"))
        elif tts_model == "piper":
            piper_path = os.path.expanduser("~/.local/share/kdeaichat/models/piper/en_US-lessac-medium.onnx")
            tts_downloaded = os.path.exists(piper_path)
        elif tts_model == "f5-tts":
            if os.path.isdir(hf_cache):
                entry = "models--m-a-p--F5-TTS"
                repo_dir = os.path.join(hf_cache, entry)
                if os.path.isdir(repo_dir) and os.path.exists(os.path.join(repo_dir, "snapshots")):
                    snapshots_dir = os.path.join(repo_dir, "snapshots")
                    if os.path.exists(snapshots_dir) and os.listdir(snapshots_dir):
                        tts_downloaded = True
        else: # kokoro-82m
            if os.path.isdir(hf_cache):
                entry = "models--hexgrad--Kokoro-82M"
                repo_dir = os.path.join(hf_cache, entry)
                if os.path.isdir(repo_dir) and os.path.exists(os.path.join(repo_dir, "snapshots")):
                    snapshots_dir = os.path.join(repo_dir, "snapshots")
                    if os.path.exists(snapshots_dir) and os.listdir(snapshots_dir):
                        tts_downloaded = True
        result["tts_model_downloaded"] = tts_downloaded

        # Check custom model paths strictly
        if stt_model_path:
            stt_p = os.path.expanduser(stt_model_path)
            stt_dir = os.path.dirname(stt_p) if os.path.isfile(stt_p) else stt_p
            if os.path.isdir(stt_dir):
                if os.path.exists(os.path.join(stt_dir, "model.bin")) and os.path.exists(os.path.join(stt_dir, "config.json")):
                    result["stt_model_path_ok"] = True

        if tts_model_path:
            tts_p = os.path.expanduser(tts_model_path)
            tts_dir = os.path.dirname(tts_p) if os.path.isfile(tts_p) else tts_p
            if os.path.isdir(tts_dir):
                config_file = os.path.join(tts_dir, "config.json")
                has_pth = any(f.endswith(".pth") for f in os.listdir(tts_dir))
                if os.path.exists(config_file) and has_pth:
                    result["tts_model_path_ok"] = True

        # Overall readiness
        is_venv = (hasattr(sys, "real_prefix") or (hasattr(sys, "base_prefix") and sys.base_prefix != sys.prefix))
        result["venv_ready"] = is_venv and result["sounddevice_ok"] and result["numpy_ok"]
        result["stt_ready"] = result["venv_ready"] and result["faster_whisper_ok"] and (
            result["stt_model_path_ok"] if stt_model_path else result["stt_model_downloaded"]
        )

        has_player = result["paplay_available"] or result["aplay_available"]
        has_tts_model = result["tts_model_path_ok"] if tts_model_path else result["tts_model_downloaded"]

        tts_ready = False
        if tts_model == "espeak-ng":
            tts_ready = result["espeak_available"] and has_player
        elif tts_model == "piper":
            has_piper_bin = bool(shutil.which("piper"))
            if not has_piper_bin:
                venv_bin = os.path.dirname(sys.executable)
                has_piper_bin = os.path.exists(os.path.join(venv_bin, "piper"))
            try:
                import piper
                has_piper_pkg = True
            except ImportError:
                has_piper_pkg = False
            tts_ready = (has_piper_bin or has_piper_pkg) and has_tts_model and has_player
        elif tts_model == "f5-tts":
            try:
                import f5_tts
                has_f5 = True
            except ImportError:
                has_f5 = False
            tts_ready = has_f5 and has_tts_model and has_player
        elif tts_model == "coqui-tts":
            try:
                import TTS
                has_coqui = True
            except ImportError:
                has_coqui = False
            tts_ready = has_coqui and has_tts_model and has_player
        else: # kokoro-82m
            tts_ready = result["kokoro_ok"] and result["espeak_available"] and has_tts_model and has_player

        result["tts_ready"] = tts_ready

        self.emit(result)

    def list_models(self, payload):
        """List available and downloaded models."""
        result = {
            "type": "models_list",
            "stt_models": [],
            "tts_models": [],
        }

        stt_list = ["large-v3-turbo", "large-v3", "large-v2", "large-v1", "medium", "medium.en", "small", "small.en", "base", "base.en", "tiny", "tiny.en"]
        sizes = {
            "large-v3-turbo": "~1.5 GB",
            "large-v3": "~3.0 GB",
            "large-v2": "~3.0 GB",
            "large-v1": "~3.0 GB",
            "medium": "~1.5 GB",
            "medium.en": "~1.5 GB",
            "small": "~460 MB",
            "small.en": "~460 MB",
            "base": "~140 MB",
            "base.en": "~140 MB",
            "tiny": "~75 MB",
            "tiny.en": "~75 MB"
        }
        hf_cache = os.path.expanduser("~/.cache/huggingface/hub")
        for name in stt_list:
            downloaded = False
            if os.path.isdir(hf_cache):
                entry = f"models--Systran--faster-whisper-{name}"
                repo_dir = os.path.join(hf_cache, entry)
                if os.path.isdir(repo_dir) and os.path.exists(os.path.join(repo_dir, "snapshots")):
                    snapshots_dir = os.path.join(repo_dir, "snapshots")
                    if os.path.exists(snapshots_dir) and os.listdir(snapshots_dir):
                        downloaded = True

            result["stt_models"].append({
                "name": name,
                "downloaded": downloaded,
                "size": sizes.get(name, "~1.0 GB"),
            })

        # Check TTS models
        tts_list = ["kokoro-82m", "piper", "f5-tts", "espeak-ng"]
        sizes = {
            "kokoro-82m": "~150 MB",
            "piper": "~15 MB",
            "f5-tts": "~1.5 GB",
            "espeak-ng": "N/A (System)"
        }
        for name in tts_list:
            downloaded = False
            if name == "espeak-ng":
                downloaded = bool(shutil.which("espeak-ng") or shutil.which("espeak"))
            elif name == "piper":
                piper_path = os.path.expanduser("~/.local/share/kdeaichat/models/piper/en_US-lessac-medium.onnx")
                downloaded = os.path.exists(piper_path)
            elif name == "f5-tts":
                if os.path.isdir(hf_cache):
                    entry = "models--m-a-p--F5-TTS"
                    repo_dir = os.path.join(hf_cache, entry)
                    if os.path.isdir(repo_dir) and os.path.exists(os.path.join(repo_dir, "snapshots")):
                        snapshots_dir = os.path.join(repo_dir, "snapshots")
                        if os.path.exists(snapshots_dir) and os.listdir(snapshots_dir):
                            downloaded = True
            else: # kokoro-82m
                if os.path.isdir(hf_cache):
                    entry = "models--hexgrad--Kokoro-82M"
                    repo_dir = os.path.join(hf_cache, entry)
                    if os.path.isdir(repo_dir) and os.path.exists(os.path.join(repo_dir, "snapshots")):
                        snapshots_dir = os.path.join(repo_dir, "snapshots")
                        if os.path.exists(snapshots_dir) and os.listdir(snapshots_dir):
                            downloaded = True

            result["tts_models"].append({
                "name": name,
                "downloaded": downloaded,
                "size": sizes.get(name, "Unknown"),
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
        self.download_thread = thread
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
        self.download_thread = thread
        self.emit({"type": "download_started", "target": "tts", "model": "kokoro-82m"})

    def start_stt(self, payload):
        """Speech-to-text recording and transcription."""
        if self.recording:
            self.emit({"type": "stt_error", "error": "Already recording"})
            return

        self.recording = True
        self.stop_recording = False

        def do_stt():
            try:
                # Fetch payload values locally to prevent enclosing scope assignment/UnboundLocalError
                duration = payload.get("duration", 10)
                language = payload.get("language", "en")
                model_name = payload.get("model", "large-v3-turbo")
                custom_model_path = payload.get("model_path", "")

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
                    self.current_status = "loading_model"
                    self.emit({"type": "stt_status", "status": "loading_model"})
                    try:
                        # Pre-load CUDA/cuDNN libraries from venv if present
                        try:
                            import ctypes
                            import glob
                            import sys
                            for p in sys.path:
                                if os.path.isdir(p):
                                    nvidia_libs = glob.glob(os.path.join(p, "nvidia", "*", "lib", "*.so*"))
                                    for lib in sorted(nvidia_libs):
                                        try:
                                            ctypes.CDLL(lib)
                                        except Exception:
                                            pass
                        except Exception:
                            pass

                        from faster_whisper import WhisperModel
                        import torch
                        device = "cuda" if torch.cuda.is_available() else "cpu"
                        compute_type = "float16" if device == "cuda" else "int8"
                        
                        try:
                            if custom_model_path:
                                custom_model_path = os.path.expanduser(custom_model_path)
                                custom_dir = os.path.dirname(custom_model_path) if os.path.isfile(custom_model_path) else custom_model_path
                                if os.path.isdir(custom_dir):
                                    self.stt_model = WhisperModel(custom_dir, device=device, compute_type=compute_type)
                                else:
                                    self.stt_model = WhisperModel(model_name, device=device, compute_type=compute_type)
                            else:
                                self.stt_model = WhisperModel(model_name, device=device, compute_type=compute_type)
                        except Exception:
                            # Fallback to CPU if CUDA fails
                            if device == "cuda":
                                if custom_model_path:
                                    custom_model_path = os.path.expanduser(custom_model_path)
                                    custom_dir = os.path.dirname(custom_model_path) if os.path.isfile(custom_model_path) else custom_model_path
                                    if os.path.isdir(custom_dir):
                                        self.stt_model = WhisperModel(custom_dir, device="cpu", compute_type="int8")
                                    else:
                                        self.stt_model = WhisperModel(model_name, device="cpu", compute_type="int8")
                                else:
                                    self.stt_model = WhisperModel(model_name, device="cpu", compute_type="int8")
                            else:
                                raise

                        self.stt_model_name = model_name
                    except Exception as e:
                        self.emit({"type": "stt_error", "error": "Failed to load STT model: " + str(e)})
                        self.recording = False
                        return

                self.current_status = "recording"
                self.emit({"type": "stt_status", "status": "recording"})

                # Record audio in chunks, checking stop_recording
                sample_rate = 16000
                chunk_duration = 1.0  # seconds per chunk
                all_audio = []
                total_recorded = 0.0

                while total_recorded < duration and not self.stop_recording:
                    self.current_countdown = int(duration - total_recorded)
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

                self.current_status = "transcribing"
                self.emit({"type": "stt_status", "status": "transcribing"})

                # Concatenate and transcribe
                import numpy as np
                audio = np.concatenate(all_audio)

                # Save audio to temp file for playback
                import soundfile as sf
                audio_path = self.temp_audio_path
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
                self.current_status = "idle"
                self.current_countdown = 0

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
        if not payload.get("text", ""):
            self.emit({"type": "tts_error", "error": "No text provided"})
            return

        if self.tts_playing:
            self.stop_tts = True
            time.sleep(0.2)

        self.tts_playing = True
        self.stop_tts = False

        def do_tts():
            try:
                # Fetch payload values locally to prevent enclosing scope assignment/UnboundLocalError
                text = payload.get("text", "")
                voice = payload.get("voice", "af_heart")
                lang_code = payload.get("lang_code", "a")
                custom_model_path = payload.get("model_path", "")
                espeak_path = payload.get("espeak_path", "")
                model = payload.get("model", "kokoro-82m")

                # Setup custom espeak path if provided
                if espeak_path:
                    ep = os.path.expanduser(espeak_path)
                    espeak_dir = ep if os.path.isdir(ep) else os.path.dirname(ep)
                    if espeak_dir and espeak_dir not in os.environ.get("PATH", "").split(os.pathsep):
                        os.environ["PATH"] = espeak_dir + os.pathsep + os.environ.get("PATH", "")
                        os.environ["PHONEMIZER_ESPEAK_PATH"] = espeak_dir

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

                self.current_status = "synthesizing"
                self.emit({"type": "tts_status", "status": "synthesizing"})

                if model == "espeak-ng":
                    if not (shutil.which("espeak-ng") or shutil.which("espeak")):
                        self.emit({"type": "tts_error", "error": "espeak-ng/espeak not installed. Install with: sudo apt install espeak-ng"})
                        return

                    espeak_voice = voice if voice and not voice.startswith("af_") and not voice.startswith("bf_") else "en-us"
                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                        tmp_path = f.name

                    cmd = ["espeak-ng"]
                    if espeak_voice:
                        cmd.extend(["-v", espeak_voice])
                    cmd.extend(["-w", tmp_path, text])
                    subprocess.run(cmd, check=True)

                    self.current_status = "playing"
                    self.emit({"type": "tts_status", "status": "playing"})

                    if player == "paplay":
                        proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif player == "aplay":
                        proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    while proc.poll() is None:
                        if self.stop_tts:
                            proc.terminate()
                            break
                        time.sleep(0.1)

                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    self.emit({"type": "tts_done"})

                elif model == "piper":
                    model_path = custom_model_path
                    if not model_path:
                        model_path = os.path.expanduser("~/.local/share/kdeaichat/models/piper/en_US-lessac-medium.onnx")

                    if not os.path.exists(model_path):
                        self.emit({"type": "tts_error", "error": f"Piper model not found. Please click Download or specify a custom path. Searched: {model_path}"})
                        return

                    config_path = model_path + ".json"
                    if not os.path.exists(config_path) and model_path.endswith(".onnx"):
                        config_path = model_path[:-5] + ".onnx.json"

                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                        tmp_path = f.name

                    piper_bin = shutil.which("piper")
                    if not piper_bin:
                        venv_bin = os.path.dirname(sys.executable)
                        venv_piper = os.path.join(venv_bin, "piper")
                        if os.path.exists(venv_piper):
                            piper_bin = venv_piper

                    if piper_bin:
                        proc = subprocess.Popen(
                            [piper_bin, "--model", model_path, "--output_file", tmp_path],
                            stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL
                        )
                        proc.communicate(input=text.encode("utf-8"))
                    else:
                        try:
                            from piper import PiperVoice
                            import wave
                            voice_obj = PiperVoice.load(model_path, config_path=config_path)
                            with wave.open(tmp_path, "wb") as wav_file:
                                voice_obj.synthesize(text, wav_file)
                        except Exception as pe:
                            self.emit({"type": "tts_error", "error": f"Failed to run Piper. piper-tts is not installed or configured: {str(pe)}"})
                            return

                    self.current_status = "playing"
                    self.emit({"type": "tts_status", "status": "playing"})

                    if player == "paplay":
                        proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif player == "aplay":
                        proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    while proc.poll() is None:
                        if self.stop_tts:
                            proc.terminate()
                            break
                        time.sleep(0.1)

                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    self.emit({"type": "tts_done"})

                elif model == "f5-tts":
                    try:
                        from f5_tts.api import F5TTS
                        import soundfile as sf
                    except ImportError:
                        self.emit({"type": "tts_error", "error": "f5-tts is not installed in the virtual environment. Please run: pip install f5-tts"})
                        return

                    f5_instance = F5TTS()
                    wav, sr, spect = f5_instance.infer(
                        gen_text=text,
                        file_wave=None,
                        ref_text=""
                    )

                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                        tmp_path = f.name
                        sf.write(tmp_path, wav, sr)

                    self.current_status = "playing"
                    self.emit({"type": "tts_status", "status": "playing"})

                    if player == "paplay":
                        proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif player == "aplay":
                        proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    while proc.poll() is None:
                        if self.stop_tts:
                            proc.terminate()
                            break
                        time.sleep(0.1)

                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    self.emit({"type": "tts_done"})

                elif model == "coqui-tts":
                    try:
                        from TTS.api import TTS
                    except ImportError:
                        self.emit({"type": "tts_error", "error": "coqui-tts is not installed in the virtual environment. Please run: pip install TTS"})
                        return

                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                        tmp_path = f.name

                    tts_voice = voice if voice and not voice.startswith("af_") and not voice.startswith("bf_") else "tts_models/en/ljspeech/glow-tts"
                    tts_instance = TTS(model_name=tts_voice)
                    tts_instance.tts_to_file(text=text, file_path=tmp_path)

                    self.current_status = "playing"
                    self.emit({"type": "tts_status", "status": "playing"})

                    if player == "paplay":
                        proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif player == "aplay":
                        proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    while proc.poll() is None:
                        if self.stop_tts:
                            proc.terminate()
                            break
                        time.sleep(0.1)

                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    self.emit({"type": "tts_done"})

                else:
                    # Default/kokoro-82m
                    if not (shutil.which("espeak-ng") or shutil.which("espeak")):
                        self.emit({"type": "tts_error", "error": "espeak-ng/espeak not installed. Install with: sudo apt install espeak-ng"})
                        return

                    from kokoro import KPipeline
                    from kokoro.model import KModel
                    import soundfile as sf
                    import numpy as np
                    import torch

                    if self.tts_pipeline is None:
                        if custom_model_path:
                            custom_model_path = os.path.expanduser(custom_model_path)
                            custom_dir = os.path.dirname(custom_model_path) if os.path.isfile(custom_model_path) else custom_model_path
                            config_file = os.path.join(custom_dir, "config.json")
                            model_file = None
                            if os.path.exists(custom_dir):
                                for f in os.listdir(custom_dir):
                                    if f.endswith(".pth"):
                                        model_file = os.path.join(custom_dir, f)
                                        break

                            if os.path.exists(config_file) and model_file and os.path.exists(model_file):
                                device = 'cuda' if torch.cuda.is_available() else 'cpu'
                                kmodel = KModel(config=config_file, model=model_file).to(device).eval()
                                self.tts_pipeline = KPipeline(lang_code=lang_code, model=kmodel)
                            else:
                                device = 'cuda' if torch.cuda.is_available() else 'cpu'
                                self.tts_pipeline = KPipeline(lang_code=lang_code, device=device)
                        else:
                            device = 'cuda' if torch.cuda.is_available() else 'cpu'
                            self.tts_pipeline = KPipeline(lang_code=lang_code, device=device)

                    self.current_status = "playing"
                    self.emit({"type": "tts_status", "status": "playing"})

                    resolved_voice = voice
                    if custom_model_path:
                        custom_dir = os.path.dirname(custom_model_path) if os.path.isfile(custom_model_path) else custom_model_path
                        custom_voice_path = os.path.join(custom_dir, f"{voice}.pt")
                        if os.path.exists(custom_voice_path):
                            resolved_voice = custom_voice_path

                    for _, _, audio in self.tts_pipeline(text, voice=resolved_voice):
                        if self.stop_tts:
                            break

                        audio = np.asarray(audio, dtype=np.float32)
                        if audio.max() > 0:
                            audio = audio / max(abs(audio.max()), abs(audio.min())) * 0.9

                        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                            tmp_path = f.name
                            sf.write(tmp_path, audio, 24000)

                        if player == "paplay":
                            proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        elif player == "aplay":
                            proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        else:
                            proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                        while proc.poll() is None:
                            if self.stop_tts:
                                proc.terminate()
                                break
                            time.sleep(0.1)

                        try:
                            os.unlink(tmp_path)
                        except OSError:
                            pass
                    self.emit({"type": "tts_done"})

            except Exception as e:
                self.emit({"type": "tts_error", "error": str(e)})
            finally:
                self.tts_playing = False
                self.current_status = "idle"

        self.tts_thread = threading.Thread(target=do_tts, daemon=True)
        self.tts_thread.start()

    def stop_tts_cmd(self, payload):
        """Stop TTS playback."""
        if self.tts_playing:
            self.stop_tts = True
            self.emit({"type": "tts_status", "status": "stopping"})
        else:
            self.emit({"type": "tts_stopped"})

    def process_server_command(self, cmd_data, mode):
        """Process a command from the HTTP server and block until done if it is STT or TTS."""
        cmd = cmd_data.get("cmd", "")
        self.last_emitted = None
        
        try:
            if cmd == "start_stt":
                self.stt_result = None
                self.start_stt(cmd_data)
                while self.recording and self.stt_result is None:
                    time.sleep(0.05)
                timeout = time.time() + 2.0
                while self.stt_result is None and time.time() < timeout:
                    time.sleep(0.05)
                return self.stt_result or {"type": "stt_error", "error": "STT finished with no result"}
            elif cmd == "stop_stt":
                self.stop_stt(cmd_data)
                return {"type": "stt_status", "status": "stopping"}
            elif cmd == "tts":
                self.tts_result = None
                self.tts(cmd_data)
                while self.tts_playing and self.tts_result is None:
                    time.sleep(0.05)
                timeout = time.time() + 2.0
                while self.tts_result is None and time.time() < timeout:
                    time.sleep(0.05)
                return self.tts_result or {"type": "tts_done"}
            elif cmd == "stop_tts":
                self.stop_tts_cmd(cmd_data)
                return {"type": "tts_status", "status": "stopping"}
            elif cmd == "check_env":
                self.check_env(cmd_data)
                return self.last_emitted
            elif cmd == "list_models":
                self.list_models(cmd_data)
                return self.last_emitted
            elif cmd == "play_audio":
                self.play_audio(cmd_data)
                return {"type": "play_started"}
            else:
                return {"type": "error", "error": f"Unsupported command in HTTP server: {cmd}"}
        except Exception as e:
            return {"type": "error", "error": f"Exception in server command processor: {str(e)}"}

    def run_http_server(self, port, mode):
        """Run a simple multithreaded HTTP server on localhost."""
        import http.server
        from http.server import HTTPServer
        try:
            from http.server import ThreadingHTTPServer as HTTPServerClass
        except ImportError:
            from socketserver import ThreadingMixIn
            class ThreadingHTTPServerClass(ThreadingMixIn, HTTPServer):
                pass
            HTTPServerClass = ThreadingHTTPServerClass

        helper_self = self

        class CustomHandler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                pass

            def do_OPTIONS(self):
                self.send_response(204)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Content-Type")
                self.end_headers()

            def do_GET(self):
                if self.path == "/status":
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.end_headers()
                    status_data = {
                        "status": helper_self.current_status,
                        "countdown": helper_self.current_countdown,
                        "recorded_audio_path": helper_self.temp_audio_path if os.path.exists(helper_self.temp_audio_path) else ""
                    }
                    self.wfile.write(json.dumps(status_data).encode("utf-8"))
                else:
                    self.send_response(404)
                    self.end_headers()

            def do_POST(self):
                if self.path in ("/command", "/"):
                    content_length = int(self.headers['Content-Length'])
                    post_data = self.rfile.read(content_length)
                    try:
                        payload = json.loads(post_data.decode('utf-8'))
                    except Exception:
                        self.send_response(400)
                        self.send_header("Access-Control-Allow-Origin", "*")
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": "Invalid JSON"}).encode("utf-8"))
                        return

                    res = helper_self.process_server_command(payload, mode)
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.end_headers()
                    self.wfile.write(json.dumps(res).encode("utf-8"))
                else:
                    self.send_response(404)
                    self.end_headers()

        server = HTTPServerClass(("127.0.0.1", port), CustomHandler)
        print(f"Starting {mode} server on 127.0.0.1:{port}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass

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
        if hasattr(self, 'download_thread') and self.download_thread and self.download_thread.is_alive():
            self.download_thread.join(timeout=300)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--stt-server", action="store_true", help="Run STT HTTP server")
    parser.add_argument("--tts-server", action="store_true", help="Run TTS HTTP server")
    parser.add_argument("--port", type=int, default=None, help="HTTP server port")
    args = parser.parse_args()

    helper = VoiceHelper()
    if args.stt_server:
        port = args.port or 9015
        helper.run_http_server(port, mode="stt")
    elif args.tts_server:
        port = args.port or 9016
        helper.run_http_server(port, mode="tts")
    else:
        helper.run()
