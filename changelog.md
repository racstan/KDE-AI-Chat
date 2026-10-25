# Changelog

All notable changes to the **KDE AI Chat** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **A workspace in every mode, none by default**: the folder button and name under the header now appear in direct, OpenCode and Pi chats alike (OpenCode keeps its agent controls), show "No workspace" until you pick a folder, and have a button to clear it. A new chat starts with no workspace, or with the optional Settings → Chat → "Default workspace for new chats" (empty by default); existing chats keep what they have, and nothing falls back to your home folder any more. No workspace means: direct, the Attach dialog opens in its usual folder (with one, it opens there); OpenCode, no directory is sent (the server's own default); Pi, the chat runs in its own folder under `~/.local/share/kdeaichat/pi-workspaces/`. The Chat info panel's "Working folder" works in all three modes.
- **Neater chat export**: Export chat… saves Markdown, plain text or JSON (pick the type in the save dialog; the file gets its extension). Files start with the chat title and details (dates, mode, provider, model), have clear speaker headings with times, keep code in fenced blocks and list attachments and tool calls readably. Reasoning, internal markers and HTML wrappers are left out.
- **A chat keeps the mode it was started in** (direct provider, OpenCode or Pi). Changing the mode in the main settings, or the per-chat settings, only affects new chats; it no longer moves a chat you have open (or a reply that is streaming) to another mode. The per-chat settings still choose the provider, model, agent and thinking level inside the chat's mode, and the Chat info panel shows the mode as fixed. Older chats without a stored mode are given one once. If a chat's mode isn't available (OpenCode or Pi not reachable), the chat says so in a notice instead of switching.
- **Empty chat instructions are off**: the "Give this chat system instructions" box is unchecked for a chat without instructions, and turning it on with no text sends and saves nothing.
- **Settings rebuilt as six small pages**: Providers (providers, time limit, streaming), Harness (direct, OpenCode or Pi, and the agent's default provider and model), Chat (system prompt, earlier messages sent, chat names, prompt templates), Schedules, Voice and Appearance (name, icon, sound). Changes are saved with Apply/OK like other Plasma widgets; prompt templates can now be edited, not only added and removed.
- **The chat window follows your Plasma colour scheme and accent colour**, light or dark, instead of its own blue-and-grey palette: the message box is dark in a dark theme, links use the scheme's link colour, and the controls are Plasma's own. Breeze icons replace the emoji on answered permission requests, delete buttons are no longer red, and errors are a neutral card with a red edge instead of red text on red.

### Added
- **Model settings per chat are now opt-in** (Settings → Chat → "Let chats have their own model settings", off by default). Off: every chat uses the mode, provider and model from the main settings, and a chat's own settings are kept but ignored. On: a chat can choose its own, and you pick who wins when they differ ("This chat's settings win" or "Main settings win"). The Chat info panel always says what the chat is using and where that comes from.
- The "More actions" menu in the chat header opens when you rest the pointer on it (and still opens with a click or the keyboard).
- **History beside the chat**: in a wide popup the chat history slides in as a side panel (one compact row per chat with Today/Yesterday/date, rename, archive and delete appear on hover or keyboard focus); in a narrow popup it still takes the whole view.
- **Chat info panel** (the (i) button in the header, replacing the old "chat controls" sidebar): this chat's input and output tokens, total cost where the provider reports it, number of messages, models used, and when it was created and last used, above the chat's own settings (provider and model, OpenCode/Pi, working folder, instructions, response length).
- Accessible names on every icon-only header button; the less-used header actions (rename, jump to first/previous/next/latest message, export, clear) are in one "More actions" menu.

### Changed
- **Token counts and cost come straight from the provider.** OpenAI-compatible streaming requests now ask for usage (`stream_options.include_usage`; retried once without it if a server rejects the field), OpenRouter also reports the real cost of each reply, and Anthropic's input count includes cached prompt tokens. Nothing is estimated.

### Fixed
- Chat history rows no longer spill out of the popup: long or markup-looking titles are cut to one line, and rows stay clear of the scroll bar.
- **OpenCode mode is steadier.** The agent list is read from the OpenCode server for the chat's own workspace folder (so the folder's own agents appear) and offers only agents that can run a chat; it no longer switches to a different list read from `opencode.json` when the server is slow, and loading it never changes the chat's agent. The agent picked above a chat is the one the chat uses (stored on the chat when the chat has its own agent setting), and the selector always shows the agent the chat really sends with. A lost event stream is reopened and the reply caught up instead of ending in an error; a chat whose OpenCode session the server no longer has continues in a new one instead of failing on every message; a subagent's permission and question requests are shown; files edited by other sessions in the same folder are no longer listed under a reply; stopping while a session is being created no longer leaves an event stream open; "Sync session history" keeps message times, tool calls, token counts and errors and merges a reply's steps into one message.

### Removed
- The guide text blocks in settings, the interface-language override, the light/dark appearance override (light or dark now follows the system), the unused desktop-selection setting, and the process memory panel with its Kill buttons.
- The "capture screen region" (Spectacle) button in the chat input. Attach a screenshot as a file instead.

## [1.4.0] - 2026-10-24

### Changed
- **📜 License**: KDE AI Chat is now licensed under the GNU GPL v3.0 or later (previously GPL-2.0 or later). The full text is in `LICENSE`.

### Added
- **🧩 Providers as a simple list**: Settings → General now shows your providers as one list. Add one from a preset (OpenAI, Anthropic, OpenRouter, Gemini, Groq, DeepSeek, Mistral, xAI, NVIDIA, Ollama, LM Studio, llama.cpp, LiteLLM, any OpenAI-compatible server…), edit its URL, key and model, fetch its model list, or make it the default. Your existing providers are carried over automatically.
- **⚡ Anthropic replies stream** as they're written, like other providers.
- **🔀 Per-chat provider & model switching**: Open the chat settings panel to change provider, model or mode for the current chat without touching your other chats. ([#3](https://github.com/racstan/KDE-AI-Chat/issues/3))
- **🔌 Multiple custom providers**: Add as many OpenAI-compatible providers as you like, each with its own name, URL and key — including several of the same type. Keys are stored in KWallet. ([#3](https://github.com/racstan/KDE-AI-Chat/issues/3))
- **🧰 MCP tool support (opt-in)**: Built-in web search plus your own MCP servers, configured under Settings → Other. ([#3](https://github.com/racstan/KDE-AI-Chat/issues/3))
- **🚫 Disable streaming option**: For providers that reject streamed requests (HTTP 400). ([#3](https://github.com/racstan/KDE-AI-Chat/issues/3))
- **🖼️ Custom widget icon**: Use any KDE icon name or an image file. ([#3](https://github.com/racstan/KDE-AI-Chat/issues/3))
- **🤖 Pi Coding Agent mode**: Chat with the Pi agent alongside OpenCode. Each chat keeps its own Pi session running in its folder, so replies stream as they're written, tool use shows live, Pi extensions can ask you questions or for permission in the chat, and Stop stops the agent. Idle Pi processes close on their own. Each Pi chat has its own provider, model, thinking level and working folder in the chat settings, which no longer change the defaults for your other chats.
- **OpenCode server managed safely**: In OpenCode mode the widget starts a local `opencode serve` when none is running, and its Stop button only ever stops a server the widget started. Replies, tool use, permission and question prompts and token use now come from OpenCode's live event stream.
- OpenCode agent profile selector, workspace directory selector and Git diff inspector.

### Changed
- **🖱️ Smoother touchpad scrolling**: Pixel-precise two-finger scrolling with tuned deceleration. ([#3](https://github.com/racstan/KDE-AI-Chat/issues/3))

### Security
- **🔐 API keys live only in KWallet**: Keys are no longer written to Plasma's widget config (pressing OK/Apply in settings used to copy them there in plaintext) or to `~/.config/kdeaichatrc`. Custom provider keys are no longer stored in the provider list. If KWallet is off or locked, the widget tells you instead of falling back to plaintext.
- **🗂️ Private chat files**: Chats are stored as one file per chat in `~/.local/share/kdeaichat/chats/` (a folder only you can read) instead of one large entry in Plasma's desktop config. Saving no longer rewrites that config file.
- **Automatic migration**: On first start, plaintext keys (and keys in the old `KaiChat` wallet folder) move to the **KDEAIChat** wallet folder, and chats move to their own files with a backup kept. Plaintext copies are removed only after the move is confirmed.

### Removed
- **MCP tools in direct mode, system-information injection, the memory manager and automatic context compaction.** Use OpenCode or Pi mode for tools; the system prompt and message limit remain.
- **Image-generation providers**, which never worked in chat.
- **The "Open in terminal" button** in OpenCode mode.
- **PlasmaShell auto-restart watchdog**: The widget no longer starts a background monitor that restarted your desktop shell, or spawns a heartbeat process every 5 seconds. Any monitor left running by an earlier version is stopped automatically.

### Fixed
- **OpenRouter "HTTP 402: requires more credits"**: requests now ask for at most 4,096 output tokens by default instead of the model's maximum.
- A reply could be built from the chat on screen instead of the chat it belonged to.
- Closing the settings page before keys had loaded could delete them from KWallet.
- The Save buttons for DeepSeek, MiniMax and OpenRouter keys didn't work.
- The Settings → Other page and model search in Settings → General failed to load or threw errors.
- **⚡ Lower idle CPU use**: The widget no longer starts a shell process every 3 seconds when the scheduler is switched off. ([#4](https://github.com/racstan/KDE-AI-Chat/issues/4))
- Fixed invalid theme and visibility bindings that logged `Unable to assign [undefined]` warnings in the journal. ([#4](https://github.com/racstan/KDE-AI-Chat/issues/4))
- Fixed QML binding loops and a blocking subprocess that could freeze plasmashell when opening chat settings.
- Hardened voice daemons with per-user token authentication, loopback/origin checks, bounded requests, private temporary audio, and authenticated systemd setup.
- Reworked request/session cancellation, OpenCode/Pi completion handling, MCP follow-up generations, context compaction, attachment correlation, and queued scheduler triggers.
- Added URL/path/session validation, bounded message and scheduler payloads, atomic scheduler writes, KWallet synchronization for custom providers, and temporary attachment cleanup.
- Custom Anthropic-compatible endpoints now work.
- Removed unused JavaScript modules that were no longer loaded by the widget.

---

## [1.3.1] - 2026-07-22

### Fixed
- **🗣️ Voice Service Autostart Management**: Fixed an issue where systemd user units (`kde-ai-stt.service` and `kde-ai-tts.service`) remained enabled and autostarted on system reboot even when voice tools were toggled off in settings. Toggling voice tools or TTS off now disables systemd autostart units (`systemctl --user disable --now`), and widget startup automatically syncs systemd service state to avoid unnecessary background RAM usage.

---

## [1.3.0] - 2026-07-21

### Added
- **■ Global TTS Stop Button**: Added an interactive global Stop (■) button to the bottom chat status bar during voice generation/playback, allowing instant interruption of text-to-speech.
- **📚 Streamlined Step-by-Step Setup Guide**: Completely redesigned `VOICE_SETUP.md` with clear distros requirements (Ubuntu, Arch, Fedora, openSUSE) and explicit environment steps.
- **📸 10-Image Screenshot Gallery**: Refactored the `README.md` to feature 10 newly-updated screenshots displaying settings, task scheduler, voice tools, and system memory monitors.

### Fixed
- **🗣️ Local Voice Mode GPU Support**: Fixed a bug where Voice STT/TTS would silently fall back to CPU despite GPU/CUDA libraries being installed. Ensured venv CUDA libs are preloaded before PyTorch checks device availability.
- **⚠️ Voice Installation Disclaimers**: Added time and storage requirement warnings to the setup guide to manage user expectations during machine learning framework installation.

---

## [1.2.9] - 2026-07-20

### Added
- **🗣️ Local Voice Tools Integration**: Documented Voice Mode and local setup for Whisper Speech-to-Text and Kokoro Text-to-Speech in the primary README and verified compatibility lists.
- **📅 Background Task Scheduler**: Promoted the systemd-integrated cron task scheduler daemon to a first-class supported feature.
- **📚 Documentation Updates**: Refactored README, VOICE_SETUP, and file catalogs to match the current release structure.

### Fixed
- **Voice Mode State Leakage & Controls**: Fixed voice status leakage across different chat sessions by centralizing the playback tracker in the root `main.qml` component. Switching chat sessions or creating new ones now properly halts current voice generation, stops playback, and cleans up UI states.
- **Manual TTS Stop Buttons**: Enabled manual TTS stop action on spoken assistant responses.
- **Voice Playback Race Condition**: Fixed a race condition in `voice_helper.py` where starting a new TTS session while one was active could cause state collisions. Added thread joins to wait for the previous synthesis thread to clean up before initiating the new playback.
- **Scheduler Auto-Archive and Limits**: Migrated and updated the scheduler task tracking logic in `kde-ai-scheduler.py` to auto-archive completed scheduled tasks and show run counts in `ScheduleDialog.qml`.
- **Repository Cleanup**: Removed unused pre-production testing scripts and temporary log files from git tracking.

---

## [1.2.8] - 2026-05-28

### Added
- **6-Part Demonstration Walkthrough Videos**: Replaced the outdated 2-part walkthrough with a brand new, highly comprehensive 6-part video walkthrough series under `.github/assets/` spanning all widget capabilities.

### Fixed
- **API Key Config Save Fix**: Resolved a critical race condition in the KCM initialization lifecycle where empty API key values were flushed over user credentials before `cfg_` aliases fully loaded.
- **Settings Auto-Save & Cleanup**: Removed the redundant manual "Save keys to config file" action button; keys are now fully auto-saved on switch and when closing/destroying the settings panel.
- **Always-Visible Clear Chat Button**: Kept the "Clear current chat history" button visible at all times in the chat view to prevent header layout shifting, disabling it dynamically when there are no messages to clear.
- **Repository Streamlining & Clean Packaging**: Purged unused development assets and the deprecated scratchpad file `scratch_config_v126.qml` from the root directory.

---

## [1.2.7] - 2026-05-27

### Added
- **Secure KWallet & Configuration Sync**: Replaced the old KWallet toggle with an automated background synchronization mechanism. API keys entered in settings are securely saved to KWallet via DBus, and fall back to local configuration (`~/.config/kdeaichatrc`) if KWallet is unavailable.
- **Configuration Auto-Save**: Settings are now persisted automatically as the user types — no Apply button click required. The configuration is written to disk immediately on change.
- **Chat Export**: Export any conversation to a `.md` or `.txt` file via the chat toolbar. The save dialog is pre-filled with `<chat_title>_<timestamp>.<ext>` as the default filename. Exports use full UTF-8 encoding and include a formatted header with role labels, timestamps, and the export date.
- **Right-Aligned User Bubbles**: User messages are now right-aligned with a distinct bubble style, mirroring modern messaging UIs. AI responses and system messages remain left-aligned.
- **LiteLLM Proxy Provider**: Added LiteLLM Proxy as a fully supported 17th provider. Connects to any LiteLLM-compatible server (default `http://localhost:4000/v1`). API key is optional for keyless local proxy setups. Full model discovery, KWallet/plain-config key storage, and model selection are all supported, enabling routing to 100+ LLMs through a single unified proxy.

### Fixed
- **Base64 Config Serialization**: Rewrote config payload handling to use base64 encoding when passing data through shell commands, eliminating all bash double-quote stripping and config parsing errors that occurred with special characters in API keys.
- **Config File Race Condition**: The config file and its parent directory are now guaranteed to exist before `xdg-open` is called, preventing the "empty file" bug where opening the config showed a blank file.
- **KConfig Caching**: Implemented physical plainconfig loading and synchronous pre-open writing to bypass KConfig's in-memory cache, ensuring the file on disk always reflects the current UI state.
- **Duplicate xaiApiKey assignment**: Removed an accidental double-assignment of `xaiApiKeyField.text` in `applyPlainConfigKeys`.

---

## [1.2.6] - 2026-05-23


### Added
- **Multi-Format Document & File Attachments**: Added drag-and-drop and copy-paste support for document attachments (Images, Word files, PDFs, CSVs, etc.) directly into the chat input field.
- **Text-Free Attachment Submissions**: Allows users to dispatch queries consisting solely of attachment files (images, documents) without forcing textual prompt input.
- **Message Editing & History Rewind**: Modifying an older user prompt now cleanly deletes all messages following it and re-runs the query, allowing users to rewind the chat history from the edited prompt.
- **Viewport-Aware Question Navigation**: Added Up/Down tool navigation buttons in the toolbar to cycle between user questions based on the active scroll viewport, with fallback index checking to prevent empty page scrolling.
- **NVIDIA NIM & OpenRouter Attribution**: Fully updated all NVIDIA configurations to the standard "NVIDIA NIM" terminology. Added HTTP-Referer and X-Title metrics/attribution headers for OpenRouter API requests.

### Fixed
- **Scrollbar Stability (Layout Flickering)**: Added large cache buffers (`cacheBuffer: 20000` on messages and `5000` on history) to prevent dynamic delegate recycling and scrollbar sizing/position jitter during scrolling.
- **Interactive Drag & Wheel Scrolling**: Overhauled manual scroll detection by monitoring `contentY` changes and checking scrollbar active/pressed states to prevent automated snap-to-bottom actions from fighting the user's manual scroll.
- **API Key Whitespace Sanitization**: Automatically `.trim()` all keys when loading configurations, stripping accidental spaces/newlines copied from web browsers that trigger HTTP 401 Unauthorized errors.
- **NVIDIA NIM Error Field Parsing**: Enhanced JSON response parsing in `doOpenAICompatRequest` to capture and display custom API error fields (such as `detail` or `message`) returned by NVIDIA NIM and OpenRouter gateway endpoints.

---

## [1.2.5] - 2026-05-22

### Added
- **Interactive Ctrl+Scroll Zooming**: Added Ctrl+Scroll interactive zooming support (`0.75x` to `1.5x` layout scaling) for the settings configuration sheet, offering on-the-fly sizing adjustments.

### Fixed
- **Dynamic Sizing and Auto-Scaling**: Completely overhauled the KCM configuration sheet to be dynamically responsive across all monitor aspect ratios and DPI scales. Enabled adaptive `wideMode` (single-column under `36` gridUnits, two-column when wide) and bound `Layout.preferredWidth: 0` to all fields, comboboxes, text areas, and warning labels, eliminating horizontal stretching and LHS coordinate clipping.

---

## [1.2.4] - 2026-05-22

### Added
- **Precise Bottom Scrolling**: Re-engineered `scrollToBottom()` list view controller to align to the absolute bottom coordinate (`contentHeight - height`) to ensure it scrolls precisely to the **last line of the latest message** instead of its midpoint.
- **Settings Theme Warning**: Added a helpful system configuration note in the appearance theme label explaining that appearance preferences apply strictly to the main chat popup UI, while the KCM settings sheet style is natively driven by the host system.

### Fixed
- **Version Number Alignment**: Updated `metadata.json`'s `KPlugin` block to correctly show **`1.2.4`** so the About tab displays the actual current release version.
- **Redundant Size Control Elimination**: Removed the redundant popupsize cycling ToolButton from the toolbar, as well as unused QML properties and timers, since drag-to-resize is natively supported by dragging the bottom-right corner.
- **Documentation Refactoring**: Removed the duplicate changelog section from `README.md` to establish `changelog.md` as the single source of truth, adding prominent KDE Store badge download hooks.

---

## [1.2.3] - 2026-05-21

### Added
- **High-Performance Markdown-to-HTML Parser**: Rebuilt Markdown rendering from the ground up! Written a custom, extremely optimized native JavaScript Regex parser to convert Markdown tags (bold, italic, links, headers, nested lists, inline code, and pre-formatted language code blocks) into high-performance HTML.
- **Beautiful RichText Rendering Without Freezes**: Switched the message label `textFormat` to `Text.RichText`. Qt's RichText layout engine renders this pre-compiled HTML instantly (<1ms), bringing back beautiful, rich formatting for AI responses with **absolutely zero UI lag or system hangs**.

---

## [1.2.2] - 2026-05-21

### Fixed
- **System Hang — True Root Cause Found and Fixed**: The actual cause was `textFormat: Text.MarkdownText` on the message content label. Qt's Markdown renderer converts the entire AI response into a QTextDocument rich-text tree — for long responses with code blocks, headers, and lists this takes 5–15 seconds and **completely blocks** the Plasma shell's single main thread. Switched to `Text.PlainText` as a temporary measure.
- **Dead Code Cleanup**: Removed the now-unused SSE batch timer, buffer properties, and `flushSseBuffer()` function left over from the v1.2.0 streaming experiment.

---

## [1.2.1] - 2026-05-21

### Fixed
- **System Hang During AI Response (Partial)**: Removed streaming (`stream: false`). This eliminated per-token writes but the hang persisted because the real bottleneck was the Markdown renderer, not the network layer.

---

## [1.2.0] - 2026-05-21

### Fixed
- **System Hang During Streaming (Partial)**: Attempted to batch SSE token writes via an 80ms Timer to reduce rendering pressure. The fundamental problem (QML property binding storm on every token) remained under fast providers, so this was superseded by the v1.2.1 non-streaming fix.
- **Long Chat Title Expanding the Window**: The header title `Label` had no width constraint, allowing very long session names to push toolbar buttons off-screen to the right. Now capped with `Layout.maximumWidth` so it always elides gracefully within the available space.

---

## [1.1.0] - 2026-05-21

### Added
- **OpenCode Interactive Questions**: Real-time interactive cards for prompt-based clarifications or input requests directly inside the chat bubbles, with Submit and Dismiss pathways.
- **OpenCode Session ID Header Display**: Real-time dynamic subtitle showing the active OpenCode session ID in the header area.
- **Ollama Provider Integration**: Out-of-the-box keyless support for local Ollama instances, pre-configured to point to `http://localhost:11434/v1` and defaulting to `llama3.2`.
- **Optional KWallet Support**: Toggle Secure KWallet credentials storage via a simple checkbox in settings. Disabling it saves API keys directly inside plain local configuration files for easier manual setups.
- **Full Offline Local LLM Support**: Keyless setup integration for local/offline engines (Ollama, LM Studio, or custom local OpenAI-compatible endpoints) without requiring dummy API keys.
- **Comprehensive User Manual & FAQ Guide**: Added a complete operational playbook and troubleshooting guide (`user_manual.md`) covering KWallet setups, Ollama CORS, and OpenCode workflows.

### Fixed
- **OpenCode Freeze Bug**: Refactored the network and stream connection logic to support robust async failure callback pipelines, completely resolving the "thinking" spinner hang.
- **Dynamic Theme apply bug**: Added strict `Kirigami.Theme` overrides and matching solid layouts in representations to honor Light and Dark appearance mode selections.
- **Repository Rename**: Updated all links, descriptors, metadata files, and git configuration to point to the new home: `https://github.com/racstan/KDE-AI-Chat`.
- **Repository Streamlining**: Removed temporary provider validation scripts (`validate_providers.py`) from distribution.
- **Stale URL Footprints**: Updated all documentation (`KDE_STORE_PUBLISHING.md`, `README.md`) and package instructions to strictly utilize the renamed `KDE-AI-Chat` endpoint URLs.

---

## [1.0.0] - 2026-05-20

### Added
- **Initial Release of KDE AI Chat** for KDE Plasma 6 & Qt 6.
- **13 API Providers**: Multi-provider support (OpenAI, Anthropic Claude, Groq, DeepSeek, Google Gemini, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA, Hugging Face, xAI, LM Studio, local OpenAI-compatible).
- **Session History Persistence**: Elegant native calendar-grouped history panel.
- **Smart Model Search**: Real-time searchable dropdown box for model switching.
- **Native Canvas Scaling**: Drag-to-resize panel support.
