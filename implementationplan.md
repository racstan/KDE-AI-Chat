# STT/TTS Integration Implementation Plan

## Overview

Add Speech-to-Text (STT) and Text-to-Speech (TTS) to the KDE AI Chat widget as an **experimental, toggleable feature**. When enabled, the user gets a mic button beside the send button for voice input, and AI responses are read aloud.

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    QML (FullRepresentation.qml)             │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────────┐  │
│  │ Mic Btn  │  │ Send Btn │  │  Chat Messages View      │  │
│  │ (toggle) │  │          │  │  (auto-read responses)   │  │
│  └────┬─────┘  └────┬─────┘  └─────────┬────────────────┘  │
│       │              │                   │                   │
│       ▼              ▼                   ▼                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              DataSource (voiceDs)                     │   │
│  │         Communicates with voice_helper.py             │   │
│  └──────────────────────────┬───────────────────────────┘   │
│                             │                                │
└─────────────────────────────┼────────────────────────────────┘
                              │ stdin/stdout (JSON protocol)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   voice_helper.py                            │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ STT Thread  │  │ TTS Thread  │  │ Model Manager       │ │
│  │ (faster-    │  │ (kokoro +   │  │ (download, check,   │ │
│  │  whisper)   │  │  paplay)    │  │  list models)       │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Audio Capture (sounddevice)              │   │
│  │              16kHz, mono, float32                     │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Why Separate `voice_helper.py`?

- `kde_ai_helper.py` uses only stdlib (no pip dependencies)
- STT/TTS require heavy third-party libs (faster-whisper, kokoro, sounddevice, numpy)
- Separate script = separate venv = no conflicts
- Same QProcess/DataSource pattern as existing helper
- Can be enabled/disabled independently

### Communication Protocol

Voice helper reads commands from stdin (line-byline) and writes JSON responses to stdout:

**Commands (QML → Python):**
```json
{"cmd": "check_env"}
{"cmd": "list_models"}
{"cmd": "download_stt", "model": "large-v3-turbo"}
{"cmd": "download_tts", "model": "kokoro-82m"}
{"cmd": "start_stt", "lang": "en"}
{"cmd": "stop_stt"}
{"cmd": "tts", "text": "Hello world", "voice": "af_heart"}
{"cmd": "stop_tts"}
{"cmd": "set_stt_model", "path": "/path/to/model"}
{"cmd": "set_tts_model", "path": "/path/to/model"}
```

**Responses (Python → QML):**
```json
{"type": "env_check", "stt_ready": true, "tts_ready": false, "mic_available": true, "paplay_available": true, "espeak_available": true}
{"type": "models_list", "stt": [{"name": "large-v3-turbo", "downloaded": true, "size": "3.1GB"}], "tts": [{"name": "kokoro-82m", "downloaded": true, "size": "150MB"}]}
{"type": "download_progress", "target": "stt", "model": "large-v3-turbo", "pct": 45, "bytes": 1400000000, "total": 3100000000}
{"type": "download_done", "target": "stt", "model": "large-v3-turbo"}
{"type": "download_error", "target": "stt", "error": "Network timeout"}
{"type": "stt_partial", "text": "hello how are"}
{"type": "stt_result", "text": "hello how are you today"}
{"type": "stt_error", "error": "No microphone detected"}
{"type": "stt_stopped"}
{"type": "tts_started", "text": "Hello world"}
{"type": "tts_done"}
{"type": "tts_error", "error": "espeak-ng not found"}
{"type": "tts_stopped"}
```

---

## Default Models

| Component | Default Model | Source | Size | Notes |
|-----------|--------------|--------|------|-------|
| STT | `large-v3-turbo` | `Systran/faster-whisper-large-v3-turbo` | ~1.5 GB (INT8) | Best quality/speed ratio |
| TTS | `kokoro-82m` | `hexgrad/Kokoro-82M` | ~150 MB | Apache-2.0, 24kHz output |

Users can override with custom model paths in settings.

---

## File Changes Required

### 1. New Files

#### `contents/ui/voice_helper.py`
The main voice processing script. Runs as a long-lived process via QProcess.

