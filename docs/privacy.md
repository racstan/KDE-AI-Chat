# Privacy

The widget itself collects nothing: no analytics, no telemetry, no account. It sends data only where your settings send it. The [terms of use](../TERMS.md) say the same in legal words.

## Where things are stored

| What | Where |
| :--- | :--- |
| **API keys** | **KDE Wallet (KWallet) only**, in a folder called **KDEAIChat**, one entry per provider. Never in a settings file. |
| **Chats** | One file per chat in `~/.local/share/kdeaichat/chats/`, in a folder only you can read. Deleting a chat deletes its file and its pictures. |
| **Memories** | `~/.local/share/kdeaichat/memory.json`, private. |
| **Schedules** | `~/.local/share/kdeaichat/schedules.v2.json`, with a small record of each run. |
| **Pictures** | In the chat's own folder, next to the chat. |
| **Settings** | Plasma's normal widget settings. They hold no keys and no chat text. |

**Settings → Storage** shows the data folder (with an **Open folder** button) and what uses the space: chats, pictures, memories, schedules, temporary files and old voice engines. You can remove some of it there; it asks first.

If KWallet is off, locked or refuses access, the widget cannot read your keys and tells you why in the chat. Turn KWallet on in System Settings → KDE Wallet.

## What is sent where

- **Direct mode, online provider**: your messages, attached files, pictures, the memories that fit your message and your instructions go to the provider you chose for that chat. The provider's own privacy policy applies.
- **Direct mode, local server** (Ollama, LM Studio and so on): requests stay on your computer, unless that server forwards them elsewhere.
- **OpenCode and Pi**: the agent runs on your computer, can read and change files in the chat's folder within the permissions you give it, and sends your requests to the model it is set up with.
- **Picture services**: your prompt goes to the service (AI Horde: to a volunteer's computer). Never the rest of the chat. See [Pictures](pictures.md).
- **Voice**: with Speech Note, speech is handled on your computer. With a speech server, the recording or the text goes to that server.

The small badge in the status line by the message box always tells you where the chat's messages go, for example "OpenRouter · online", "Ollama · this computer" or "Ollama · your network".

## What the widget does to protect you

- **Keys** are only sent to the service they belong to. A key is never sent on to another site after a redirect, and never from a secure address to a plain `http` one.
- **Picture downloads** are limited to public secure addresses, and every redirect is checked again.
- **Private text stays off the command line.** Text that the widget hands to its helper programs goes through a private file in your runtime folder, so other users on the computer cannot read it in the process list.
- **Damaged chat files** are never overwritten (see [Chats](chats.md#when-a-chat-file-is-damaged)).
- **The ask inbox** refuses files in hidden folders or outside your home folder (see [Desktop integration](desktop-integration.md)).
- **Local server search** only looks at this computer and never sends a key.

## Incognito chats

An [incognito chat](chats.md#incognito-chats) is never written to disk, is not searchable, uses and saves no memories, and shows no text in notifications. Pictures in it are deleted when it closes. In OpenCode mode the agent keeps its own session while the chat is open and it is removed when the chat closes; in Pi mode Pi keeps no session file. The messages still go to the provider you chose.

## Upgrading from before 1.4.0

Older versions kept keys in plain text and all chats in Plasma's widget settings. On the first start, 1.4.0 moves them: keys go into KWallet (the plain copies are deleted only after KWallet has stored them), and chats go into their own files, with a backup of the old history kept as `legacy-chat-history-backup.ini`. A short notice above the chat tells you what was moved. If KWallet is not available, nothing is changed.

Questions about security: see [SECURITY.md](../SECURITY.md).
