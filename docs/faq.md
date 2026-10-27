# FAQ

### Where are my API keys saved?
Only in KDE Wallet (KWallet), in the **KDEAIChat** folder. You can see them in KDE Wallet Manager. Nothing is stored in plain text. See [Privacy](privacy.md).

### Do I need an API key for Ollama or LM Studio?
No. Programs on your own computer usually need no key. A server such as a LiteLLM proxy may ask for one; the widget says so. See [Providers](providers.md).

### Can I switch a chat from Direct to OpenCode or Pi?
No. A chat keeps the mode it was started in. Changing the mode in Settings only affects new chats. Start a new chat to use another mode. See [Modes](modes.md).

### My AI service is not in the list.
Choose **Other OpenAI-compatible** and enter its address and key. Or use the OpenCode agent, which has its own list of providers; see [Modes](modes.md).

### Why does the widget say it is "Thinking" for a long time with OpenCode?
Check that the OpenCode server is running: Settings → Connection, under OpenCode, press **Check** (or **Start**). **Check setup** can also tell you.

### How do I export a chat?
Choose **Export chat...** from the More menu in the chat header and pick Markdown, plain text or JSON. See [Chats](chats.md#export).

### How do I get a chat out of the history without deleting it?
Archive it. Archived chats are under **Archived** in the history, and you can restore them.

### Is anything sent when I use KRunner, Dolphin or the selected-text shortcut?
Only a KRunner question without files is sent at once. With files or selected text, the question waits in the message box until you press Send. See [Desktop integration](desktop-integration.md).

### Can the AI see my files?
Only the files you attach. In OpenCode and Pi modes, the agent can read and change files in the chat's folder, and asks you for permission before it changes things.

### Why are the translations not perfect?
They were made by machine and have not been checked by people who speak those languages. You can help: see [Translating](translating.md).

### Is it free?
Yes, for noncommercial use (see the License in the [README](../README.md#license)). You pay your AI provider for what you use; local programs cost nothing. If it helps you, there is a **Buy Me a Coffee** button in Settings → Support.

### How do I report a bug or suggest something?
Open an issue at <https://github.com/racstan/KDE-AI-Chat/issues>. For a security problem, please report it privately: see [SECURITY.md](../SECURITY.md).