**Key classes:**
- `VoiceHelper` - Main class managing STT/TTS lifecycle
- `STTEngine` - Faster Whisper wrapper (model loading, transcription)
- `TTSEngine` - Kokoro wrapper (synthesis, playback)
- `ModelManager` - Download/check models via huggingface_hub
- `AudioCapture` - sounddevice microphone wrapper

**Threading model:**
```
Main Thread: Reads stdin commands, dispatches to worker threads
  ├── STT Record Thread: Continuously records 3-sec audio chunks → queue
  ├── STT Transcribe Thread: Takes chunks from queue → transcribes → prints results
  └── TTS Thread: Synthesizes text → plays audio via paplay
```

#### `contents/ui/voice_setup.sh`
One-time setup script that creates the venv and installs dependencies:
```bash
#!/bin/bash
VENV_DIR="$HOME/.local/share/kdeaichat/venv"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install faster-whisper kokoro sounddevice numpy soundfile huggingface_hub
```

### 2. Modified Files

#### `contents/ui/main.qml`
- Add `voiceDs` DataSource for voice_helper communication
- Add `voiceEnabled`, `voiceRecording`, `voiceTtsEnabled` properties
- Add `onVoiceDsNewData` handler to parse JSON responses
- Wire voice events to FullRepresentation

#### `contents/ui/FullRepresentation.qml`
- Add mic button next to send button (toggle on/off)
- Add voice mode indicator (recording animation)
- Auto-send transcribed text when STT result arrives
- Auto-trigger TTS when AI response arrives (if voice enabled)
- Add stop TTS button when audio is playing

#### `contents/ui/MainDatabase.js`
- Add `handleVoiceResult(text)` function
- Add `triggerTtsForResponse(text)` function
- Add `startVoiceMode()` / `stopVoiceMode()` functions
- Modify `sendMessageByIndex` to support voice mode

#### `contents/ui/ConfigAdvancedSection.qml`
- Add "Voice & Audio" section (new settings group)
- Toggle: Enable voice features
- Toggle: Enable TTS for AI responses
- STT model selector (dropdown + custom path field)
- TTS model selector (dropdown + custom path field)
- Download buttons for STT/TTS models
- Model status indicators (downloaded/not downloaded/size)
- Audio device selector (microphone dropdown)
- Test buttons (test STT, test TTS)

#### `contents/config/main.xml`
```xml
<!-- Voice & Audio Settings -->
<entry name="voiceEnabled" type="Bool">
  <default>false</default>
</entry>
<entry name="voiceTtsEnabled" type="Bool">
  <default>false</default>
</entry>
<entry name="voiceSttModel" type="String">
  <default>large-v3-turbo</default>
</entry>
<entry name="voiceTtsModel" type="String">
  <default>kokoro-82m</default>
</entry>
<entry name="voiceSttModelPath" type="String">
  <default></default>
</entry>
<entry name="voiceTtsModelPath" type="String">
  <default></default>
</entry>
<entry name="voiceLanguage" type="String">
  <default>en</default>
</entry>
<entry name="voiceTtsVoice" type="String">
  <default>af_heart</default>
</entry>
<entry name="voiceAutoSend" type="Bool">
  <default>true</default>
</entry>
<entry name="voiceVenvPath" type="String">
  <default>~/.local/share/kdeaichat/venv</default>
</entry>
```

---

## Implementation Phases

### Phase 1: Foundation (voice_helper.py + setup)
- Create `voice_helper.py` with stdin/stdout JSON protocol
- Implement `check_env` command (detect mic, paplay, espeak-ng, venv)
- Implement `list_models` command (check downloaded models)
- Implement `download_stt` / `download_tts` commands with progress
- Create `voice_setup.sh` for venv creation
- Test standalone (run voice_helper.py directly)

### Phase 2: STT Integration
- Implement `AudioCapture` class (sounddevice, 16kHz)
- Implement `STTEngine` class (faster-whisper model loading)
- Implement `start_stt` / `stop_stt` commands
- Implement chunked recording + transcription in threads
- Add `stt_partial` and `stt_result` responses
- Add QML side: mic button, voice mode toggle
- Wire STT results to chat input

