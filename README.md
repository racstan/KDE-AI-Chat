# Kai Chat — KDE Plasma 6 Widget

An AI chat widget for KDE Plasma 6 with:
- Collapsible chat history sidebar in the popup.
- Provider configuration only in right-click Configure.
- Multiple providers: OpenAI, Anthropic, Groq, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA, Hugging Face Router, xAI (Grok), and Local.
- Optional OpenCode priority mode.

---

## Quick Start

### Install

```bash
# Clone the repo
git clone https://github.com/your-repo/rachitkdeaichat
cd rachitkdeaichat

# Install (first time)
./install.sh

# Then restart plasmashell
systemctl --user restart plasma-plasmashell.service
```

### Add to panel

1. Right-click panel → **Add Widgets…**
2. Search for **Kai Chat**
3. Drag it to your panel

### Configure

Right-click the widget → **Configure Kai Chat…**

Provider-specific fields are shown only for the currently selected provider.

## KWallet Setup (Important)

Kai Chat defaults to wallet name `KaiChatWallet`.

If you want a fresh wallet password (`password`):

1. Open KDE Wallet Manager (`kwalletmanager5`) from app launcher.
2. Create a wallet named `KaiChatWallet`.
3. Set wallet password to `password`.
4. In widget Configure, keep Wallet name as `KaiChatWallet`.
5. Use **Save KWallet** / **Load** for provider keys.

Note: KDE wallet master password cannot be force-set non-interactively by this project script. KDE requires wallet creation/password via its wallet UI flow.

## About / Docs Page

- Local docs page: `docs/ABOUT.html`
- Intended website path: `https://example.com/kaichat/docs`

## Quick Troubleshooting Commands

```bash
# Show wallets
qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets

# Clean reinstall
./install.sh
systemctl --user restart plasma-plasmashell.service

# Lint UI files
qmllint org.kde.plasma.kaichat/contents/ui/main.qml
qmllint org.kde.plasma.kaichat/contents/ui/ConfigGeneral.qml
```

---

## Upgrade after changes

```bash
./install.sh
systemctl --user restart plasma-plasmashell.service
```

---

## File Structure

```
org.kde.plasma.kaichat/
├── metadata.json                 # Widget metadata (id, name, icon)
└── contents/
    ├── config/
    │   └── main.xml             # Configuration schema
    └── ui/
        ├── main.qml             # Chat UI + collapsible history sidebar
        └── ConfigGeneral.qml    # Provider and key settings
```

---

## Local model (Ollama) example

1. Install Ollama: https://ollama.com/
2. Pull a model: `ollama pull llama3.2`
3. Start Ollama: `ollama serve`
4. In widget settings set Base URL to: `http://localhost:11434/v1`
5. Set Model to: `llama3.2`
6. Leave API Key empty

---

## Requirements

- KDE Plasma 6
- Qt 6
- Network access for remote providers
- KWallet (for key save/load buttons)

## License

GPL-2.0+
