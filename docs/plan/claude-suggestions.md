# 1.4.0 audit and suggestions (Claude)

Audit of the widget at the tip of `feat/gui-rebuild` (commit 35f85a1). Read-and-report only: no code was changed. `pytest -q` was run and passes (700 passed, 100 subtests, about 6 minutes). Everything below was checked by reading the code unless marked **unverified**; a few claims were also confirmed with small throw-away scripts (noted per finding).

## Summary

The widget is in good shape for a release: the mode rule ("a chat never switches mode") is enforced consistently, secrets stay out of config files and out of the command line on the paths that handle keys, the helper validates paths and file names carefully, and the image downloader, ask inbox and Pi bridge were clearly designed with privacy in mind. The real problems are in the places where the careful design stops: (1) the chat store can silently replace a chat, or the whole chat list, with an empty one if a file is damaged; (2) the OpenCode server the widget starts has no password, unlike the Pi bridge; (3) exporting a chat puts the whole conversation on the command line, which is both visible to other users of the computer and too long for large chats (the export then fails with no message); (4) a few network paths follow redirects while carrying an API key or fetching "images" from the local machine; and (5) file names with ordinary characters such as `(`, `)` or `&` cannot be attached. None of these is hard to fix; most are small. I found no critical (release-blocking, active-harm) issue, but A1 to A4 should be fixed before 1.4.0.

Counts: critical 0, high 4, medium 11, low 11 (26 findings), plus 12 new ideas.

## Most important findings

| Id | Sev | Area | One-line summary |
|---|---|---|---|
| A1 | high | Data loss | A damaged chat file is read as "empty" and then overwritten with the empty chat on the next save |
| A2 | high | Data loss | A damaged chat index makes the widget start with no chats and then overwrite the index; the "left untouched" guard only covers the old storage |
| A3 | high | Security | The OpenCode server started by the widget has no password; anything on this computer can use it |
| A4 | high | Privacy / bug | Exporting a chat puts the whole conversation on the command line; chats over about 90 KB fail silently |
| A5 | medium | Privacy | Memories and scheduled prompts also travel on the command line (readable by other local users for a moment) |
| A6 | medium | UX | Files named like `Report (final).pdf` or `Q&A.docx` are refused as "unsafe path" |
| A7 | medium | Security | The image downloader can be redirected to `http://127.0.0.1:...` (a request into the local machine) |
| A8 | medium | Security | API keys for read-aloud, dictation and scheduled runs are re-sent to wherever a server redirects; plain `http://` is accepted |
| A9 | medium | Security | Anything running as you can make the widget auto-send a question plus any file to your cloud provider |
| A10 | medium | UX | Dolphin "Ask KDE AI Chat" does nothing, with no message, when more than 10 files are selected |
| A11 | medium | Performance | Every save re-serialises every chat; start-up reads every chat file on the UI thread |
| A12 | medium | Bug | Messages longer than 2,000,000 characters are cut when loaded and the cut version is saved back |
| A13 | medium | UX / docs | The changelog describes three different "new default" voice engines in a row and is still headed "Unreleased" |
| A14 | medium | Data loss | A reply that is still streaming is not saved; if plasmashell crashes the partial reply is lost |
| A15 | medium | Desktop integration | KRunner and Dolphin files stay behind (pointing at a missing script) if the widget is removed with the switches on |

---

## Findings

### A1 - A damaged chat file is overwritten with an empty chat
- **Severity:** high. **Area:** data loss / chat store.
- **Where:** `org.kde.plasma.kdeaichat/contents/ui/store/ChatStore.qml:146-153` (read) and `:187` (write).
- **What is wrong:** If one chat's file cannot be parsed, the widget shows that chat as empty and remembers nothing about what was on disk, so the next save treats "empty" as a change and writes the empty chat over the damaged file.
- **Failure scenario:** A disk-full event or a crash during an unusual write leaves `chat-s-123.ini` with a half-written value. The user opens the widget, sees the chat is empty, types one message; the broken file (which might have been repairable by hand) is replaced by a one-message chat. Compare `kdeaichat/memory.py`, which has a test (`tests/test_memory_store.py:162`) that an unreadable file is never overwritten; chats have no such test.
- **Suggested fix:** On a parse failure, keep the original raw text in `_written` (so it is not seen as changed), copy the file to `chat-<id>.ini.damaged-<date>` once, mark the chat read-only or show the existing `sessionHistoryLoadError` banner, and do not write that chat until the user chooses. Add a QML test next to `tests/qml/tst_chat_store.qml`.
- **Effort:** S. **Risk of fix:** low.

