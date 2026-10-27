# KDE AI Chat

[![KDE Store](https://img.shields.io/badge/KDE%20Store-Download-blue?style=for-the-badge&logo=kde)](https://store.kde.org/p/2360152/) [![GitHub Release](https://img.shields.io/github/v/release/racstan/KDE-AI-Chat?style=for-the-badge&color=success)](https://github.com/racstan/KDE-AI-Chat/releases)

A chat assistant that lives on your **KDE Plasma 6** desktop. Talk to the AI service of your choice, or to a model running on your own computer. Drop in files, keep your chats in projects, schedule messages, and let the AI help with code. Your API keys are kept in KDE Wallet, and your chats stay in private files on your computer.

![A conversation in KDE AI Chat](docs/media/chat-conversation-light.png)

[Watch the demo (video)](docs/media/demo.webm)

---

## What it does

- **Many AI providers.** OpenAI, Anthropic, Google Gemini, OpenRouter, Groq, Mistral and more, plus local programs such as Ollama and LM Studio. It can find local servers for you. See [Providers](docs/providers.md).
- **Three ways to chat.** Directly to a provider, through the OpenCode coding agent, or through the Pi coding agent. See [Modes](docs/modes.md).
- **Chats that stay organised.** History, search across all chats, projects, incognito chats, quotes, edit and rewind, slash commands, export. See [Chats](docs/chats.md).
- **Memory and personality.** Tell the AI who you are and what to remember. See [Memory and personality](docs/memory-and-personality.md).
- **Scheduled messages.** Send a message into a chat at set times, even when the widget is closed. See [Schedules](docs/schedules.md).
- **Pictures.** Make pictures with `/image` through AI Horde or Pollinations, and see pictures that models send back. See [Pictures](docs/pictures.md).
- **Voice.** Dictate instead of typing and have replies read aloud. Both are off until you switch them on. See [Voice](docs/voice.md).
- **Desktop integration.** Ask from KRunner, from Dolphin, or about selected text in any app. See [Desktop integration](docs/desktop-integration.md).
- **Your look.** Text size, bubbles, accent colour, an icon or animation in the panel, avatars. See [Customising](docs/customising.md).
- **Private by design.** See [Privacy](docs/privacy.md) for what is stored where and what is sent where.

---

## Installation

### Option 1: From the desktop (recommended)
1. Right-click the desktop or a panel and choose **Add Widgets...**
2. Click **Get New Widgets** and then **Download New Plasma Widgets...**
3. Search for **KDE AI Chat** and click **Install**.

### Option 2: Download the file
1. Get the `.plasmoid` file from the [KDE Store](https://store.kde.org/p/2360152/) or the [GitHub releases](https://github.com/racstan/KDE-AI-Chat/releases).
2. Install it in a terminal:
   ```bash
   kpackagetool6 -i /path/to/downloaded-package.plasmoid
   ```

### Option 3: From the source code
```bash
git clone https://github.com/racstan/KDE-AI-Chat.git
cd KDE-AI-Chat
./install.sh
systemctl --user restart plasma-plasmashell.service
```
Then right-click the desktop or a panel, choose **Add Widgets...** and add **KDE AI Chat**.

The first time you open the chat, a short setup card helps you choose where your AI runs. More in [Getting started](docs/getting-started.md).

---

## System dependencies

The widget works out of the box. Some features need a small tool; if one is missing, the widget tells you what to install, and **Settings → Connection → Check setup** lists it too.

| Feature | Tool needed | Debian/Ubuntu | Arch Linux | Fedora |
| :--- | :--- | :--- | :--- | :--- |
| **Reading PDFs** | `pdftotext` | `sudo apt install poppler-utils` | `sudo pacman -S poppler` | `sudo dnf install poppler-utils` |
| **Reading Word documents** | `pandoc` | `sudo apt install pandoc` | `sudo pacman -S pandoc-cli` | `sudo dnf install pandoc` |
| **Secure key storage** | `qdbus6` / `qdbus` | *Pre-installed* | *Pre-installed* | *Pre-installed* |
| **Voice (optional)** | Speech Note (Flatpak [net.mkiol.SpeechNote](https://flathub.org/apps/net.mkiol.SpeechNote)) | see [Voice](docs/voice.md) | see [Voice](docs/voice.md) | see [Voice](docs/voice.md) |
| **Coding agents (optional)** | `opencode` or `pi` | see [Modes](docs/modes.md) | see [Modes](docs/modes.md) | see [Modes](docs/modes.md) |

---

## Documentation

- [Getting started](docs/getting-started.md): your first chat in a few minutes
- [Providers](docs/providers.md): AI services, local servers, custom providers and API keys
- [Modes](docs/modes.md): direct, OpenCode and Pi
- [Chats](docs/chats.md): history, search, projects, incognito, commands and more
- [Memory and personality](docs/memory-and-personality.md)
- [Schedules](docs/schedules.md)
- [Pictures](docs/pictures.md)
- [Voice](docs/voice.md)
- [Desktop integration](docs/desktop-integration.md)
- [Customising](docs/customising.md)
- [Privacy](docs/privacy.md)
- [Troubleshooting](docs/troubleshooting.md)
- [FAQ](docs/faq.md)
- [Translating](docs/translating.md)
- [Development](docs/development.md)
- [API key pages for each provider](SETUP.md)
- [Changelog](changelog.md)

---

## Known Problems

- **Many keyboard shortcuts can't be changed yet.** The only one you can change is the shortcut that opens the widget; the others are fixed for now. Making them customisable is planned for a future release.
- **Other languages haven't been tested.** The widget comes with translations, but they haven't been checked by people who speak those languages. Testing them is planned for future releases, and testers are welcome to help.

---

## License

Copyright (C) 2026 Rachit Asthana

KDE AI Chat is licensed under the [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0): you may use, change and share it for any noncommercial purpose (personal use, study, research, hobby projects, and use by charities, schools and public bodies). Commercial use needs the author's permission. It comes without any warranty. See [LICENSE](LICENSE) for the full text, [TERMS.md](TERMS.md) for the terms of use and [SECURITY.md](SECURITY.md) for reporting security problems. Versions up to 1.3.1 were released under the GNU GPL v3.0 or later and stay available under that license.

Using the widget also means accepting the [terms of use](TERMS.md): no warranty, your messages go only to the services you choose, and you are responsible for your keys, your costs and how you use the answers.

---

## Credits

- Voice (dictation and read aloud) is powered by [Speech Note](https://github.com/mkiol/dsnote) by Michał Kosciesza.
