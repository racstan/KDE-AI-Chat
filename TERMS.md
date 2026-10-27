# Terms of use

KDE AI Chat is a free desktop widget that connects you to AI services you choose. By using it you agree to these terms. They sit next to the software license in [LICENSE](LICENSE); where the two differ, the license decides what you may do with the code, and these terms describe how you use the widget.

## The software is provided as it is

KDE AI Chat comes with **no warranty**. It may have bugs, stop working with a service, lose a chat or behave in ways you don't expect. Keep your own copies of anything important. The developer is not liable for any damage, loss or cost that comes from using it, as far as the law allows.

## You choose where your messages go

The widget itself collects nothing: it has no analytics, no telemetry and no account. It only sends data where your settings send it:

- **AI providers** (OpenAI, Anthropic, Google, OpenRouter, NVIDIA and the others, or a server you add): your messages, attached files, pictures, memories that are included in a request and your instructions go to the provider you picked for that chat. That provider's own terms and privacy policy apply to what you send it.
- **Local servers** (Ollama, LM Studio, llama.cpp, LiteLLM and similar on your own computer): requests stay on your computer, unless that server forwards them elsewhere.
- **OpenCode and Pi modes**: the agent program you installed runs on your computer, can read and change files in the chat's folder and can run commands there, within the permissions you grant it. It sends your requests to the provider it is set up with.
- **Picture services** (Pollinations, AI Horde): your picture descriptions go to that service and are handled under its terms. Some of them publish or share generated pictures.
- **Speech Note** (for dictation and read aloud) is a separate app by another developer, with its own license. It runs on your computer; what it does with audio is described in its own documentation.

The widget shows which service a chat uses. Before you send anything private, check that you're comfortable with that service seeing it.

## Your keys, your costs

- API keys you enter are kept in KDE Wallet on your computer and are only sent to the service they belong to.
- **You are responsible for every cost** on your provider accounts: messages, long chats, attached files, picture generation and **scheduled prompts, which run by themselves** at the times you set, even while you're away.
- Keep your keys private. If you think one has leaked, revoke it at the provider.

## Your use

- Follow the terms, usage policies and limits of every service you connect, and the law where you live.
- Don't use the widget to break or get around a service's limits, rate limits or safety measures.
- AI answers can be wrong, out of date or made up. Check anything important, especially medical, legal, financial or safety-related advice, and code before you run it.
- You are responsible for what you ask the AI to do, for what you send to it, and for how you use its answers, including commands or file changes an agent makes in OpenCode or Pi mode with your permission.

## Changes

These terms may change with new versions of the widget. The version that came with your copy applies to it; the [changelog](changelog.md) notes when they change.

## Contact

Questions or problems: open an issue on the project's GitHub page, <https://github.com/racstan/KDE-AI-Chat/issues>.
