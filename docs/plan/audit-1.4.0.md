# Audit of the released 1.4.0 (2026-10-29)

Three read-only reviews of the v1.4.0 package (security and privacy; correctness, robustness and performance; UX,
accessibility, translations and packaging), plus an install of the released `.plasmoid` from GitHub on the owner's
panel. Every item marked **verified** was checked again by the main session (code read, or a run).

The release installs and starts cleanly with `kpackagetool6 --upgrade` (no widget warnings in the journal), and starts
no process while idle (the 3-second shell poll of issue #4 is gone). Idle plasmashell CPU (~5 %) comes with an
always-playing animated panel icon; "Animate only while the pointer is on it" avoids it.

## Proposed for 1.4.1 (before the KDE Store upload)

| # | Sev. | What | Where | Status |
|---|---|---|---|---|
| S1 | high | A reply can make the widget fetch a web address by itself (privacy leak): four Markdown image forms slip past the filter (`'title'`, `<url with space>`, reference-style `![a][r]`, `(paren title)`) and Qt loads them. | chat/ImageExtract.js:142, chat/MessageBody.qml:57 | verified (node) |
| S2 | high/med | Tool names and details from OpenCode/Pi agents are shown in labels that read `<img src=…>` as rich text, so an agent can trigger the same fetch. | chat/ToolCard.qml:115,122, SenderName.qml:75 | verified (read) |
| S3 | med | The "Allow" button in a permission notification approves the whole command, but the notification shows it shortened to 240 characters with code removed. | chat/Notifier.qml:138 | reported, read |
| C1 | med | Edit, Retry or Regenerate while a message is queued starts the queued message and the new one; the first request keeps running (tokens; in OpenCode/Pi the agent keeps working). | chat/MessageEdits.qml:39,75,93 + SendController.qml:275 | verified (read) |
| U1 | med | Visible texts not translatable (drop overlay, attach dialog, several error messages), and plurals missing ("1 models"). | FullRepresentationContent.qml:86, chat/AttachDialog.qml:24-27, ReplyEvents.qml:161, … | verified (read) |
| U2 | low | metadata.json: description still says "OpenCode priority mode" (shown in Add Widgets and the store); `X-Plasma-ConfigurationUI` points at a file that no longer exists. | metadata.json | verified |
| S7 | low | Schedule id/time checks accept a trailing newline (broken timer file). | kdeaichat/schedule_model.py:19-23 | reported, run |
| S8 | low | Reply text goes into notifications as markup unescaped. | chat/Notifier.qml:107,113 | reported |
| S11 | low | "Input needed" notifications show the question/command text for incognito chats. | chat/Notifier.qml inputSpec | reported |
| S6 | low | No warning when a provider's address is plain `http://` to another computer (the key travels unencrypted). | ProvidersPanel.qml | reported |
| U3 | doc | Translations cover 217 of 1,421 texts; Known Problems should say "partly translated". | README.md | verified |

## Proposed for 1.5

- C2: attached files are saved inside the chat file and rewritten on every save (the owner's largest chat file is 4.3 MB). Store attachment bytes as files. (verified)
- C3: every chat is read and parsed 1 s after login; load messages when a chat is opened.
- S4: the OpenCode server the widget starts has no password (any local program can drive it).
- S5: other programs of the same user can auto-send into an agent-mode chat through the ask inbox / KRunner D-Bus.
- C4: starting the Pi bridge has no lock (two at once); its log never rotates.
- C5–C7, C10, S9: migration edge cases (old KaiChat wallet folder removed whole; one bad old memory blocks the memory migration; a malformed old schedules.json leaves schedules silently not running; a failed chat migration is never retried; keys cleared without a read-back).
- S10: some logs/state files created with the default umask.
- C8, C9, C12, C13, S12: small robustness and housekeeping items (see the reviews).
- Translations completed; "Reset this page" on every settings page; notification sound default.