### Phase 3: TTS Integration
- Implement `TTSEngine` class (kokoro synthesis)
- Implement `tts` / `stop_tts` commands
- Implement non-blocking playback via paplay
- Add QML side: auto-read AI responses
- Add stop TTS button
- Handle TTS errors gracefully

### Phase 4: Settings UI
- Add "Voice & Audio" section to ConfigAdvancedSection.qml
- Add model selectors with download buttons
- Add audio device selector
- Add test buttons
- Add progress indicators
- Add language/voice selection

### Phase 5: Polish & Error Handling
- Graceful fallbacks for all error conditions
- Pre-flight checks before starting STT/TTS
- Clear error messages in UI
- Model size display and disk space check
- Cancel download support
- Memory management (unload models when not in use)

---

## Graceful Error Handling

### Pre-flight Checks (on voice mode toggle)

```python
def check_voice_ready(self):
    """Check all prerequisites before starting voice mode."""
    errors = []
    
    # 1. Check microphone
    try:
        import sounddevice as sd
        devices = sd.query_devices()
        input_devices = [d for d in devices if d['max_input_channels'] > 0]
        if not input_devices:
            errors.append("No microphone detected")
    except Exception:
        errors.append("sounddevice not available")
    
    # 2. Check STT model
    if not self.stt_model_loaded:
        errors.append("STT model not downloaded")
    
    # 3. Check audio playback
    if not shutil.which('paplay') and not shutil.which('aplay'):
        errors.append("No audio player (install pulseaudio-utils or alsa-utils)")
    
    # 4. Check TTS (if enabled)
    if self.tts_enabled:
        if not shutil.which('espeak-ng'):
            errors.append("espeak-ng not installed (required for Kokoro TTS)")
        if not self.tts_model_loaded:
            errors.append("TTS model not downloaded")
    
    return errors
```

### Error Recovery Patterns

| Error | Recovery |
|-------|----------|
| Microphone disconnected mid-session | Auto-stop STT, show "Mic disconnected" message |
| Model loading fails (OOM) | Suggest smaller model, offer to switch |
| TTS playback fails | Skip TTS for this message, continue chat |
| Network fails during download | Pause download, offer retry |
| voice_helper.py crashes | QProcess exit signal → auto-restart or show error |
| espeak-ng missing | Show install instructions, disable TTS |
| No audio output device | Disable TTS, continue with text-only |

### State Machine

```
Voice Mode States:
  IDLE → (mic click) → CHECKING → RECORDING → (mic click) → PROCESSING → IDLE
                                    ↓
                               (auto) TRANSCRIBING → (result) → IDLE
                                    ↓
                               (error) ERROR → (retry) → IDLE

TTS States:
  IDLE → (ai response) → SYNTHESIZING → PLAYING → (done) → IDLE
                              ↓
                         (error) ERROR → (skip) → IDLE
```

---

## UI Design

### Mic Button (FullRepresentation.qml)

```qml
// Next to send button in input area
QQC2.ToolButton {
    id: micButton
    visible: plasmoid.configuration.voiceEnabled
    icon.name: root.voiceRecording ? "microphone-sensitivity-high" : "microphone-symbols"
    enabled: root.voiceReady
    onClicked: root.toggleVoiceMode()
    QQC2.ToolTip.text: root.voiceRecording ? "Stop listening" : "Start voice input"
    
    // Pulsing animation when recording
    SequentialAnimation on opacity {
        running: root.voiceRecording
        loops: Animation.Infinite
        NumberAnimation { to: 0.5; duration: 500 }
        NumberAnimation { to: 1.0; duration: 500 }
    }
}
```

### Voice Mode Indicator

```qml
// Small indicator above input area when voice mode is active
Rectangle {
    visible: root.voiceRecording
    color: Kirigami.Theme.negativeTextColor
    radius: 4
    RowLayout {
        Kirigami.Icon { source: "microphone-sensitivity-high" }
        Label { text: "Listening..." }
        QQC2.Button { text: "Stop"; onClicked: root.stopVoiceMode() }
    }
}
```

### TTS Indicator

```qml
// Small speaker icon when TTS is playing
QQC2.ToolButton {
    id: stopTtsButton
    visible: root.ttsPlaying
    icon.name: "audio-volume-high"
    onClicked: voiceHelperDs.connectSource('{"cmd": "stop_tts"}')
    QQC2.ToolTip.text: "Stop reading aloud"
}
```

