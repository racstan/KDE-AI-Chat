# API key pages

Where to make an API key for each AI service, and how to give it to the widget. For the rest, see [Getting started](docs/getting-started.md) and [Providers](docs/providers.md).

## Give the widget your key

1. Right-click the widget and choose **Configure KDE AI Chat...**, then open **Connection**.
2. Choose **Add provider** and pick the service from the list. The address and the type are filled in.
3. Paste your key into **API key**, choose a **Model** (press **Refresh** to ask the provider) and press **Save**. The widget checks the key with the provider first.

The first time you open the chat, the setup card **Choose where your AI runs** does the same in fewer steps, and its **Get a key** link opens the page below for you.

Keys are kept in KDE Wallet only, in a folder called **KDEAIChat**, one entry per provider. KWallet must be on: System Settings → KDE Wallet. Details in [Privacy](docs/privacy.md).

## Where to make a key

| Service | Key page |
| :--- | :--- |
| OpenAI | https://platform.openai.com/api-keys |
| Anthropic | https://console.anthropic.com/settings/keys |
| Google Gemini | https://aistudio.google.com/apikey |
| OpenRouter | https://openrouter.ai/keys |
| Groq | https://console.groq.com/keys |
| DeepSeek | https://platform.deepseek.com/api_keys |
| Mistral | https://console.mistral.ai/api-keys |
| NVIDIA NIM | https://build.nvidia.com/settings/api-keys |
| Fireworks | https://fireworks.ai/account/api-keys |
| Hugging Face | https://huggingface.co/settings/tokens |
| xAI | https://console.x.ai/ |
| Cloudflare Workers AI | https://dash.cloudflare.com/ (create an API token under AI) |

Perplexity, MiniMax, Qwen and Moonshot are in the list too. Make the key on the service's own website, usually under "API keys".

## Notes for some services

- **Cloudflare Workers AI**: the address has `YOUR_ACCOUNT_ID` in it. Replace it with your own account ID from the Cloudflare dashboard.
- **Anthropic**: the only service that needs the **Anthropic** API type. It is set for you when you pick it from the list.
- **A service that is not in the list** (for example Cerebras, `https://api.cerebras.ai/v1`): choose **Other OpenAI-compatible** and enter its address and key.

## Programs on your own computer

Ollama, LM Studio, llama.cpp server and LiteLLM proxy need no key. Press **Find local servers** in Settings → Connection to add a running one, or pick it from **Add provider** and check the address.

| Program | Usual address |
| :--- | :--- |
| Ollama | `http://localhost:11434/v1` (start it with `ollama serve`) |
| LM Studio | `http://localhost:1234/v1` |
| llama.cpp server | `http://localhost:8080/v1` |
| LiteLLM proxy | `http://localhost:4000/v1` (a key is optional) |

## If KWallet gives trouble

- Open KDE Wallet Manager and look for the **KDEAIChat** folder. (Versions before 1.4.0 used a folder called `KaiChat`; it is moved automatically.)
- Make sure KWallet is on and unlocked. The widget says in the chat when it cannot read your keys.
- **Settings → Connection → Check setup** looks at KWallet and your providers and says what to fix.

More: [Troubleshooting](docs/troubleshooting.md).

## Support and license

Report problems at <https://github.com/racstan/KDE-AI-Chat/issues>. See [LICENSE](LICENSE).