### A2 - A damaged chat index starts the widget with no chats and overwrites the index
- **Severity:** high. **Area:** data loss / chat store.
- **Where:** `store/ChatStore.qml:136-140` (returns `null` when the index is not valid JSON), `chat/Sessions.qml:23-33` and `:230-232` (`null` is treated as "read the old config storage", which is empty after the 1.4.0 migration), then `Sessions.qml:78-79` (the "load blocked, do not save" guard).
- **What is wrong:** The protection "Stored chat history could not be parsed. It was left untouched." only triggers for the old config blob, not for the new files. A damaged `index.ini` therefore yields an empty list, a fresh chat is created, and the next save rewrites `index.ini` with only that chat. The old chat files stay on disk but are no longer listed (and nothing tells the user).
- **Failure scenario:** `index.ini` is truncated by a power cut. Next start: all chats seem gone; one message later the index is replaced, and recovery now needs manual detective work.
- **Suggested fix:** When `hasIndex()` is true but parsing fails, set `sessionHistoryLoadBlocked` (the existing mechanism), show the existing error text with a "Rebuild list from chat files" button that scans `chat-*.ini` files, and back up the damaged index first. Keep a rolling `index.ini.bak` written on each successful save.
- **Effort:** M. **Risk of fix:** low to medium (touches start-up).

### A3 - The OpenCode server the widget starts has no password
- **Severity:** high. **Area:** security / OpenCode mode.
- **Where:** `kdeaichat/opencode_server.py:68-75` (starts `opencode serve --hostname 127.0.0.1` with no password or token) and `:50-54` (any server answering `/global/health` on the port counts as "already-running").
- **What is wrong:** The Pi bridge (`pi_bridge_server.py:205-221`) requires a random token; the OpenCode server it is paired with does not. An OpenCode server can run commands and edit files, so any other program or user on the computer that connects to port 4096 can use it as you. An unrelated program that happens to listen on 4096 is also accepted as "OpenCode" and would receive your chat text.
- **Failure scenario:** On a shared computer (or with a hostile local process, or a web page that can reach loopback), someone sends a prompt to `127.0.0.1:4096` and the agent acts with your user rights.
- **Suggested fix:** Start the server with a random per-session password (OpenCode supports HTTP basic auth through its server-password setting; **unverified for the OpenCode version the user has**, check `opencode serve --help`), keep it in a 0600 state file or in memory, send it from `backends/OpenCodeBackend.js` and `schedule_opencode.py`, and refuse to use a server that was not started by the widget unless the user opted in (Settings: "Use an OpenCode server I started myself, with this password"). Tell the user in Check setup when the server is open.
- **Effort:** M. **Risk of fix:** medium (every OpenCode request path must send the credential; test with a stub server).

### A4 - Exporting a chat puts the whole chat on the command line, and large exports fail silently
- **Severity:** high. **Area:** privacy / bug.
- **Where:** `chat/HelperCommands.qml:26-48` (the chat text is base64-encoded into one argument of `sh -c ...`); the size checks are at `:32` (500,000 characters) and `:42` (900,000 encoded).
- **What is wrong:** Command-line arguments can be read by every user of the computer while the command runs, and Linux refuses any single argument over 128 KiB (131,072 bytes). The widget's own limit is about seven times higher, so exports of chats larger than roughly 90 KB of text fail inside the shell with "Argument list too long"; the success notification is chained with `&&`, so the user sees nothing at all. (I did not run the widget; the 128 KiB limit is the kernel's per-argument limit, `MAX_ARG_STRLEN`.)
- **Failure scenario:** The user exports a long research chat. No file is written and no message appears. A short export works but briefly exposes its content to other local users.
- **Suggested fix:** Add `export_chat` to `privateCommands` in `store/HelperRunner.qml:22` (the private runtime-file path used for read-aloud text, which has no size problem up to 1 MB) or write the file directly from QML with `Settings`/`XMLHttpRequest PUT`; raise the limit to the real maximum and show an error when the helper fails.
- **Effort:** S. **Risk of fix:** low.