### Settings Panel (ConfigAdvancedSection.qml)

```
┌─ Voice & Audio ──────────────────────────────────────────┐
│                                                           │
│  ☐ Enable voice features (experimental)                  │
│                                                           │
│  ┌─ Speech-to-Text (STT) ─────────────────────────────┐  │
│  │  Model: [large-v3-turbo ▼]                         │  │
│  │  Custom path: [/path/to/model           ] [Browse]  │  │
│  │  Status: ✓ Downloaded (1.5 GB)                     │  │
│  │  [Download Model]  [Delete Model]                   │  │
│  │  Language: [en ▼]                                   │  │
│  │  [Test STT]                                         │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─ Text-to-Speech (TTS) ─────────────────────────────┐  │
│  │  ☐ Read AI responses aloud                         │  │
│  │  Model: [kokoro-82m ▼]                             │  │
│  │  Custom path: [/path/to/model           ] [Browse]  │  │
│  │  Status: ✓ Downloaded (150 MB)                     │  │
│  │  [Download Model]  [Delete Model]                   │  │
│  │  Voice: [af_heart ▼]                                │  │
│  │  [Test TTS]                                         │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─ Audio Device ─────────────────────────────────────┐  │
│  │  Microphone: [Default ▼]                           │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ☐ Auto-send transcribed text                            │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

---

## Dependencies

### System Packages (user must install)
```bash
# Required for TTS playback
sudo apt install pulseaudio-utils   # paplay
# OR
sudo apt install alsa-utils         # aplay

# Required for Kokoro TTS
sudo apt install espeak-ng

# Required for sounddevice
sudo apt install libportaudio2
```

### Python Packages (installed via venv)
```
faster-whisper>=1.0.0
kokoro>=0.1.0
sounddevice>=0.4.0
numpy>=1.24.0
soundfile>=0.12.0
huggingface_hub>=0.20.0
```

### Disk Space Requirements
| Component | Size |
|-----------|------|
| Python venv + packages | ~500 MB |
| STT model (large-v3-turbo) | ~1.5 GB |
| TTS model (kokoro-82m) | ~150 MB |
| **Total** | **~2.15 GB** |

---

## Testing Plan

### Unit Tests
- voice_helper.py standalone: test each command via stdin
- Test `check_env` returns correct device availability
- Test `list_models` returns correct model status
- Test STT with sample audio file (not just mic)
- Test TTS with short text strings

### Integration Tests
- Test QML → voice_helper.py → QML round-trip
- Test mic button toggle (start/stop recording)
- Test auto-send transcribed text
- Test auto-read AI response
- Test error handling (no mic, no model, etc.)

### Manual Tests
- Test with real microphone in noisy environment
- Test with different languages
- Test model download progress UI
- Test cancel download
- Test switching between STT models
- Test switching between TTS voices
- Test voice mode during long AI response
- Test TTS while user is typing
- Test multiple rapid start/stop cycles

---

## Known Limitations

1. **No streaming STT**: Faster Whisper processes chunks (3-5 sec latency)
2. **CPU-only by default**: GPU support requires CUDA/ROCm setup
3. **English-optimized TTS**: Kokoro supports other languages but English is best
4. **No wake word**: User must click mic button (no "Hey KDE" activation)
5. **Large model size**: ~2 GB disk space for default models
6. **No voice cloning**: Uses pre-built voices only
7. **PulseAudio dependency**: TTS playback requires paplay (or aplay fallback)

---

## Future Enhancements (Out of Scope)

- [ ] Streaming STT with lower latency (whisper_streaming / SimulStreaming)
- [ ] GPU acceleration (CUDA/ROCm)
- [ ] Wake word detection ("Hey KDE")
- [ ] Voice cloning
- [ ] Multiple TTS voices per response (roleplay)
- [ ] Audio visualization (waveform during recording)
- [ ] Whisper.cpp backend (lighter weight)
- [ ] Vosk backend (even lighter weight)
- [ ] TTS speed/pitch controls
- [ ] STT sensitivity controls (VAD threshold)
