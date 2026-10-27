# KDE AI Chat Voice Setup

Dictation (talk instead of typing) and read aloud (the widget speaks replies) are both **off by default**. Turn them on in **Settings → Voice**.

The widget does not install or run speech models itself. All speech goes through a separate app:

## Speech Note (recommended)

[Speech Note](https://github.com/mkiol/dsnote) by Michał Kosciesza (MPL-2.0) does the listening and the speaking, in any language you download a model for, and uses your graphics card when it can (NVIDIA, AMD, Vulkan).

1. Install it: [Flathub: net.mkiol.SpeechNote](https://flathub.org/apps/net.mkiol.SpeechNote), or your distribution's package.
2. Open Speech Note once and download a **speech-to-text** model (for dictation) and a **voice** (for read aloud) in your language.
3. In the widget's **Settings → Voice**, switch on **Dictation** and/or **Read aloud**. Speech Note is the default engine; pick a model for each if you don't want Speech Note's own default.

Speech Note starts when you dictate or read and stops by itself when idle. The widget shows "Starting Speech Note…" while it is starting.

## Other engines

- **System voice** (read aloud only): Qt's text-to-speech with Speech Dispatcher (`speech-dispatcher` and, for a voice, `espeak-ng`). It reads replies whenever Speech Note is not installed. Nothing to set up, but it sounds robotic.
- **Speech server** (OpenAI-compatible): any server with `/audio/transcriptions` (dictation) or `/audio/speech` (read aloud): a Whisper or Kokoro server on your computer, Groq, OpenAI, and so on. Enter its address in Settings → Voice; its API key is kept in KWallet. For dictation with a server, the microphone is recorded with `pw-record` (PipeWire), `parecord` or `arecord`, and the recording is sent to the server.

## Coming from an earlier build

faster-whisper, whisper.cpp, Parakeet, Kokoro, Flite, Piper and the custom commands are gone. A saved choice of one of them becomes Speech Note (read aloud uses the system voice until Speech Note is installed), and their old background services are removed at the first start. Their Python environments and models stay on disk until you delete them in **Settings → Storage → Old voice engines** (it asks first and shows how much space it frees).
