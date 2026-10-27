# Security Policy

KDE AI Chat handles API keys, your chats and, in agent modes, programs that can read and change files. If you find a way to misuse any of that, please tell me privately first so it can be fixed before it is public.

## Supported versions

| Version | Security fixes |
|---|---|
| 1.4.x | Yes |
| 1.3.x and older | No: please update to the latest release |

## Reporting a vulnerability

- **Please don't open a public issue** for a security problem.
- Report it privately on GitHub: open the [Security tab](https://github.com/racstan/KDE-AI-Chat/security) of the project and choose **Report a vulnerability**.
- Say what you found, which version and which mode (direct, OpenCode, Pi), how to reproduce it, and what an attacker could do with it.
- **Never include a real API key**, password or private chat in a report. Use made-up values.

You can expect:

- an answer within **7 days** saying whether the problem is confirmed;
- a fix as soon as possible for confirmed problems, depending on how serious they are, with a note in the [changelog](changelog.md);
- credit for the report in the release notes, if you would like it.

Please give a reasonable time to release a fix before you share details publicly.

## What counts

Examples of what to report:

- an API key leaving KWallet in a way it shouldn't: written to a file, shown on a command line, sent to the wrong server, or followed through a redirect;
- a chat, memory or attached file being readable by other users of the computer, or sent somewhere the user didn't choose;
- a way for a web page, a model's reply, a file name or another program to run commands or change files without the user's say-so (through the helper, the ask inbox, KRunner, Dolphin, the Pi bridge, the OpenCode server or scheduled prompts);
- a crash or loss of chats that someone else can trigger on purpose.

Not security problems here (please open a normal issue instead):

- what a model says, or mistakes in its answers;
- problems in the AI services themselves, in OpenCode, Pi, Speech Note, KWallet or Plasma (please report those to their own projects);
- anything that needs an attacker who can already run programs as you, unless the widget makes the harm clearly worse.

## How the widget protects you

- API keys are kept only in KWallet (folder "KDEAIChat"), never in config files and never on a command line.
- Chats, memories and settings stay on your computer, in private folders (`~/.local/share/kdeaichat`).
- Messages go only to the providers and servers you choose. The widget itself collects nothing.
- Desktop integration (KRunner, Dolphin, the selected-text shortcut) is off until you turn it on, and requests with files never send themselves.

See [TERMS.md](TERMS.md) for the terms of use.
