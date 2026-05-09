# Kai Chat — KDE Plasma 6 Widget

A powerful, native AI chat widget built exclusively for KDE Plasma 6. Designed by **Rachit Asthana** ([github.com/racstan](https://github.com/racstan)), Kai Chat integrates seamlessly into your desktop panel to provide instant access to the world's most capable language models.

---

## 🌟 Features

* **Multi-Provider Support:** First-class support for OpenAI, Anthropic, Groq, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA, Hugging Face, xAI (Grok), LM Studio, and Local endpoints.
* **Smart Model Discovery:** Automatically fetches and syncs available models directly from provider APIs when you enter your API key.
* **Auto-Complete Combobox:** Effortlessly search through hundreds of models (like OpenRouter's massive catalog) using the smart, non-blocking dropdown search.
* **Fluid UI & Resizability:** Features a built-in drag-to-resize handle natively integrated into the Plasma popup, remembering your preferred dimensions across reboots.
* **Advanced Chat History:** Conversations are automatically grouped by date (Today, Yesterday, etc.). You can archive, rename, and branch conversations simply by editing a previous message.
* **Secure Key Storage:** Fully integrates with KWallet to keep your API keys encrypted and safe from plain-text exposure.
* **Rich Messaging:** Full Markdown rendering, live Server-Sent Events (SSE) streaming for immediate token-by-token output, and easy one-click copy buttons for both queries and AI responses.
* **Transparent Debugging:** Extracts deep error metadata directly from provider API payloads, so you always know exactly why a request failed (e.g., rate limits, invalid IDs).

---

## 🚀 Installation & Walkthrough

### Prerequisites
* KDE Plasma 6
* Qt 6
* KDE Wallet (`kwalletmanager5`) for secure API key storage.

### 1. Installation
Clone the repository and run the installation script:
```bash
git clone https://github.com/racstan/rachitkdeaichat
cd rachitkdeaichat
./install.sh
```
Once installed, restart your Plasma shell to load the widget:
```bash
systemctl --user restart plasma-plasmashell.service
```

### 2. Add to Panel
1. Right-click your Plasma panel and select **Add Widgets…**
2. Search for **Kai Chat** and drag it to your panel or desktop.

### 3. Setup & KWallet
1. Right-click the Kai Chat widget icon and select **Configure Kai Chat…**
2. Select your preferred provider (e.g., OpenRouter).
3. Enter your API Key.
4. *(Optional but Recommended)* Click **Save to KWallet** to securely store your key in the `KaiChatWallet`.
5. The widget will automatically refresh the model list. Use the auto-complete dropdown to select your desired model.
6. Click **Apply** and start chatting!

---

## 🛠️ Local Model (Ollama/LM Studio) Setup

Kai Chat works perfectly with local inference servers:
1. Start your local server (e.g., `ollama serve` or LM Studio).
2. Open Kai Chat Settings and select **Local** as the provider.
3. Set the Base URL to your local endpoint (e.g., `http://localhost:11434/v1` for Ollama).
4. Type your model name manually in the dropdown (e.g., `llama3.2`).
5. Leave the API Key blank and apply.

---

## 🚧 Changelog

**v1.1.0**
* Added custom drag-to-resize handle at the bottom right of the popup.
* Fixed QtQuick ComboBox autofill interference when typing to search for models.
* Enhanced error parsing to expose deep JSON metadata from providers like OpenRouter and Anthropic.
* Added one-click copy buttons for user queries and AI responses.
* Implemented automatic model discovery triggers upon opening widget configurations.
* Refined chronological chat history headers with localized dates.
* Removed aggressive "Queued..." labeling that caused visual flickering.

**v1.0.0**
* Initial release for KDE Plasma 6.
* Support for major AI providers and Server-Sent Events streaming.
* History archiving, branching, and KWallet integration.

---

## ⚠️ Known Problems

* **Plasma 6 Popups:** Plasma manages popup geometry strictly. To bypass limitations, use the custom drag handle at the bottom right instead of attempting edge-dragging.
* **KWallet Initialization:** On first run, KWallet may prompt you repeatedly for permissions. You can configure KWalletManager to auto-allow Plasma widgets to avoid this.

---

## 🗺️ Roadmap

- [ ] **Image Generation:** Integrate DALL-E 3 and Stable Diffusion endpoints for rendering images inline.
- [ ] **Vision Models:** Allow users to drag and drop images into the chat box for multi-modal context.
- [ ] **System Prompt Templates:** Save and load custom system prompts based on specific tasks (e.g., "Coding Assistant", "Creative Writer").
- [ ] **Export Options:** Export full chat histories to Markdown or PDF.
- [ ] **Cloud Sync:** Sync chat history across multiple KDE Plasma devices using Nextcloud or KDE Connect.

---

## 📜 License

GPL-2.0+

Made with ❤️ by Rachit Asthana.
