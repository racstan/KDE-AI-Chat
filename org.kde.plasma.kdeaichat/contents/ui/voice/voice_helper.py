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
import signal


class VoiceHelper:
    def __init__(self):
        self.stt_model = None
        self.stt_model_name = None
        self.stt_device = "cpu"
        self.tts_pipeline = None
        self.tts_device = "cpu"
        self.recording = False
        self.stop_recording = False
        self.tts_playing = False
        self.stop_tts = False
        self.tts_paused = False
        self.current_tts_proc = None
        self.stt_thread = None
        self.tts_thread = None
        self.last_emitted = None
        self.stt_result = None
        self.tts_result = None
        self.current_status = "idle"
        self.current_countdown = 0
        self.temp_audio_path = os.path.join(tempfile.gettempdir(), "kdeaichat_stt_test.wav")
        self._nvidia_libs_preloaded = False

    def _preload_nvidia_libs(self):
        """Pre-load CUDA/cuDNN libraries from venv if present to prevent version mismatches."""
        if self._nvidia_libs_preloaded:
            return
        try:
            import ctypes
            import glob
            import sys
            import os
            for p in sys.path:
                if os.path.isdir(p):
                    nvidia_libs = glob.glob(os.path.join(p, "nvidia", "*", "lib", "*.so*"))
                    for lib in sorted(nvidia_libs):
                        try:
                            ctypes.CDLL(lib)
                        except Exception:
                            pass
            self._nvidia_libs_preloaded = True
        except Exception:
            pass

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

    def _detect_tts_model_type(self, model_path):
        if not model_path or not model_path.strip():
            return "unknown"
        
        mp_lower = model_path.lower()
        if "kokoro" in mp_lower or "voices.bin" in mp_lower:
            return "kokoro-82m"
        if "piper" in mp_lower or mp_lower.endswith(".onnx") or mp_lower.endswith(".onnx.json"):
            return "piper"
        if "f5" in mp_lower:
            return "f5-tts"
        if "coqui" in mp_lower:
            return "coqui-tts"
        
        p = os.path.expanduser(model_path.strip())
        if os.path.isdir(p):
            try:
                files = os.listdir(p)
                if any("voices.bin" in f or "kokoro" in f.lower() for f in files):
                    return "kokoro-82m"
                if any(f.endswith(".onnx") for f in files):
                    return "piper"
                if any("f5" in f.lower() for f in files):
                    return "f5-tts"
                if any("coqui" in f.lower() for f in files):
                    return "coqui-tts"
            except Exception:
                pass
            
        return "kokoro-82m"

    def check_env(self, payload):
        """Check environment for voice capabilities."""
        stt_model_path = payload.get("stt_model_path", "")
        tts_model_path = payload.get("tts_model_path", "")
        venv_path = payload.get("venv_path", "")
        espeak_path = payload.get("espeak_path", "")
        gpu_requested = payload.get("gpu_requested", False)

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
            "tts_model_downloaded": False,
            "tts_model_type": "unknown",
            "gpu_ok": False,
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
            result["sounddevice_ok"] = True
            try:
                devices = sd.query_devices()
                input_devices = [d for d in devices if d.get("max_input_channels", 0) > 0]
                result["mic_available"] = len(input_devices) > 0
            except Exception:
                pass
        except Exception:
            pass

        # Check audio players
        result["paplay_available"] = shutil.which("paplay") is not None
        result["aplay_available"] = shutil.which("aplay") is not None

        # Setup custom espeak path if provided
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
        except Exception:
            pass
            
        # Always check if GPU libraries are available
        self._preload_nvidia_libs()
        try:
            import torch
            result["torch_cuda_version"] = getattr(torch.version, 'cuda', None)
            if torch.cuda.is_available():
                result["gpu_ok"] = True
        except Exception:
            pass

        try:
            from faster_whisper import WhisperModel
            result["faster_whisper_ok"] = True
        except Exception:
            pass

        try:
            from kokoro import KPipeline
            result["kokoro_ok"] = True
        except Exception:
            pass

        # Check custom model paths strictly
        if stt_model_path:
            if stt_model_path.lower() in ["tiny", "tiny.en", "base", "base.en", "small", "small.en", "medium", "medium.en", "large-v1", "large-v2", "large-v3", "large"]:
                result["stt_model_path_ok"] = True
            else:
                stt_p = os.path.expanduser(stt_model_path)
                stt_dir = os.path.dirname(stt_p) if os.path.isfile(stt_p) else stt_p
                if os.path.isdir(stt_dir):
                    if os.path.exists(os.path.join(stt_dir, "model.bin")) or any(f.endswith(".bin") or f.endswith(".json") for f in os.listdir(stt_dir)):
                        result["stt_model_path_ok"] = True
        else:
            # Empty path relies on faster_whisper auto-download
            result["stt_model_path_ok"] = True

        if tts_model_path:
            tts_p = os.path.expanduser(tts_model_path)
            if os.path.isfile(tts_p):
                result["tts_model_path_ok"] = True
            else:
                tts_dir = tts_p
                if os.path.isdir(tts_dir):
                    has_model_files = any(
                        f.endswith(".pth") or f.endswith(".onnx") or f.endswith(".bin") or f.endswith(".pt") or f == "config.json"
                        for f in os.listdir(tts_dir)
                    )
                    if has_model_files:
                        result["tts_model_path_ok"] = True
        else:
            # Empty path relies on kokoro auto-download
            result["tts_model_path_ok"] = True

        # Overall readiness
        is_venv = (hasattr(sys, "real_prefix") or (hasattr(sys, "base_prefix") and sys.base_prefix != sys.prefix))
        result["venv_ready"] = is_venv and result["sounddevice_ok"] and result["numpy_ok"]
        if gpu_requested and not result["gpu_ok"]:
            result["venv_ready"] = False
        result["stt_ready"] = (
            result["venv_ready"]
            and result["faster_whisper_ok"]
            and result["stt_model_path_ok"]
            and result["mic_available"]
        )

        has_player = result["paplay_available"] or result["aplay_available"]
        
        tts_model = self._detect_tts_model_type(tts_model_path)
        result["tts_model_type"] = tts_model
        has_tts_model = result["tts_model_path_ok"]

        tts_ready = False
        if tts_model == "unknown":
            tts_ready = False
        elif tts_model == "espeak-ng":
            tts_ready = result["espeak_available"] and has_tts_model and has_player
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
            tts_ready = result.get("kokoro_ok", False) and result.get("espeak_available", False) and has_tts_model and has_player

        result["tts_ready"] = tts_ready

        self.emit(result)

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
                model_name = payload.get("model", "small")
                custom_model_path = payload.get("model_path", "")
                gpu_requested = payload.get("gpu_requested", False)
                if not custom_model_path:
                    self.emit({"type": "stt_error", "error": "Select an STT model folder first."})
                    self.recording = False
                    return

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
                model_identity = os.path.expanduser(custom_model_path) if custom_model_path else model_name
                if self.stt_model is None or self.stt_model_name != model_identity:
                    self.current_status = "loading_model"
                    self.emit({"type": "stt_status", "status": "loading_model", "device": "loading..."})
                    try:
                        # Pre-load CUDA/cuDNN libraries from venv if present
                        self._preload_nvidia_libs()

                        from faster_whisper import WhisperModel
                        import torch
                        device = "cuda" if gpu_requested and torch.cuda.is_available() else "cpu"
                        self.stt_device = device
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

                        self.stt_model_name = model_identity
                    except Exception as e:
                        self.emit({"type": "stt_error", "error": "Failed to load STT model: " + str(e)})
                        self.recording = False
                        return

                self.current_status = "recording"
                self.emit({"type": "stt_status", "status": "recording", "device": self.stt_device})

                # Record audio using a single continuous stream to prevent microphone icon flickering on the taskbar
                sample_rate = 16000
                all_audio = []
                total_recorded = 0.0

                stop_stt_file = os.path.join(tempfile.gettempdir(), "kdeaichat_stop_stt")
                if os.path.exists(stop_stt_file):
                    try: os.remove(stop_stt_file)
                    except OSError: pass

                with sd.InputStream(samplerate=sample_rate, channels=1, dtype="float32") as stream:
                    chunk_duration = 0.1  # Check stop_recording every 100ms
                    chunk_frames = int(chunk_duration * sample_rate)
                    while (duration <= 0 or total_recorded < duration) and not self.stop_recording:
                        if os.path.exists(stop_stt_file):
                            self.stop_recording = True
                            break
                        self.current_countdown = int(duration - total_recorded) if duration > 0 else 0
                        chunk, overflowed = stream.read(chunk_frames)
                        all_audio.append(chunk.flatten())
                        total_recorded += chunk_duration

                if not all_audio:
                    self.emit({"type": "stt_result", "text": "", "duration": 0})
                    self.recording = False
                    return

                self.current_status = "transcribing"
                self.emit({"type": "stt_status", "status": "transcribing", "device": self.stt_device})

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
                    "device": self.stt_device,
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
            open(os.path.join(tempfile.gettempdir(), "kdeaichat_stop_stt"), "w").close()
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
                raw_text = payload.get("text", "")
                import re
                emoji_pattern = re.compile(r"[\U00010000-\U0010ffff]|[\u2600-\u27bf]")
                text = emoji_pattern.sub("", raw_text)
                voice = payload.get("voice", "")
                lang_code = payload.get("lang_code", "a")
                custom_model_path = payload.get("model_path", "")
                espeak_path = payload.get("espeak_path", "")
                gpu_requested = payload.get("gpu_requested", False)
                if not custom_model_path:
                    self.emit({"type": "tts_error", "error": "Select a TTS model folder first."})
                    return
                model = self._detect_tts_model_type(custom_model_path)

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
                self.emit({"type": "tts_status", "status": "synthesizing", "device": "cpu"})

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
                    self.tts_device = "cpu"
                    self.emit({"type": "tts_status", "status": "playing", "device": "cpu"})

                    if player == "paplay":
                        proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif player == "aplay":
                        proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    self.current_tts_proc = proc
                    while proc.poll() is None:
                        if self.stop_tts or os.path.exists(stop_tts_file):
                            proc.terminate()
                            break
                        if self.tts_paused:
                            time.sleep(0.1)
                            continue
                        time.sleep(0.1)
                    self.current_tts_proc = None

                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    self.emit({"type": "tts_done", "device": self.tts_device})

                stop_tts_file = os.path.join(tempfile.gettempdir(), "kdeaichat_stop_tts")
                if os.path.exists(stop_tts_file):
                    try: os.remove(stop_tts_file)
                    except OSError: pass

                if model == "piper":
                    model_path = custom_model_path
                    model_path = os.path.expanduser(model_path)
                    if os.path.isdir(model_path):
                        candidates = [
                            os.path.join(model_path, f)
                            for f in os.listdir(model_path)
                            if f.endswith(".onnx")
                        ]
                        model_path = candidates[0] if candidates else model_path

                    if not os.path.exists(model_path):
                        self.emit({"type": "tts_error", "error": f"TTS model file not found in selected folder. Searched: {model_path}"})
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
                            self.emit({"type": "tts_error", "error": f"Failed to run selected TTS model. Required engine support may be missing: {str(pe)}"})
                            return

                    self.current_status = "playing"
                    self.tts_device = "cpu"
                    self.emit({"type": "tts_status", "status": "playing", "device": "cpu"})

                    if player == "paplay":
                        proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif player == "aplay":
                        proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    self.current_tts_proc = proc
                    while proc.poll() is None:
                        if self.stop_tts or os.path.exists(stop_tts_file):
                            proc.terminate()
                            break
                        if self.tts_paused:
                            time.sleep(0.1)
                            continue
                        time.sleep(0.1)
                    self.current_tts_proc = None

                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    self.emit({"type": "tts_done", "device": self.tts_device})

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
                    self.tts_device = "cpu"
                    self.emit({"type": "tts_status", "status": "playing", "device": "cpu"})

                    if player == "paplay":
                        proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif player == "aplay":
                        proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    self.current_tts_proc = proc
                    while proc.poll() is None:
                        if self.stop_tts or os.path.exists(stop_tts_file):
                            proc.terminate()
                            break
                        if self.tts_paused:
                            time.sleep(0.1)
                            continue
                        time.sleep(0.1)
                    self.current_tts_proc = None

                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    self.emit({"type": "tts_done", "device": self.tts_device})

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
                    self.tts_device = "cpu"
                    self.emit({"type": "tts_status", "status": "playing", "device": "cpu"})

                    if player == "paplay":
                        proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    elif player == "aplay":
                        proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    else:
                        proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                    self.current_tts_proc = proc
                    while proc.poll() is None:
                        if self.stop_tts or os.path.exists(stop_tts_file):
                            proc.terminate()
                            break
                        if self.tts_paused:
                            time.sleep(0.1)
                            continue
                        time.sleep(0.1)
                    self.current_tts_proc = None

                    try:
                        os.unlink(tmp_path)
                    except OSError:
                        pass
                    self.emit({"type": "tts_done", "device": self.tts_device})

                else:
                    # Default/kokoro-82m
                    if not (shutil.which("espeak-ng") or shutil.which("espeak")):
                        self.emit({"type": "tts_error", "error": "espeak-ng/espeak not installed. Install with: sudo apt install espeak-ng"})
                        return

                    self._preload_nvidia_libs()
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
                                device = 'cuda' if gpu_requested and torch.cuda.is_available() else 'cpu'
                                self.tts_device = device
                                kmodel = KModel(config=config_file, model=model_file).to(device).eval()
                                self.tts_pipeline = KPipeline(lang_code=lang_code, model=kmodel)
                            else:
                                device = 'cuda' if gpu_requested and torch.cuda.is_available() else 'cpu'
                                self.tts_device = device
                                self.tts_pipeline = KPipeline(lang_code=lang_code, device=device)
                        else:
                            device = 'cuda' if gpu_requested and torch.cuda.is_available() else 'cpu'
                            self.tts_device = device
                            self.tts_pipeline = KPipeline(lang_code=lang_code, device=device)

                    self.current_status = "playing"
                    self.emit({"type": "tts_status", "status": "playing", "device": self.tts_device})

                    resolved_voice = voice
                    if custom_model_path:
                        custom_dir = os.path.dirname(custom_model_path) if os.path.isfile(custom_model_path) else custom_model_path
                        if voice:
                            custom_voice_path = os.path.join(custom_dir, f"{voice}.pt")
                            if os.path.exists(custom_voice_path):
                                resolved_voice = custom_voice_path
                        else:
                            try:
                                voice_files = sorted([f for f in os.listdir(custom_dir) if f.endswith(".pt")])
                                if voice_files:
                                    resolved_voice = os.path.join(custom_dir, voice_files[0])
                            except Exception:
                                pass

                    import queue
                    play_queue = queue.Queue()
                    
                    def playback_worker():
                        while True:
                            tmp_path = play_queue.get()
                            if tmp_path is None:
                                break
                                
                            if self.stop_tts or os.path.exists(stop_tts_file):
                                try:
                                    os.unlink(tmp_path)
                                except OSError:
                                    pass
                                play_queue.task_done()
                                continue
                                
                            if player == "paplay":
                                proc = subprocess.Popen(["paplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            elif player == "aplay":
                                proc = subprocess.Popen(["aplay", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            else:
                                proc = subprocess.Popen(["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", tmp_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                            self.current_tts_proc = proc
                            while proc.poll() is None:
                                if self.stop_tts or os.path.exists(stop_tts_file):
                                    proc.terminate()
                                    break
                                if self.tts_paused:
                                    time.sleep(0.1)
                                    continue
                                time.sleep(0.1)
                            self.current_tts_proc = None

                            try:
                                os.unlink(tmp_path)
                            except OSError:
                                pass
                                
                            play_queue.task_done()

                    playback_thread = threading.Thread(target=playback_worker, daemon=True)
                    playback_thread.start()

                    try:
                        import re
                        # Split the text into smaller chunks (paragraphs/lines) so that the pipeline 
                        # yields the first chunk immediately without phonemizing the entire huge document upfront.
                        paragraphs = [p.strip() for p in re.split(r'\n+', text) if p.strip()]

                        for para in paragraphs:
                            if self.stop_tts or os.path.exists(stop_tts_file):
                                break

                            for _, _, audio in self.tts_pipeline(para, voice=resolved_voice):
                                if self.stop_tts or os.path.exists(stop_tts_file):
                                    break
                                while self.tts_paused and not self.stop_tts:
                                    time.sleep(0.1)
                                if self.stop_tts or os.path.exists(stop_tts_file):
                                    break

                                audio = np.asarray(audio, dtype=np.float32)
                                if audio.max() > 0:
                                    audio = audio / max(abs(audio.max()), abs(audio.min())) * 0.9

                                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                                    tmp_path = f.name
                                    sf.write(tmp_path, audio, 24000)

                                play_queue.put(tmp_path)
                    finally:
                        play_queue.put(None)
                        playback_thread.join()
                        self.emit({"type": "tts_done", "device": self.tts_device})


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
            self.tts_paused = False
            if self.current_tts_proc:
                try:
                    self.current_tts_proc.send_signal(signal.SIGCONT)
                    self.current_tts_proc.terminate()
                except Exception:
                    pass
            self.emit({"type": "tts_status", "status": "stopping"})
        else:
            open(os.path.join(tempfile.gettempdir(), "kdeaichat_stop_tts"), "w").close()
            # Also terminate any background paplay processes spawned by our script
            try:
                subprocess.run(["pkill", "-f", "paplay.*kdeaichat"], stderr=subprocess.DEVNULL)
                subprocess.run(["pkill", "-f", "aplay.*kdeaichat"], stderr=subprocess.DEVNULL)
            except Exception:
                pass
            self.emit({"type": "tts_stopped"})

    def pause_tts_cmd(self, payload):
        """Pause TTS playback."""
        if self.tts_playing and not self.tts_paused:
            self.tts_paused = True
            if self.current_tts_proc:
                try:
                    self.current_tts_proc.send_signal(signal.SIGSTOP)
                except Exception:
                    pass
            self.emit({"type": "tts_status", "status": "paused"})

    def resume_tts_cmd(self, payload):
        """Resume TTS playback."""
        if self.tts_playing and self.tts_paused:
            self.tts_paused = False
            if self.current_tts_proc:
                try:
                    self.current_tts_proc.send_signal(signal.SIGCONT)
                except Exception:
                    pass
            self.emit({"type": "tts_status", "status": "playing"})

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
            elif cmd == "pause_tts":
                self.pause_tts_cmd(cmd_data)
                return {"type": "tts_status", "status": "paused"}
            elif cmd == "resume_tts":
                self.resume_tts_cmd(cmd_data)
                return {"type": "tts_status", "status": "playing"}
            elif cmd == "check_env":
                self.check_env(cmd_data)
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
                    vram_kb = 0
                    try:
                        import torch
                        if torch.cuda.is_available():
                            vram_kb = torch.cuda.memory_allocated() // 1024
                    except:
                        pass

                    status_data = {
                        "status": helper_self.current_status,
                        "countdown": helper_self.current_countdown,
                        "recorded_audio_path": helper_self.temp_audio_path if os.path.exists(helper_self.temp_audio_path) else "",
                        "stt_device": helper_self.stt_device,
                        "tts_device": helper_self.tts_device,
                        "vram_kb": vram_kb,
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
            "start_stt": self.start_stt,
            "stop_stt": self.stop_stt,
            "play_audio": self.play_audio,
            "tts": self.tts,
            "stop_tts": self.stop_tts_cmd,
            "pause_tts": self.pause_tts_cmd,
            "resume_tts": self.resume_tts_cmd,
        }

        handler = handlers.get(cmd)
        if handler:
            handler(cmd_data)
        else:
            self.emit({"type": "error", "error": "Unknown command: " + cmd})

    def run(self):
        """Main loop: read commands from stdin."""
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            self.process_command(line)
        self.wait_for_background_work()

    def wait_for_background_work(self):
        """Wait for one-shot command threads and emit a timeout instead of hanging."""
        # Wait for any running threads before exiting
        if self.stt_thread and self.stt_thread.is_alive():
            self.stt_thread.join(timeout=45)
            if self.stt_thread.is_alive():
                self.recording = False
                self.emit({"type": "stt_error", "error": "STT test timed out while loading or transcribing. Try a smaller model or check that the selected folder matches the STT engine."})
        if self.tts_thread and self.tts_thread.is_alive():
            self.tts_thread.join(timeout=60)
            if self.tts_thread.is_alive():
                self.tts_playing = False
                self.emit({"type": "tts_error", "error": "TTS test timed out while loading or creating speech. Try a smaller model or check that the selected folder and voice name match the TTS engine."})
        if hasattr(self, 'download_thread') and self.download_thread and self.download_thread.is_alive():
            self.download_thread.join(timeout=300)


if __name__ == "__main__":
    import argparse
    import base64
    parser = argparse.ArgumentParser()
    parser.add_argument("--stt-server", action="store_true", help="Run STT HTTP server")
    parser.add_argument("--tts-server", action="store_true", help="Run TTS HTTP server")
    parser.add_argument("--port", type=int, default=None, help="HTTP server port")
    parser.add_argument("--command-json", default="", help="Run one JSON command and exit")
    parser.add_argument("--command-b64", default="", help="Run one base64-encoded JSON command and exit")
    args = parser.parse_args()

    helper = VoiceHelper()
    if args.command_b64:
        try:
            command_json = base64.b64decode(args.command_b64.encode("ascii")).decode("utf-8")
            helper.process_command(command_json)
            helper.wait_for_background_work()
        except Exception as e:
            helper.emit({"type": "error", "error": "Invalid encoded voice command: " + str(e)})
    elif args.command_json:
        helper.process_command(args.command_json)
        helper.wait_for_background_work()
    elif args.stt_server:
        port = args.port or 9015
        helper.run_http_server(port, mode="stt")
    elif args.tts_server:
        port = args.port or 9016
        helper.run_http_server(port, mode="tts")
    else:
        helper.run()