### A5 - Memories, scheduled prompts and other private text also travel on the command line
- **Severity:** medium. **Area:** privacy.
- **Where:** `store/HelperRunner.qml:22` (only `tts_synthesize` and `speechnote_speak` use the private file) and `:60-61` (everything else goes in argv); callers include `store/MemoryStore.qml:42` (memory text), `config/ScheduleService.qml:80` (schedule prompts), `chat/ImageStore.qml:83`.
- **What is wrong:** The header comment says "never put secrets in it", and no key goes through here, but personal facts the user asked the AI to remember and scheduled prompts are private too. On a single-user desktop the risk is small; on a shared machine any user can read these while the helper runs (a few milliseconds to seconds).
- **Suggested fix:** Make `privateCommands` the default for every command except a short allow-list of tiny ones (`prepare_chat_dir`, status checks). The mechanism already exists and is tested.
- **Effort:** S. **Risk of fix:** low (one place; add a QML test that payload files are deleted).

### A6 - File names with ( ) & ; $ are refused
- **Severity:** medium. **Area:** UX / bug.
- **Where:** `Security.js:166` (`validateFilePath` rejects `$ ( ) \ ` ; & | < >`), `Security.js:47` (`sanitizeForShell` silently deletes the same characters), used by `chat/Attachments.qml:49,115`, `chat/AttachmentChips.qml:38`, `chat/HelperCommands.qml:27`.
- **What is wrong:** `Report (final).pdf`, `Q&A.docx`, `Budget $2026.xlsx` or "Notes; draft.md" cannot be attached ("Unable to attach this file: unsupported or unsafe path."), cannot be opened from its chip, and cannot be a chat-export destination. The same strings are already wrapped in proper single quotes by `quoteForShell`/`rawShellSnippetQuote`, which is safe for every character except `'` (handled), so the blacklist adds no safety but breaks common names. Worse, `sanitizeForShell` would delete the characters and point at a different file.
- **Failure scenario:** A user drops "Contract (signed).pdf" on the chat and gets an error that blames the path.
- **Suggested fix:** Quote with `rawShellSnippetQuote` (escape only `'`), keep rejecting NUL, newline and `..`, and drop the character blacklist for file paths. Add the awkward names to `tests/test_security.py`.
- **Effort:** S. **Risk of fix:** low to medium (keep the shell-injection tests green; test names with `'`, `"`, `$(...)`, `;`).

### A7 - The image downloader can be sent to the local machine by a redirect
- **Severity:** medium. **Area:** security (server-side request forgery).
- **Where:** `kdeaichat/images.py:155-159` (`build_opener(_GuardedHandler(...))`).
- **What is wrong:** The guard only protects the HTTPS connection class. `build_opener` still adds the default plain-HTTP, FTP and file handlers (confirmed by listing `opener.handlers`), and Python's redirect handler follows `https -> http`. A public server can answer "302 -> http://127.0.0.1:11434/api/..." and the helper will make that request from your computer.
- **Failure scenario:** A model reply contains `![x](https://evil.example/a.png)`; the user clicks "Load picture" (the click is a good protection, see "Checked and fine"); the server redirects to a local service URL that does something on a GET (reload, delete in a naive local API). The response must look like an image to be kept, so data cannot easily come back, but the request is made.
- **Suggested fix:** Pass a redirect handler that refuses any redirect (or re-validates each hop with `valid_image_url` and the public-address check) and build the opener from only the guarded handler (`urllib.request.OpenerDirector`).
- **Effort:** S. **Risk of fix:** low.

### A8 - API keys are re-sent on redirects, and plain http:// is accepted with a key
- **Severity:** medium. **Area:** security / keys.
- **Where:** `kdeaichat/tts.py:147-159` (remote read-aloud), `kdeaichat/stt_http.py:50-58` and `:91` (remote dictation), `kdeaichat/schedule_direct.py:116` (scheduled provider call).
- **What is wrong:** These use `urllib.request.urlopen`, which follows redirects and copies the `Authorization`/`x-api-key` header to the new address, including a different host. A custom or compromised endpoint (or a typo'd URL that points to a redirecting service) can collect the key. Also `http://` URLs are accepted with a key, so the key goes over the network in clear text (fine for `localhost`, not for a LAN or the internet). The interactive chat (QML `XMLHttpRequest`) has the same http concern; **unverified** whether it follows redirects with headers (Qt strips authorization on cross-origin redirects by default in recent versions).
- **Suggested fix:** One shared helper `kdeaichat/http_safe.py` with an opener that does not follow redirects carrying credentials, and a warning in the UI (and Check setup) when a key is configured for a non-loopback `http://` address.
- **Effort:** M. **Risk of fix:** low.

### A9 - Anything running as you can make the widget send your files to the cloud
- **Severity:** medium. **Area:** security / desktop integration.
- **Where:** `kdeaichat/ask_inbox.py:47-56` (`clean` accepts any absolute file path and `send: true`), `chat/AskInbox.qml:91-96` (sends at once when the box is empty), `kdeaichat/krunner.py:89-94` (KRunner `Run` always uses `send=True`; the D-Bus method is callable by any program on your session bus).
- **What is wrong:** The inbox is correctly private (0700, 0600, atomic claim), so other users cannot write to it. But any program running as you (a script, an npm package, a browser extension helper) can drop a file `{"text": "summarise", "files": ["/home/you/.ssh/id_rsa"], "send": true}`, and the widget pops open and sends the file to the active provider without asking. It could already read the file, but the widget gives it a network path out.
- **Suggested fix:** Never auto-send when files are attached (fill the box and attach, but wait for Enter), or show a one-line "KRunner asks to send this. Send / Cancel" bar for requests that did not come from your own keystroke; restrict attached files to the current user's home and readable regular files; skip dot-folders like `.ssh` and `.gnupg`.
- **Effort:** S. **Risk of fix:** low.

### A10 - Dolphin "Ask about this file" silently does nothing for more than 10 files
- **Severity:** medium. **Area:** UX.
- **Where:** `kdeaichat/ask_inbox.py:64-65` raises "at most 10 files at a time"; `scripts/kdeaichat-ask:38-42` prints it to stderr only; Dolphin runs the script with no terminal (`desktop_integration.py:213`).
- **Failure scenario:** The user selects 25 photos, chooses the menu entry; nothing happens and no message is shown.
- **Suggested fix:** Take the first 10 and send a desktop notification ("Attached 10 of 25 files; the limit is 10"), or show the error with `notify-send`/`kdialog` when not attached to a terminal.
- **Effort:** S. **Risk of fix:** low.

### A11 - Every save re-serialises all chats; start-up reads all chat files on the UI thread
- **Severity:** medium. **Area:** performance.
- **Where:** `store/ChatStore.qml:178-190` (`JSON.stringify(session.messages)` for every chat on every flush, to compare with the last write) and `:131-158` (`loadAll` reads and parses every chat file synchronously).
- **What is wrong:** With 200 chats at about 100 KB, one saved message costs about 20 MB of string work in plasmashell's UI thread, and opening the widget the first time reads and parses about the same, so the desktop can stutter. `Sessions.qml`'s comments already note a previous "plasmashell appears hung" problem.
- **Suggested fix:** Only re-serialise the chat that changed (keep a dirty set set by `saveCurrentSessionState`/`setSessionProperty`), and load the open chat first, the others lazily (the index already holds the titles).
- **Effort:** M. **Risk of fix:** medium (the "only changed chats are rewritten" logic is what protects data; keep the existing tests and add one with 300 synthetic chats and a timing budget).

### A12 - Very long messages are permanently cut when loaded
- **Severity:** medium. **Area:** data loss.
- **Where:** `chat/Sessions.qml:58-62` (cuts content at `maxMessageChars`, 2,000,000, and appends "[message truncated]") followed by normal saving.
- **What is wrong:** The cut is meant to protect the display, but the shortened text is what the next save writes, so the original is gone from disk. It needs a 2 MB message, which is rare (large pasted logs, agent output), but the loss is silent.
- **Suggested fix:** Truncate only for display (a separate property) or keep the full text in the store and show "Show full message"; at minimum skip saving the chat after a truncating load.
- **Effort:** M. **Risk of fix:** low.

### A13 - Changelog is contradictory and still "Unreleased"
- **Severity:** medium. **Area:** docs.
- **Where:** `changelog.md:8-30`. The "Unreleased" section announces, one after another, "A natural read-aloud voice (Kokoro, the new default)", "Parakeet dictation, the new default" and "Speech Note is the new default" (in that order of appearance: Speech Note first, then Kokoro, then Parakeet), while `metadata.json` already says 1.4.0.
- **What is wrong:** A user reading the notes cannot tell what the final default is, and the store text (`store_description.txt`) and `VOICE_SETUP.md` may repeat the old claims (**unverified**, not read in full).
- **Suggested fix:** Collapse the voice history into one entry describing the shipped behaviour (Speech Note default, others optional), rename the heading to `## [1.4.0] - <date>`, and reconcile `README.md`, `store_description.txt`, `VOICE_SETUP.md`.
- **Effort:** S. **Risk of fix:** none.

### A14 - A streaming reply is not saved until it finishes
- **Severity:** medium. **Area:** data loss / reliability.
- **Where:** saves happen at `chat/SendController.qml:57,79,237,274`, `chat/ReplyEvents.qml:81,138` (on send, completion, stop), and `chat/StreamBuffer.qml` only fills in-memory properties.
- **What is wrong:** If plasmashell crashes or is restarted halfway through a long answer (an agent task can take many minutes), the question is on disk but the partial answer is not.
- **Suggested fix:** Save the partial reply every 15-30 seconds while streaming (a debounced `saveCurrentSessionState(false)`), marked "(interrupted)" if it is found unfinished at start. Remember A11 (serialise only the open chat) before adding more saves.
- **Effort:** S. **Risk of fix:** low.

### A15 - KRunner and Dolphin files are left behind when the widget is removed
- **Severity:** medium. **Area:** desktop integration.
- **Where:** `kdeaichat/desktop_integration.py:296-297` and `:305` install files outside the package (`~/.local/share/krunner/...`, `dbus-1/services/...`, `kio/servicemenus/...`) whose `Exec` points at `scripts/` inside the widget folder (`:177-178`, `:202-213`).
- **What is wrong:** They are removed only when the user switches the option off in Settings. Removing or moving the widget package first leaves a KRunner entry, a D-Bus activation file and a Dolphin menu entry that point at a script that no longer exists: Dolphin shows a dead menu item and D-Bus logs errors each time KRunner asks.
- **Suggested fix:** Document "switch off before removing" next to the switches and in `user_manual.md`; add a `kdeaichat-uninstall` helper command or an "if the script is missing, delete the files" check at the start of each run (the files carry a marker so this is safe); the widget already re-syncs them at start (`chat/AskInbox.qml:start`).
- **Effort:** S. **Risk of fix:** low.

### A16 - A malformed D-Bus message stops the KRunner service
- **Severity:** low. **Area:** security / robustness.
- **Where:** `kdeaichat/minidbus.py:311` (`decode`), loop at `kdeaichat/krunner.py:130-135`.
- **What is wrong:** `decode` raises `IndexError`/`struct.error` (confirmed with a hand-made message) rather than `DBusError`, and the serve loop catches neither, so one bad message from any program on your session bus ends the service. D-Bus starts it again on the next use, so the effect is a short KRunner hiccup. Very deeply nested variant types could also exhaust Python's recursion limit (**unverified**); messages up to 128 MiB are accepted (`:299`) which is more than a runner needs.
- **Suggested fix:** Wrap each `read`/`_handle` in `try/except Exception`, reply with an error or drop the message, and lower the size cap to about 1 MiB for the runner.
- **Effort:** S. **Risk of fix:** low.

### A17 - Scheduled notifications put a reply preview on the command line
- **Severity:** low. **Area:** privacy.
- **Where:** `kdeaichat/schedule_notify.py:49-52` (the title and 140 characters of the reply go to `notify-send` as arguments).
- **What is wrong:** Visible to other local users for a moment, and also shown on a locked screen. Low impact, but it is the one place a reply leaves the private-file channel.
- **Suggested fix:** Use the D-Bus notification call through `speechnote_bus`-style private connection (`minidbus.Connection`) or show only the schedule name and "A new reply is ready" unless the user opts into previews; honour "hide notification content on lock screen".
- **Effort:** S. **Risk of fix:** low.

### A18 - The "keep Speech Note ready" timer starts a helper process every 45 seconds
- **Severity:** low. **Area:** performance.
- **Where:** `voice/SpeechNoteWarm.qml:23` (`tickMs: 45000`), `:66-71` and `:42-48` (while the popup is open and for `speechNoteKeepReadyMinutes` after it closes).
- **What is wrong:** Each tick launches `python3 kde_ai_helper.py` plus a `busctl`; with the default engine and the popup left open, that is about 80 process starts an hour for a feature the user may not be using, and `speechnote_start` is called on every popup open even when Speech Note is not installed.
- **Suggested fix:** Skip the warm-up when `speechnote_status` last said "not installed", and use a longer interval (Speech Note's idle exit is about a minute, so 45 s is close to the limit; test 50-55 s) or one long-running helper.
- **Effort:** S. **Risk of fix:** low.

### A19 - Credentials in the OpenCode "already running" state file and log are not atomically private
- **Severity:** low. **Area:** security hygiene.
- **Where:** `kdeaichat/opencode_server.py:76-78` (`open(..., "w")` then `chmod`), `:73-74` (log file with default permissions in a 0700 folder).
- **What is wrong:** There is a short moment where the state file has default permissions, and the server log (which can contain prompts if OpenCode logs them, **unverified**) is created with the user's umask. Inside a 0700 folder the real exposure is nil today, but if A3 stores a password there this becomes important.
- **Suggested fix:** Use `common.atomic_write_json`-style 0600 creation (`os.open(..., 0o600)`) for both.
- **Effort:** S. **Risk of fix:** none.

### A20 - Runtime payload files can be left behind
- **Severity:** low. **Area:** privacy.
- **Where:** `store/HelperRunner.qml:31-43` writes `kdeaichat-payload-*.ini` and relies on the helper to delete it.
- **What is wrong:** If the helper never starts (python missing, killed, or plasmashell stops first) the file, which holds read-aloud text, stays in `$XDG_RUNTIME_DIR` until logout. The folder is private, so this is only tidiness.
- **Suggested fix:** Have the helper sweep payload files older than one hour at start; the ask inbox already does the same for requests (`MAX_AGE`).
- **Effort:** S. **Risk of fix:** none.

### A21 - The ask inbox can stay stuck after an error
- **Severity:** low. **Area:** bug (unverified).
- **Where:** `chat/AskInbox.qml:103-120`.
- **What is wrong:** `_busy` is cleared after `chat.sendMessage()` returns; if that call throws (for example a send while the chat is in an odd state), the timer has already stopped and `_busy` stays true, so every later KRunner request is queued and never applied until the widget restarts. Not reproduced.
- **Suggested fix:** Clear `_busy` in a `try/finally`, and add an upper bound (for example 30 s) after which `_busy` is cleared anyway.
- **Effort:** S. **Risk of fix:** low.

### A22 - Hard-coded English messages in a translated widget
- **Severity:** low. **Area:** UX / i18n.
- **Where:** 15 `pushErrorMessage("...")` calls (for example `chat/HelperCommands.qml:29,33`, `chat/Attachments.qml:118`) and messages built in `chat/Sessions.qml:28,61,71`, `chat/EffectiveConfig.js` (`unavailableText`), plus the default chat title "New Chat" (`Sessions.qml:193`).
- **What is wrong:** Seven languages ship (`contents/locale/`), yet these messages, and the "New Chat" title that appears in every history list, are never translated.
- **Suggested fix:** Wrap in `i18n()` where the call site is QML, and return message keys from JS modules (translated by the caller). Re-extract the `.pot`.
- **Effort:** M. **Risk of fix:** low.

### A23 - Two keyboard / screen-reader gaps worth fixing now
- **Severity:** low. **Area:** accessibility (a separate pass covers the rest).
- **Where:** `chat/QuoteBlock.qml:93-104` (jump to the quoted message is a mouse click only, no `Accessible.role`/keyboard activation); `chat/PendingFiles.qml:44-52` (the reason a file failed to attach is only a hover tooltip); `chat/MessageText.qml:42-46` (links in messages open on click; whether they can be reached and activated with the keyboard in a `TextEdit` is **unverified**).
- **Suggested fix:** Make the quote a `QQC2.AbstractButton` with `Accessible.name`, put the file error in visible text and in `Accessible.description`, and offer "Open link" in the message's context menu.
- **Effort:** S. **Risk of fix:** low.

### A24 - Local "image" paths and the clipboard temp file linger if the widget closes mid-attach
- **Severity:** low. **Area:** privacy.
- **Where:** `doc_extractor.py:305` (clipboard images saved to `/tmp/kdeaichat_clip_*`, 0600), cleaned in `chat/Attachments.qml:44-59` and `chat/SendController.qml:161` only when the attachment is removed or sent.
- **What is wrong:** A pasted screenshot not yet sent stays in `/tmp` if the widget is closed or plasmashell restarts (0600, so only the user can read it, but `/tmp` may not be cleared for days on some systems).
- **Suggested fix:** Write to `$XDG_RUNTIME_DIR` instead of `/tmp` (cleared at logout) and sweep stale `kdeaichat_clip_*` at start.
- **Effort:** S. **Risk of fix:** low.

### A25 - The desktop-integration state file and Exec quoting have small gaps
- **Severity:** low. **Area:** robustness.
- **Where:** `kdeaichat/desktop_integration.py:267-275` (temporary file is not removed if writing fails), `:181-186` (`_quote` doubles a backslash once; the desktop-entry specification asks for it to be doubled again inside quotes, so a widget path containing a backslash would not start).
- **Suggested fix:** Reuse `common.atomic_write_text`; follow the spec's double-escaping or refuse paths with a backslash.
- **Effort:** S. **Risk of fix:** low.

### A26 - Dead reference in documentation
- **Severity:** low. **Area:** docs / tests.
- **Where:** `kdeaichat/minidbus.py:6` says the module "is checked against a real dbus-daemon in tests/test_minidbus.py", but no such file exists (the checks live in `tests/test_krunner.py` and `tests/test_speechnote.py`); `CLAUDE.md`/`docs/development.md` do not list the new desktop-integration files either.
- **Suggested fix:** Fix the sentence or add the test (a malformed-message test would also cover A16).
- **Effort:** S. **Risk of fix:** none.

---

## Mode-rule review (no switching modes inside a chat)

No violation found. A chat's `source` is set at creation (`chat/Sessions.qml:197`), `setSessionProperty` and `setSessionOverrides` ignore it (`:135`, `:159`), `chat/ModeSync.qml` only re-reads the open chat's own mode, `/mode` changes the setting for new chats only and says so (`chat/CommandRunner.qml:131-138`), a missing backend produces the "stays in mode" message instead of falling back (`EffectiveConfig.js:unavailableText`), scheduled runs use the chat's own mode (`kdeaichat/schedule_exec.py:1-14`), and the ask inbox uses "the open chat, in its own mode" (`chat/AskInbox.qml:6-10`). The one place a mode is assigned after creation is `inferSource` for very old chats that had none, which is by design and stored once.

## Checked and fine (so nobody re-checks)

- `safe_path` (`kdeaichat/common.py:28`) rejects NUL/newline, relative paths and `..`; the chat folder commands confine to `chats/applet-<id>` (`kdeaichat/chats.py:25-31`); images use fixed relative-path patterns and `realpath` checks (`images.py:80-91`).
- Image bytes are identified by their first bytes, not by name or server type, and written 0600 atomically; Markdown image links are replaced by a placeholder, so Qt never fetches them by itself (`chat/ImageExtract.js:137-158`, `chat/MessageBody.qml:54-57`). I also tried an inline `<img src="http://127.0.0.1:...">` in a Qt `TextEdit` with `MarkdownText` against a local test server: no request arrived within 3 seconds in an offscreen run (not a proof for every Qt version).
- Link opening goes through `Security.validateUrl` (http, https, mailto only, no credentials) (`chat/MessageText.qml:42-46`, `Security.js:69-90`).
- The ask inbox (`kdeaichat/ask_inbox.py`): 0700 folder owned by the user, 0600 files, `O_NOFOLLOW`, atomic claim by rename, size and age limits.
- KWallet: one client (`store/Wallet.qml`), keys never in config, helper reads keys over D-Bus and keeps them in memory (`kdeaichat/schedule_wallet.py`); API keys never appear in argv on any path I read.
- Pi bridge: loopback only, random token compared with `hmac.compare_digest`, state file 0600 (`kdeaichat/pi_bridge_server.py:205-221,341-351`).
- Local server probing is restricted to 127.0.0.1, six fixed ports, no redirects, no proxy, no keys (`kdeaichat/local_servers.py:35-41`).
- Speech Note over D-Bus: only model ids on the `busctl` command line; spoken text goes through a private socket call (`kdeaichat/speechnote.py:_call_privately`).
- Scheduler design (per-folder lock, append then inbox merge by run id, `schedule_chat.py:1-20`) is sound; the hand-written INI writer is covered by `tests/test_schedule_ini_qt.py`.

## Tests, CI and what is not covered

- Passing: 700 tests, about 6 minutes locally. Not flaky in this run (one run only; no repeat).
- Missing tests that map to the findings: damaged chat file / index (A1, A2; the memory store has one, chats do not), export of a large chat (A4), file names with `(`, `&` (A6), redirect handling in `images.py` and the three key-carrying clients (A7, A8), ask requests with files and `send` (A9), more than 10 Dolphin files (A10), a malformed D-Bus message (A16), an `AskInbox` send that throws (A21).
- The QML tests run offscreen, so nothing exercises real KRunner, Dolphin or KWallet; that is acceptable and the dev scripts cover the rest, but the release checklist should include one manual KRunner and Dolphin pass on a clean user.
- `pytest` takes about 6 minutes; the slowest files are worth profiling before CI minutes grow (**unverified**: I did not time individual files).

## UX notes (all modes and settings)

- **Direct, OpenCode, Pi:** the "this chat stays in X mode" messages are clear. A confusing spot remains: `/mode opencode` changes the main setting immediately and persistently (it writes `plasmoid.configuration` from the chat, `chat/CommandRunner.qml:134-135`), so the Settings page and every new chat change after a slash command; the confirmation line says it, but a user may type it as a one-off. Consider "/mode opencode" asking "Use OpenCode for new chats from now on?" once.
- A chat in OpenCode or Pi mode whose agent is not installed shows the "can't answer right now" text (good) but the way out ("start a new chat in another mode") needs a visible button, not only text.
- Settings pages: every setting has a plain-language line (good); the Voice page presents five engines plus Speech Note, and the changelog still describes the older ones as defaults (see A13).
- Error cards offer "Check setup" (good); make sure the same button exists for export and attachment failures (A4, A6) so these are not dead ends.

## New ideas (from general knowledge of what desktop AI chat users expect in 2026; no web browsing was done)

What people typically ask of desktop AI assistants in 2026: private/local models by default, one-keystroke access from anywhere, answers that use what is on screen or in a file, tools and agents that do real work with clear permission prompts, voice in and out, honest cost and usage numbers, easy export and backup, and not being locked to one provider. KDE AI Chat already covers providers, local models, Pi/OpenCode agents, MCP, schedules, memory, voice, KRunner/Dolphin entry points, search, projects and incognito. The gaps:

| # | Idea | Why users want it | Effort | Risk |
|---|---|---|---|---|
| N1 | **Ask about the selected text or the screen**: a global shortcut that sends the current selection (primary selection or clipboard) or a region screenshot to the chat | The most common "assistant on my desktop" use; KRunner needs typing, Dolphin needs a file | M | Medium (screenshot permission on Wayland through the portal; privacy: show what will be sent) |
| N2 | **Spending and usage page with budgets and alerts** (per provider, per month, from the existing token/cost fields, "you have used 80% of your limit") | Scheduled prompts and agents can run up bills; users ask for hard stops | M | Low |
| N3 | **Automatic fallback model** when a provider is rate-limited, down or out of credit (user-defined order, per chat, never changes the chat's mode) | Reliability; mentioned often for OpenRouter/free tiers | M | Medium (must stay inside the chat's own mode; show which model answered) |
| N4 | **Compare two models side by side** for one prompt | Choosing models is hard; users like to see differences | M | Low |
| N5 | **Chat with my files (local document index)**: pick folders, search them locally, give the model the best passages | Very common request; keeps documents on the computer | L | Medium (index size, privacy of what is sent; an optional local embedding model) |
| N6 | **Backup, restore and import/export of all chats and settings** (one encrypted archive; import from ChatGPT/Claude exports) | Data portability; protects against A1/A2-style loss | M | Low |
| N7 | **Optional encryption of chats at rest** (key in KWallet) | Chats are 0600 plain files today; shared or stolen laptops | M | Medium (lose the key, lose the chats; needs a clear recovery story) |
| N8 | **Hands-free voice conversation** (listen, answer, listen again, with barge-in) building on Speech Note | Voice is already there; users ask for a conversation mode rather than push-to-talk | M | Medium (echo, battery, privacy of an open microphone) |
| N9 | **Web search and page-reading tool** for direct chats (a user-chosen search provider, results shown with sources) | Models without browsing are seen as out of date | M | Medium (prompt injection from web pages; show sources, require approval for actions) |
| N10 | **A tool-approval centre**: one place to see and allow/deny what each agent or MCP server may do, remembered per project | Agents that touch files and the shell are the top safety worry in 2026; permission cards exist, central management does not | M | Low |
| N11 | **Code and diagram output you can use**: run-in-sandbox for small scripts, render Mermaid/LaTeX, "open in Kate" | Users expect more than text from code answers | L | Medium (sandboxing) |
| N12 | **Plasma-native touches**: activities-aware chats (a chat set per Activity), KDE Connect "send to phone", a panel badge for unread scheduled replies | Makes the widget feel part of Plasma rather than a chat app in a popup | M | Low |

## Suggested order

1. Before 1.4.0: A1, A2 (chat store safety), A3 (OpenCode password), A4 (export), A6 (file names), A13 (changelog). All small except A3.
2. Soon after: A5, A7, A8, A9, A10, A12, A14, A15.
3. When convenient: the low items, N2, N6, N1.
