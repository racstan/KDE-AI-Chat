# Changelog

All notable changes to the **KDE AI Chat** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Schedules, new back end (Phase 5, part 1; the editor and the real background run follow).** A schedule now has a list of timing rules and fires at their union: once, daily (every N days), weekly (weekday chips, every N weeks), monthly (a day 1–31 or the last day, every N months), hourly (every 1/2/3/4/6/8/12 hours at a minute, optionally between two hours), every N minutes (15 minimum) and cron (advanced/imported), each with several times. "Mondays at 16:00 and the other days at 15:00" is two weekly rules. Plus start/end dates, a run limit and a catch-up option (off by default; on: one run for times missed within 12 h). Definitions live in `~/.local/share/kdeaichat/schedules.v2.json` (written only by the widget); run state (last run, count, missed/skipped history trimmed to `historyLimit`) in `schedule-runs/<id>.json` (written only by the job), both atomic and private. One stdlib engine gives the plain-language summary ("Tue–Sun 15:00", "Every 2 days at 09:00"), the next runs, warnings (02:00–03:00 daylight-saving times, months without day 31, "never runs") and the run/skip decision. Each enabled schedule gets a systemd user timer `kdeaichat-sched-<id>.timer` (one `OnCalendar=` line per rule time, cron's day-of-month OR weekday as two lines, last day as `*-*~01`; checked with `systemd-analyze` before saving) that starts the shared `kdeaichat-run@.service`; systemd only wakes the job and Python decides (every-N days/weeks/months, start/end dates, already ran, edited since, catch-up window). New helper commands `schedules_list`, `schedule_preview`, `schedule_save`, `schedule_delete`, `schedule_history`, `schedules_sync` and `run_schedule <id>` (for now it only records its decision; it does not send the prompt yet). **Migration:** the old `schedules.json` is converted once into `schedules.v2.json` from the fields you picked (fixing the old cron bugs: "every N weeks" is kept, hourly keeps its minute), with a backup `schedules.v1.json`; the old file is left as it was so the old scheduler keeps working until it is removed. Incomplete old entries come over switched off and marked for review.
- **Scheduled prompts run by themselves, in the chat's own mode (Phase 5, part 2).** When a schedule is due, its systemd timer runs the prompt without the widget: a direct chat calls its provider (non-streaming; the key is read from KWallet over D-Bus, and if KWallet is locked the run is skipped, recorded as "skipped: wallet locked" and a notification says so), an OpenCode chat uses its own OpenCode session and folder (a temporary local `opencode serve` is started for the run when none answers, and stopped afterwards), a Pi chat goes through the Pi bridge in the chat's folder. The chat's provider, model, system prompt (Personality, extra instructions, project and chat instructions, response length) and its recent messages (same "earlier messages" limit) are used as in the widget; memories, tools and attachments are not. The prompt may use `{{date}}`, `{{time}}`, `{{weekday}}` and `{{last_run}}` (the last successful run). Nobody can answer an agent's permission request or question during a scheduled run, so they are declined and the reply says so. The prompt and the reply are added to the chat (marked as scheduled) and the run's result (ok / error / skipped, with the reason) goes into the schedule's history; runs that failed or were skipped don't count toward a run limit. The open widget picks the reply up at once without polling (it watches the chat folder) and never switches the chat you are in; "<schedule> is ready" opens that chat when clicked. With Plasma not running, or when a run fails, the notification comes from the job itself (no click action).
- **Schedules, new editor (Phase 5, part 3).** Settings → Schedules is now **New schedule…** and the list (no global switch and no daemon buttons: each schedule has its own on/off switch): each schedule shows its name, chat, a plain summary ("Mon 16:00; Tue–Sun 15:00"), the next run, the last result (sent, failed with the reason, missed, …), an on/off switch, Edit, History (when each run happened and what came of it) and Delete (asks first). Schedules brought over from the old scheduler that lack a chat or a time say so ("Needs a chat and a time") and open ready to finish. The editor has a name, the chat (this widget's chats), the message and the timing rules: add and remove rules, each one weekly (weekday chips, every N weeks), every day / every N days, monthly (a day or "Last day of the month"), once, every N hours (1/2/3/4/6/8/12, at a minute, between two hours), every N minutes (15 minimum) or a custom cron line, each with several times; a new weekly rule ticks the days the other rules leave free, so "Mondays at 16:00, the other days at 15:00" takes two clicks. A live preview (from the helper, 300 ms after each change) shows each rule's summary, the whole schedule, the next three runs and warnings (daylight-saving times, months without day 31, never runs). **More options**: start and end date, stop after N runs, run once when back if missed (off by default; within 12 h unless changed) and the notification. The helper's validation error is shown in the editor and nothing closes until the save worked. **Describe when**: type "weekdays at 9 and Sunday at noon" and **Fill in** asks the main settings' provider and model (Settings → Connection; not OpenCode or Pi) once for the rules as JSON; when the sentence can be read two ways ("every other day": the remaining weekdays or alternate days?) the model asks, with an answer button per reading and a free answer, until it can give rules. The rules are checked by the helper and put in the editor for you to review; nothing is saved by it. **Schedule a message…** in the chat's ⋮ menu opens the same editor over the chat with that chat chosen. A message a schedule sent shows "Scheduled: <name>" next to your name. The 1,391-line `ScheduleDialog.qml` and `config/SchedulerService.qml` (daemon start/stop/auto-start buttons) are replaced by small components in `config/` (`ScheduleDraft.js` and `ScheduleDescribe.js` are plain JS, tested with node). The settings `schedulerEnabled` and `executeMissedSchedules` are removed (the old "send missed messages" choice became each migrated schedule's catch-up option). `scripts/dev-run.sh` sets `KDEAICHAT_UNIT_DIR`/`KDEAICHAT_SYSTEMCTL` so a dev run never creates a real timer.
- **Projects**: group chats into projects. The history starts with **All chats**, each project (with its colour and how many chats it has) and **Archived**; choosing one filters the list. Create a project with the folder button, edit it with the pencil (name, colour, instructions, working folder, and optionally a model for direct chats), delete it from its menu: its chats are kept (they move to no project) and **Undo** brings it all back. Move a chat into a project from its menu (the header's More menu, or right-click / the Menu key on a history row, which also offers "New project…"); start a chat in a project with the **+** next to its name. A project's instructions go to every chat in it (after the main instructions, before the chat's own) in direct, OpenCode and Pi mode (Pi gets them through a private file, never on a command line); its folder is where OpenCode and Pi work unless the chat has its own; its model applies to direct chats (the chat's own settings first, then the project, then the main settings). Chat info and the folder row say what comes from the project. A project never changes a chat's mode. Projects are stored in `projects.ini` next to the chats; chats from before have no project and load unchanged. `DEV_PROJECT="…" scripts/dev-send.sh …` sends in a chat inside a project.
- **Projects**: group chats into projects. The history starts with **All chats**, each project (with its colour and how many chats it has) and **Archived**; choosing one filters the list. Create a project with the folder button, edit it with the pencil (name, colour, instructions, working folder, and optionally a model for direct chats), delete it from its menu, either keeping its chats (they move to no project) or, after a confirmation that says how many, **with its chats** (each deleted as a single chat is, with its memories, pictures and scheduled messages); **Undo** brings it all back (not the scheduled messages). Move a chat into a project from its menu (the header's More menu, or right-click / the Menu key on a history row, which also offers "New project…"); start a chat in a project with the **+** next to its name. A project's instructions go to every chat in it (after the main instructions, before the chat's own) in direct, OpenCode and Pi mode (Pi gets them through a private file, never on a command line); its folder is where OpenCode and Pi work unless the chat has its own; its model applies to direct chats (the chat's own settings first, then the project, then the main settings). Chat info and the folder row say what comes from the project. A project never changes a chat's mode. Projects are stored in `projects.ini` next to the chats; chats from before have no project and load unchanged. `DEV_PROJECT="…" scripts/dev-send.sh …` sends in a chat inside a project.
- **Memory, redesigned**: memories are separate short notes, each for every chat, for one project's chats or for one chat, and each can be pinned or turned off. They are kept in a private `~/.local/share/kdeaichat/memory.json` (0600 in a 0700 folder, written atomically by the helper; never in the widget's config), shared by all your KDE AI Chat widgets, with up to 1000 notes of up to 4000 characters. Each request takes the pinned notes and the ones that best match the message being answered and the two before it (keyword ranking), within a size you choose (new setting `memoryBudget` on Settings → Memory: 2000 characters by default, any amount, or no limit), and sends them as a short "Things the user asked you to remember" list: in the system prompt for direct and OpenCode chats, in Pi's instructions for Pi chats (a different choice starts Pi again on the same session). The notes sent are recorded on the chat (`memoryUsedIds`) for Chat info. Memory can be turned off everywhere (new setting `memoryEnabled`, on by default) or for one chat (`memoryOff`). Deleting a chat or project deletes its notes; Undo brings them back. **Migration:** the old memory text from the settings and each chat's old chat memory become notes (one per line, bullets removed; ones that were off come in turned off), and the old copies are cleared only after the new list was read back with all of them; running it again adds nothing twice.
- **Save and manage memories** (only you save them; nothing is suggested by the AI). **Remember** under a message (bookmark button) opens a small editor with the message, or the text you selected, cut to 4000 characters, and asks where it applies: all chats (the default), the chat's project (when it is in one) or this chat only. **`/remember <text>`** saves a note for all chats without sending anything (`/remember chat: …` or `/remember project: …` narrows it; `/remember` alone shows how). Both confirm with "Saved to memory" and **Undo**; saving a note you already have says "Already in memory" and turns it on if it was off. New page **Settings → Memory**: memory on or off for every chat, a one-line note on what is sent, and the list of notes with search, a filter (all chats / a project / one chat / turned off), Add, and per note on/off, pin, edit in place and delete (with Undo); scopes show the chat or project name. Notes brought over from the old memory start off, so the page offers **Turn on all**. **Chat info** has a Memory section: "Use memories in this chat" (applies at once) and the notes the latest message was sent with.
- **Pictures in replies** (direct mode): images a model sends back (OpenRouter `message.images` / `delta.images`, OpenAI-style image parts and base64 results, Markdown `data:` images) are saved as files in the chat's folder (`~/.local/share/kdeaichat/chats/applet-<id>/images/<chat>/<message>-<n>.<png|jpg|webp|gif>`, private, written by the helper) and shown in the message. The helper accepts only PNG, JPEG, WebP and GIF, judged by the file's first bytes (not its name or the server's content type), with a 12 MB cap per image. A message keeps only relative paths and notes (prompt, service, model, size, seed), never picture data or a signed link. Click a picture to enlarge it; each has **Copy image** (the helper puts it on the clipboard with `wl-copy` on Wayland or `xclip` on X11, since Plasma's QML cannot copy images; if neither is installed it says so), **Download** (a Save dialog) and, for pictures the widget generated, **Regenerate** (same prompt, a new image). Markdown image links in a reply (`![alt](https://...)`) are never loaded by themselves (Qt would fetch them): the text shows `[image: alt]` and a button "Show image from <site>" loads the picture only when you click, through the helper, https only, public hosts only (checked by `Security.js` and again when connecting), size-capped. Deleting a message or chat deletes its picture files shortly after, so Undo still works. Exports list the pictures: Markdown uses `![prompt](images/<chat>/<file>)` links, relative to the chat's folder, and JSON has an `images` list with the notes (the pictures themselves are not inside the export).
- **Image services** (direct mode, Settings → Connection → Add provider): **AI Horde** (community-run, works without an account through its documented anonymous key; your own key is optional and kept in KWallet) and **Pollinations.ai**, either with your own key (the documented `gen.pollinations.ai` API) or without one through the older free service (labelled as such: it may stop working, makes one picture every 45 seconds and adds a Pollinations logo; the widget keeps the 45 s gap with a countdown and honours 402/429 and `Retry-After`, never retrying by itself). Each service starts switched off: its form says in plain words that the prompt goes to the service (for AI Horde, to a volunteer's computer, and anonymous pictures are shared with LAION), links its terms, and you switch it on yourself. Live model lists (AI Horde: models with workers, adult-content models left out by the list's flags and a name blocklist, `nsfw: false` on every request), picture size, steps, count and seed within each service's limits (AI Horde without an account: up to 576 px, 30 steps, one picture at a time; 512×512 and 22 steps by default). AI Horde requests name the app honestly (`Client-Agent: KDE-AI-Chat:<version>:<website>`). A chat that uses an image service turns each message into pictures and stays a direct chat. Only the prompt is sent, never the chat.
- **`/image <prompt>`** in any direct chat makes a picture with the default image service ("Use for /image" in the provider list; the first one otherwise). While it works the reply shows AI Horde's queue place and wait time (checked every 4 s, every 10 s after a minute) or the free Pollinations countdown, with **Stop**, which cancels the AI Horde job (`DELETE`). Failures (kudos needed, no worker for the model, safety filter, limits, offline) appear as plain-words error cards.
- **"Input needed" notifications** (Settings → Appearance → Notifications, on by default): when the AI asks a question (direct `ask_user`, OpenCode or Pi) or an agent asks for permission while the popup is closed, or the open chat is another one, Plasma shows a notification with the question. Up to three answers are buttons on it, a typed answer goes in Plasma's inline reply box, and a permission is Allow / Deny. Answering there answers the card exactly as the card would; clicking the notification opens the widget (on a server without inline replies the Reply button opens the chat). It closes by itself when you answer the card in the widget.
- **One name per run of messages**: the sender's name and time show only on the first message of a run from the same sender (you, or the AI with the same model), like a group chat. The AI's tool steps, its questions and permission requests and its answer are one run, in every mode, until you write something or an error comes in. Question and permission cards have a plain heading ("Question", "Permission request") instead of repeating the model name.
- **The AI can ask you a question in direct chats** (new setting Settings → Chat → "Let the AI ask me questions", on by default). Direct requests now carry tools, handled for OpenAI-compatible APIs (streamed `tool_calls`), Anthropic (`tool_use`) and Gemini through its OpenAI-style endpoint. The first tool is `ask_user` (question, optional answer buttons, typed answer allowed unless the model says otherwise): the same question card the OpenCode and Pi agents use appears in the chat, you tap an option or type an answer, and the model carries on with it. Tool calls show as tool cards on the reply, are saved with the chat (so resending, regenerating and Export chat keep working) and go back to the provider as proper tool messages, or as plain text for a model without tools. If a model's server refuses tools (HTTP 400 naming them) the request is sent again without them and that model is remembered as having none until the widget restarts. Stop, or writing a message instead of answering, closes the question ("The user did not answer") and ends the request cleanly. At most 8 tool rounds per reply. `DEV_AUTO_ANSWER="text" scripts/dev-send.sh …` answers questions in the dev sandbox for end-to-end runs.
- **Slash commands in the message box**: typing "/" lists built-in commands first, then your prompt templates (Up/Down move in the list, Tab completes, Enter runs a command). `/model [name]` changes this chat's model (no name opens the model picker; it follows the same per-chat settings switch as the picker), `/variant [name]` changes its variant or thinking level (only listed when the model has variants), `/new` starts a new chat, and `/mode <direct|opencode|pi>` sets the mode of **new** chats only (the open chat keeps its mode). A command is never sent to the model and shows a short result under the box. Text starting with "/" that is no command or template (like "/etc/hosts?") is sent as a normal message. The empty-chat hint now reads "/ for commands and templates".
- **Browse messages with the keyboard**: with the message box empty (or not focused), Up/Down pick the previous/next message (highlighted, scrolled into view, with its action buttons shown); Down past the latest returns to the box, Esc clears the pick, and typing a character goes back to the box. PageUp/PageDown jump to the first/latest message (in a box with text only when the text does not itself scroll). **Changed:** editing your last message moved from Up to **Ctrl+E**. All listed in Settings → Appearance.
- **Copy an error**: error cards have a Copy button (tooltip "Copy error") that copies the full message with its HTTP status, URL and the provider's detail.
- **A wrong API key is caught when you save it** (Settings → Providers): a new or changed key is checked with the provider first. A rejected key (401/403) is not saved and the editor says so ("NVIDIA NIM rejected this key (403). Check you copied the whole key."). Providers that list their models for any key, like NVIDIA NIM, are checked with a one-token request to the chosen model. If the provider cannot be reached you can choose "Save anyway". Local servers without a key are not checked.
- **Live, usable model lists**: opening a provider in Settings → Providers lists its models without pressing a button (Refresh updates the list; it is kept for the settings session). Embedding, reranking, safety/guard, reward, speech and image models are hidden, with a "Show all models" switch. The chosen model is tried on save: a model the provider has retired or does not give your account (HTTP 404/410, "end of life") is flagged with the provider's reason, marked "(unavailable)" in the list, shown next to the provider and in the per-chat model settings, and needs "Use this model anyway" to save. The per-chat model picker uses the same live chat-model list.
- **The chat's mode, provider, model and variant are in Chat info** ("Direct · NVIDIA NIM · nemotron-3.5-bolt-e4b", "OpenCode · … · agent build", "Pi · … · thinking high"), on one line under "This chat" with a **Change…** button that opens the quick picker there (model, Pi's thinking level or OpenCode's variant and agent; no need to scroll to the settings below). The mode is shown but never changeable. With "Let chats have their own model settings" off, the picker says so and offers the settings. `/model` and `/variant` without a name open the same picker above the message box. The key hint ("Enter sends · …") only shows in a new empty chat.

- **Quote a message** (Discord-style): every user and assistant message has a **Quote** button (and **Ctrl+Q** quotes the message picked with Up/Down; listed in Settings → Appearance). The quote shows as a removable chip above the message box (speaker and first line; several quotes are kept in order, the same message is added once, and focus goes to the box). Chips are dropped when you switch chats. When you send, the quoted text goes to the AI together with your message in every mode (direct, OpenCode and Pi), as a block quote with a short speaker label in front of your text: `> Quoted (assistant):` followed by the quoted lines each starting with `> `, a blank line, then the message. A quote is cut at 4000 characters (with "…") and a message takes at most 10 quotes. The sent message shows the quotes in small blocks above its text; clicking one jumps to the original message and picks it if it is still in the chat. Quotes are kept with the message (saved chats, edit and resend keep them), and exports show them as Markdown block quotes (plain text: `> You: …`; JSON: a `quotes` list).

- **Model variants (reasoning levels) in every mode, only where the source reports them.** A variant picker appears next to the model only when the selected model has variants, and nothing is shown or sent otherwise. Direct: OpenRouter's `reasoning.supported_efforts` (sent as `reasoning: {effort}`) and Anthropic's `capabilities.effort` / `capabilities.thinking` (adaptive thinking plus `output_config.effort`; older Claude models get thinking on/off with one 8000-token budget) are read from the model list that is fetched anyway and cached with it per provider; a local Ollama says which models think through `/api/show` (variant "Thinking off"). Providers that report nothing (OpenAI, NVIDIA NIM, Groq, Mistral, Gemini's OpenAI-style list, ...) get no picker. OpenCode: the variant names per model come from the server's `/config/providers` (only the names are kept; the response also holds your API keys and is never stored or logged) and are sent as `variant` with the prompt. Pi: Pi's own thinking levels, only for models `pi --list-models` marks as thinking. The variant is chosen in Settings → Connection (direct: in the provider editor, per provider; OpenCode and Pi: next to the model), the Chat info panel and the quick picker (Chat info → Change…, or `/variant`; chips, with the variant shown on the Chat info line), and follows the same "this chat's settings win / main settings win" rule as the model. Only the variant's id is stored; an id the model no longer offers sends nothing.

- **Personality: you and the AI** (new Settings page **Personality**): tell the AI about you (your name, a few lines about you, the tone you like: Friendly, Professional, Concise or Playful, the language replies should be in, and "always / never" notes) and give the AI a name, a personality (None, Friendly, Professional, Witty, Mentor, Concise or your own words) and an avatar (a theme icon from KDE's icon chooser, or a PNG/JPEG/WebP/GIF/SVG/BMP picture). In the chat your messages show your name instead of "You" and replies show the AI's name and avatar with the model in small type beside it; exports use the same names (JSON lists them as `userName` / `aiName`). Direct chats get a short block made only from what you filled in ("## About the user" … "## Your persona" …, each field cut to a few hundred characters) at the very start of the system prompt; OpenCode and Pi chats keep their own instructions and don't get it. A chat can turn it off in its own settings ("Use my Personality settings", saved as `personalityOff`), independently of its own instructions. With nothing filled in nothing is sent and the chat looks as before. New settings `userName`, `userAbout`, `userTone`, `userLanguage`, `userNotes`, `aiName`, `aiPersonality`, `aiPersonalityCustom`, `aiAvatar` (plain text, never secrets).

- **Read aloud with the engine you choose (Phase 6, text-to-speech).** Settings → Voice now starts with two switches, both off by default: **Read aloud** and **Dictation**; with a switch off its buttons are hidden and nothing is installed or started for it (read aloud no longer needs dictation to be on). Read aloud has an engine list that shows only engines that can run here: **System voices** (Qt's text-to-speech with Speech Dispatcher, in the widget itself: nothing to install, works on a fresh system), **Kokoro** and **Flite** (when their Qt speech plugins work and have voices), **Piper** (when a `piper` program is found; pick a `.onnx` voice), a **speech server** with an OpenAI-compatible `/audio/speech` (URL, model, voice, speed; its API key is kept in KWallet, entry `tts-remote`, and read by the helper, never put in the settings or on a command line) and a **custom command** (text on standard input, a WAV on standard output or to `{output}`; run without a shell). Each engine shows its own options (language and voice from the engine, speed, pitch, voice file, speaker) and keeps them when you switch engines; **Say Hello** tries the choice before saving. In the chat, read aloud works with every engine, with Stop and **Pause/Resume** next to the status line; it reads only the text you selected when there is a selection (the selection stays when you click the button), the right-click menu of message text has **Copy** and **Read aloud**, and **Ctrl+Shift+S** reads the selected text (in a message, the message box or an edit box), else the message picked with Up/Down, else the last reply, and stops when it is reading. The engine is loaded on first use and unloaded after two idle minutes. New settings `voiceTtsEngine` and per-engine `voiceTts<Engine><Option>` entries; the old `voiceTtsVoice` and `voiceTtsModelPath` (Kokoro venv) are gone.

### Changed
- **Settings → Chat → Prompt templates** now explains in one plain paragraph what a template is and how to use it (/name in the chat box; / alone lists them).
- **The system prompt moved to Settings → Personality** as "Extra instructions" (same settings, nothing to migrate); the Chat page keeps history, chat names, questions, the default workspace, per-chat model settings and templates.
- **Archived chats have their own view**: they leave All chats and their project and are listed under Archived, with Restore and Delete (Undo). Archiving the open chat opens the latest one still in the list.
- **New chat is a plain +** next to Chat info; the More menu (which opens on hover) no longer sits beside it, and a hover-opened menu closes as soon as the pointer reaches another header button.
- **The line above the message box is gone**: it took a row from the input, and what it said (mode, provider, model, variant) is now in Chat info with a Change… button (see Added).
- Internal restructuring, no behaviour change: the widget root (`main.qml`) is split into small modules under `contents/ui/chat/` (chats, chat names, sending and the queue, direct requests, backend events, message edits, chat view navigation, attachments, helper commands, scheduled-task polling), and the helper's commands moved from `kde_ai_helper.py` into modules under `contents/ui/kdeaichat/`.
- **The default provider is listed first**: in Settings → Connection and in the per-chat provider picker the default provider is at the top (still marked default); changing the default re-sorts at once. Your saved provider order is not changed.
- **Model errors in plain words**: when a model is listed but your account can't use it (NVIDIA NIM's 404 "Not found for account", 410 end of life, "model_not_found" elsewhere), the error says "This model isn't available on your <provider> account..." (or "has been retired") and where to pick another, followed by the provider's own detail. A plain 404 for a wrong URL is left as is.
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
- **Read aloud said it had finished while it was still speaking**, and its stop fallback never matched (it looked for a `kdeaichat` process name the audio files never had). Playing now ends only when the engine reports the end, and a stop is final.
- **Voice errors showed no notification** (the code still used a data source that no longer existed); they now appear as a Plasma notification.
- **A picture reply showed two rows of buttons** (the picture's own view/copy/save/regenerate, and the message's edit/regenerate/copy/delete). A reply that is only pictures now shows the picture buttons plus Delete.
- **Up/Down move through the messages after clicking in the chat**: clicking a message's text or the space between messages gives the chat the keyboard, then Up picks the latest message and walks up, Down walks down and, past the latest (or with nothing picked), goes back to the message box; typing goes to the message box. Up/Down still move the cursor in a message box with text, in an edit in place and in the "/" list.
- **The resize grip no longer sits on a button**: it was drawn over the header's ⋮ (or the history's +) with the panel at the bottom, and over Send with the panel at the top or side. The rows in its corner (header, message box, history, Chat info's top and bottom rows) now leave it room, for every panel edge, and it stays visible above Chat info.
- **The Undo notice fits the window**: a long text (such as a long project name) wraps instead of running past both edges, and Undo and ✕ stay visible.
- Chat history rows no longer spill out of the popup: long or markup-looking titles are cut to one line, and rows stay clear of the scroll bar.
- **OpenCode mode is steadier.** The agent list is read from the OpenCode server for the chat's own workspace folder (so the folder's own agents appear) and offers only agents that can run a chat; it no longer switches to a different list read from `opencode.json` when the server is slow, and loading it never changes the chat's agent. The agent picked above a chat is the one the chat uses (stored on the chat when the chat has its own agent setting), and the selector always shows the agent the chat really sends with. A lost event stream is reopened and the reply caught up instead of ending in an error; a chat whose OpenCode session the server no longer has continues in a new one instead of failing on every message; a subagent's permission and question requests are shown; files edited by other sessions in the same folder are no longer listed under a reply; stopping while a session is being created no longer leaves an event stream open; "Sync session history" keeps message times, tool calls, token counts and errors and merges a reply's steps into one message.

### Removed
- **The read-aloud service**: `kde-ai-tts.service` (an always-on `voice_helper.py --tts-server` on port 9016) and the hard-coded Kokoro language `"a"`. On the first start after the upgrade the widget stops, disables and deletes that unit once (helper command `voice_startup`); the dictation unit is left alone.
- **The polling scheduler**: the daemon that woke every 5 seconds (`kde-ai-scheduler.py`, `kde-ai-scheduler.service`), the widget's 3-second check for its trigger files, the `pending/` and `results/` folders and the helper commands `poll_pending_triggers`, `setup_scheduler_service` and `save_all_schedules`. On the first start after the update the widget stops, disables and removes the old service and its copied script (once; nothing happens on later starts), drops triggers it left behind, and creates the timers of the migrated schedules. A scheduled message no longer switches the visible chat.
- The guide text blocks in settings, the interface-language override, the light/dark appearance override (light or dark now follows the system), the unused desktop-selection setting, and the process memory panel with its Kill buttons.
- The "capture screen region" (Spectacle) button in the chat input. Attach a screenshot as a file instead.
- **Dead code and unused settings** (see `docs/plan/dead-code.md`): old helper commands (`toggle_schedule`, `add_schedule`, `delete_schedule`, `migrate_history`, `read_history`, `write_history`, `update_schedule_history_status`, `get_memory_usage`, `get_voice_token`, `delete_venv_setup`, `privacy_report`, `opencode_server_status`, `pi_bridge_stop` and two aliases), unused JS functions, the unused settings `schedulerAutoStart`, `preselectedChatId`, `preselectedChatName` and `voiceTtsModel`, and the pre-rebuild audit docs. README, SETUP, user manual and store text no longer describe the removed memory, system-info, MCP and monitor features. The translation template was regenerated from the current source (translations not yet updated).

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
- **MCP tools in direct mode, system-information injection, the old memory manager (memory is back, redesigned: see Added) and automatic context compaction.** Use OpenCode or Pi mode for tools; the system prompt and message limit remain.
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
