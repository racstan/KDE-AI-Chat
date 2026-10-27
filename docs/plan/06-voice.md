# Phase 6: Voice (speech-to-text and text-to-speech)

**Goal:** the user chooses their own speech engines and models for both reading aloud and dictation. A good default works with zero setup, and nothing uses RAM while you're not talking.

**Owner requirement (2026-10-24):** STT and TTS must be the user's choice. Today the code is effectively hard-wired to one model (Whisper "small" on CPU for STT, Kokoro voice `"a"` for TTS).

Paths are relative to `org.kde.plasma.kdeaichat/contents/ui/`.

## Audit findings

**Setup (`voice/venv_setup.sh`):**
- Installs **torch, spacy, transformers**, faster-whisper, piper-tts, kokoro and misaki (:129-167), several GB.
- GPU is a manual toggle, not detected. `VoiceManager.runSetup` never passes the mode, so it always installs the CPU build anyway (`VoiceManager.qml:370-376`).
- Models download from HuggingFace on first use, with no size shown. This is the setup pain in issues #4 and #5.

**Services:**
- Two always-on systemd services (`Restart=always`, enabled at login; `kde_ai_helper.py:533-563`) on loopback ports 9015/9016, with token auth.
- **The STT service imports torch and preloads a Whisper model at startup** (`voice/voice_helper.py:1480-1520`). The TTS pipeline stays loaded after first use. **Nothing ever unloads.**
- While active, the widget polls `/status` every 300 ms (`VoiceManager.qml:73`).

**Broken:**
- **Model and GPU settings are ignored at startup.** The preload reads them from `~/.config/kdeaichatrc`, which nothing writes anymore (`voice_helper.py:1462-1478`), so it always loads "small" on CPU.
- **Changing voice, path or GPU needs a service restart**, because the Kokoro pipeline is cached once (:921).
- **torch is imported just to check for CUDA**, even for espeak (:426, :671-675).
- **Playback can be marked finished while still playing** (`VoiceManager.qml:136-142`), a status race.
- **The fallback stop never matches** (`pkill "paplay.*kdeaichat"`; temp files have no such name).
- **TTS language is hard-coded** to `"a"` (`VoiceManager.qml:399`).

**Available on the system:**
- **`QtTextToSpeech`** (Qt's QML module) is installed, with Speech Dispatcher, Flite and **Kokoro** back ends. It speaks in-process with stop and pause, and needs no Python, venv or service.
- `spd-say` works too.
- `faster-whisper` needs only `ctranslate2` and `onnxruntime`, **not torch**. CUDA can be detected with `ctranslate2.get_cuda_device_count()`.

## Design: pluggable engines

Both directions use a small **engine interface**, so adding an engine doesn't touch the UI. Settings show one dropdown for the engine, then that engine's own options (model, voice, language, device). The dropdown is filled from what's actually installed or reachable.

### Text-to-speech engines

| Engine | Setup | Notes |
|---|---|---|
| **System voices (`QtTextToSpeech` → Speech Dispatcher)**, the default | none | In-process with stop and pause. Lists every voice Speech Dispatcher has (espeak-ng, RHVoice, Piper via speechd, …). |
| **Kokoro (`QtTextToSpeech` Kokoro plugin)** | installed on this system | Neural voices with no Python. Voice list from the plugin. |
| **Piper** (local binary + `.onnx` voice) | user points to a voice file, or downloads one with size shown | Fast and light. Many languages. |
| **Remote OpenAI-compatible `/audio/speech`** | URL + key (KWallet) + voice name | For users who already run a TTS server (e.g. Kokoro-FastAPI, openedai-speech) or use a cloud API. |
| **Custom command** | a command template, e.g. `my-tts --voice X` reading text on stdin and writing WAV | For people who want to wire their own. |

### Speech-to-text engines

| Engine | Setup | Notes |
|---|---|---|
| **Parakeet** (same on-demand service), the default since 2026-10-26 | one-click venv install (~24 MB: `transcribe-cpp` + `transcribe-cpp-native`, pinned) and the model, reused from disk (Handy's GGUF) or downloaded with size shown (731 MB) | NVIDIA Parakeet Unified EN 0.6B as Handy's Q8_0 GGUF, run by transcribe.cpp (ggml; no torch/NeMo). English only. GPU through Vulkan (any make), CPU fallback. Streaming is possible in transcribe.cpp (`Session.stream`) but not wired yet: the transcript arrives when you stop. |
| **faster-whisper** (on-demand local service) | one-click venv install, with size shown | Model size picked by the user (tiny … large-v3, distil, or any CTranslate2 model folder). CPU/CUDA auto-detected, overridable. Language auto or fixed. |
| **whisper.cpp** (`whisper-cli` / server) | user's own binary + `ggml` model | No Python at all. Good for AMD/Intel via Vulkan builds. |
| **Remote OpenAI-compatible `/audio/transcriptions`** | URL + key (KWallet) + model | Works with a local whisper server, Groq or OpenAI. |
| **Custom command** | command template that receives a WAV path and prints text | — |

### Shared rules

- **Reuse existing models.** Scan known folders: Speech Note `~/.cache/net.mkiol/dsnote/speech-models/`, the HuggingFace cache, `~/.local/share/piper`, whisper.cpp `models/`. Offer what's found before offering a download.
- **Downloads are explicit.** Show size and destination first. Honour `XDG_CACHE_HOME`/`XDG_DATA_HOME`. Each engine has a "remove its data" button.
- **On-demand services only.** The local faster-whisper service is socket-activated and exits after ~5 minutes idle. It doesn't import torch, loads the chosen model on first use, and reloads when settings change. It pushes events instead of being polled every 300 ms.
- **Per-chat voice override** (optional): a chat can have its own TTS voice, e.g. a different language.
- **Test buttons** for each engine ("Say hello", "Record 3 seconds"), so users can try a choice before saving.

## Steps

1. Engine interface (QML side for TTS, helper side for STT) and the settings UI with engine dropdowns, per-engine options and test buttons.
2. TTS engines: system voices and Kokoro via `QtTextToSpeech`, then Piper, remote and custom command. Remove the old TTS service and its hard-coded `lang_code: "a"`.
3. STT engines: rewrite the faster-whisper service (socket activation, idle exit, lazy model, no torch), then whisper.cpp, remote and custom command. Settings move from `kdeaichatrc` into normal config.
4. Model discovery and download flow (size preview, reuse existing, remove data).
5. Remove the process memory panel and kill buttons, the venv/espeak path settings and the separate GPU setup path (cut list).

## Tests

- pytest: STT service with a fake model (socket activation via a passed fd, idle exit, auth, model reload on settings change); setup size calculation; model discovery against fixture directories.
- Offscreen QML: TTS controls with Qt's `mock` TTS engine (installed: `libqtexttospeech_mock.so`); engine dropdown shows only available engines; per-engine options persist.
- pytest: each STT engine adapter with a fake binary/server (whisper.cpp, remote, custom command).
- Manual: dictate a sentence on CPU; check `systemctl --user status` shows the STT service gone after the idle timeout; read aloud a long answer with pause/stop.

## Done when

- A user can pick any listed TTS and STT engine and model from settings, test it, and use it.
- Read aloud works on a fresh install with no setup.
- With voice idle, no voice process is running.
- Setup never downloads anything without showing its size first.
