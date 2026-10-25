# Dead and obsolete code: list for review

Written on `feat/gui-rebuild` at `2b3ee99`, after phases 4-A/4-B/4-C. This is the list the owner asked to see first. **Status: the approved items have been removed (see "Removal result" at the end).**

How it was found: scripted scans (every function, property and signal declared in `contents/ui/**/*.qml` and `*.js`, every helper command, every `main.xml` entry, every `.pot` message) with `grep -w` over `contents/ui/`, `contents/config/`, `contents/scripts/` and `tests/`, then a manual look at every hit with one or zero uses. Dynamic access was checked: `chat.<name>`, `root.<name>`, `rootRef.<name>`, `typeof x.<name> === "function"`, `Connections` `on<Name>Changed`, `configuration[name]`, and `Alias.fn` calls from QML. File:line numbers are for `2b3ee99`.

Risk: **low** = no app caller anywhere, only a test or nothing; **medium** = no caller today but a pending phase or a user-machine state might want it; **high** = could break a running install.

**The honest headline:** `main.qml` is almost clean (the rebuild already removed the big blocks). The bulk of the dead weight is in `kde_ai_helper.py` (old history and schedule commands, memory monitor), the stale `.pot` (about three quarters of it), and the user docs/screenshots that still describe cut features.

## 1. QML functions and properties with no use in the app

`main.qml` has 193 functions/properties/signals; all but the rows below are used by another QML file, by `main.qml` itself, or by a `Connections`/handler. Test fakes (`tests/qml/FakeChat.qml`) mirror many chat-root members; those do not count as app use.

| Item | file:line | Evidence | Risk | Recommendation |
|---|---|---|---|---|
| `property bool fetchingOpenCodeConfig` | `main.qml:79` | Only reference in the app is a write of `false` at `chat/OpenCodeMode.qml:147`. Never set to `true`, never read. Not in `FakeChat.qml` or any test. | low | **Remove** the property and the one assignment. |
| `property bool fetchingAgentsInProgress` | `main.qml:78` | Written at `chat/OpenCodeMode.qml:272` and `:280`, never read by any QML. Only a test reads it (`tests/qml/tst_opencode_agents.qml:154`, via `FakeChat.qml:115`). OpenCodeMode guards re-entry with its own `_agentsRequest`/`_agentWaiters`. | low | **Remove** (property, two writes, and the test assertion and FakeChat line). |
| `function configuredSessionSource()` | `main.qml:426` | One-line forwarder to `modeSync.newChatMode()`; single caller `main.qml:464`. | low | **Remove**: call `modeSync.newChatMode()` directly. Saves 1 line, removes a name. |
| `function chooseOpenCodeAgent` / `syncOpenCodeSessionHistory` | `main.qml:766`, `:764` | One-line forwarders to `openCodeAgent.chooseAgent` / `.syncHistory`. Used from `FullRepresentationContent.qml:107` and `chat/WorkspaceBar.qml:152`, and mirrored in `FakeChat.qml`. | low | **Keep**: they are the public chat-root API that the tests fake. Only drop if callers are moved to talk to the mode object. |
| `function stopLegacyWatchdog()` | `main.qml:1200`, called `:1868` | Only a startup cleanup of the removed watchdog; not dead. | high if removed | **Keep: migration** (see 3 and 6). Remove together with the helper command after a few releases. |
| `Connections` `onCustomProvidersJsonChanged` | `main.qml:1913` | `customProvidersJson` is only written by `store/Migration.qml:122` (clearing/rewriting old customs). After migration nothing changes it. | medium | **Unsure**: probably removable once the 1.4.0 migration is old; harmless meanwhile. |
| `readonly property alias composerItem` / `historyPane` | `chat/ChatBody.qml:24-25` | Used by tests only (`tst_history_panel.qml`, `mockups.qml`). | low | **Keep**: test hooks. |
| `readonly property alias undoNotice` | `chat/ChatShortcuts.qml:35` | Used by `tests/qml/mockups.qml` only. | low | **Keep**: test hook. |
| `readonly property alias iconSource` | `chat/PermissionButtons.qml:46` | Used by `tst_permission_buttons.qml` only. | low | **Keep**: test hook. |
| `readonly property string fontFamily` | `chat/MonoBlock.qml:15` | Used by `tst_cards.qml` only. | low | **Keep**: test hook. |
| `readonly property var providerChecker` | `config/ProvidersPanel.qml:52` | Used by `tst_providers_panel.qml` only. | low | **Keep**: test hook. |
| `stepCount`, `runningCount` | `chat/ContextList.qml:32-33` | Used internally at `:64-65` and by tests; fine. | low | **Keep**. |

No other `chat.<name>`/`root.<name>` member was found with zero readers. Also checked and found live: `attachmentRequestCounter` (`main.qml:1719`), `privacyNotice` (`FullRepresentationContent.qml:100`), `openCodeUseAgentModel` (`chat/OpenCodeMode.qml:210`), `sessionSourceInferred`, `titleRequested`, `queueCounter`, `piModelFetchWaiters`, `historySidePanel` (set by `ChatBody` via a Binding).

## 2. JS functions and exports with no importer or caller

All JS modules are imported by at least one QML file. Internal `_helper` functions are used inside their own file. Functions below are exported but nothing outside tests calls them.

| Item | file:line | Evidence | Risk | Recommendation |
|---|---|---|---|---|
| `fetchModels` | `ProviderService.js:248` | No QML/JS caller; only `tests/js/provider_service.test.js:112`. Replaced by `ProviderCheck.listModels` (used by `ChatSettingsDraft.qml:260`, `config/ProviderChecker.qml`). | low | **Remove** with its helpers below, and the test case. |
| `parseModelIds` | `ProviderService.js:211` | Only caller is `fetchModels` (`:268`). Test export only. | low | **Remove** with `fetchModels`. |
| `modelsRequest` | `ProviderService.js:232` | Only caller is `fetchModels` (`:249`). Test export only. | low | **Remove** with `fetchModels`. (`isHttpUrlAllowed` at `:223` stays: `config/ProvidersPanel.qml:164,177,237` use it.) |
| `scrubSecrets` | `Security.js:238` | No QML/JS caller at all; only `tests/test_security.py` (about 14 uses). Nothing logs through it any more. | low | **Remove** (and the tests) or **keep** if a log/diagnostic feature is planned. Recommend remove: secrets are in KWallet and never logged. |
| `safeHref` | `Security.js:108` | No caller anywhere in app; `tests/test_security.py` only. `MessageText.qml:36` uses `validateUrl` instead. | low | **Remove**. |
| `listed` | `Variants.js:91` | No caller; only `tests/js/variants.test.js:18`. | low | **Remove**. |
| `clear` | `ProviderVariants.js:28` | No caller; only `tests/js/variants.test.js:20`. (`cached` at `:82` is used internally at `:100`.) | low | **Remove** `clear` (and the `_shown` reset if nothing else uses it). |

Test-only but fine to keep: nothing else.

## 3. Helper commands the widget never runs

`kde_ai_helper.py` `commands` dict (`:790-810`) and `kdeaichat/*.py` `COMMANDS`. "Runs" = the command name appears in a QML/JS string passed to a DataSource or `HelperRunner`. No dynamic name building exists (`runServer(command)` in `config/OpenCodeSettings.qml:127` is only called with `opencode_server_start`/`_stop`).

| Command | file:line (def, lines) | Evidence | Risk | Recommendation |
|---|---|---|---|---|
| `toggle_schedule` | `kde_ai_helper.py:224` (12) | No QML caller. Scheduler now saves everything through `save_all_schedules` (`config/SchedulerService.qml:139`). Tested in `test_kde_ai_helper_integration.py`. | low | **Remove** with its test. |
| `update_schedule_history_status` | `:238` (23) | No QML caller, no test. | low | **Remove**. |
| `migrate_history` | `:263` (40) | No QML caller; old per-file history move, replaced by `ChatStore`. Test only. | low | **Remove** with its test. |
| `write_history` | `:305` (8) | No caller, no test. Old history file writer. | low | **Remove**. |
| `read_history` | `:315` (14) | No caller, no test. | low | **Remove**. |
| `delete_schedule` | `:386` (7) | No QML caller; test only. | low | **Remove** with its test. |
| `add_schedule` | `:395` (9) | No QML caller; test only. | low | **Remove** with its test. |
| `get_memory_usage` | `:641` (45) + `_process_memory_kb` `:616` (23) | No QML caller; the memory monitor UI is gone. On the cut list ("Process memory monitor", Phase 6). Test: `test_kde_ai_helper_integration.py:134`. | low | **Remove** with its test and `_read_existing_voice_token` (below). |
| `_read_existing_voice_token` | `:698` (9) | Only caller is `cmd_get_memory_usage` (`:646`). | low | **Remove** with `get_memory_usage`. |
| `get_voice_token` | `:709` (3) | No caller. `VoiceManager.qml` gets its token from the voice daemon (`get_http_token`, `VoiceManager.qml:292`). No test. | low | **Remove**. (`ensure_voice_http_token` stays: used by `setup_venv_services`.) |
| `setup_voice_services` (alias) | `:803` | Alias of `setup_venv_services`; QML uses the `venv` name (`config/VoiceEngine.qml:114`). | low | **Remove** the alias line. |
| `delete_voice_setup` (alias) | `:805` | Alias of `delete_venv_setup`; no QML uses either name. | low | **Remove** the alias line. |
| `delete_venv_setup` | `:511` (64) | No QML/JS caller by either name; the voice settings no longer offer removal. Phase 6 (voice) may want an "uninstall" button. | medium | **Unsure**: remove if Phase 6 does not plan an uninstall; otherwise keep and wire it. |
| `opencode_server_status` | `kdeaichat/opencode_server.py:58`, `:114` | Not run from QML (only `start`/`stop` are). `tests/test_opencode_server.py` covers it. | medium | **Unsure**: probably intended for a future status line; remove if not planned. |
| `pi_bridge_stop` | `kdeaichat/pi_bridge.py:71`, `:82` | Not run from QML: the bridge exits when idle. Covered by `tests/test_pi_bridge.py` and mentioned in the module docstring. | medium | **Keep** (safety valve, tested) or remove with the docstring. |
| `stop_legacy_watchdog` | `:740` | Used (`main.qml:1208`). | high if removed | **Keep: migration.** |

Live and used: `poll_pending_triggers`, `delete_session_schedules`, `setup_scheduler_service`, `save_all_schedules`, `setup_venv_services`, `export_chat`, `pi_bridge_start`, `get_pi_models`, `prepare_chat_dir`, `delete_chat_files`, `opencode_server_start/stop`, `privacy_report` (used by `tests/test_privacy.py` and the privacy flow), `read_legacy_keyfile`, `remove_legacy_keyfile`.

Note on `privacy_report`: no QML runs it (grep of `.qml`/`.js` is empty), only tests; it is described in `CLAUDE.md` as a read-only dry run. Recommend **keep** (diagnostic) but it is technically unused by the widget.

## 4. `main.xml` entries nothing reads

115 entries. A key counts as read if `plasmoid.configuration.<k>`, `configuration.<k>`, `configuration[name]`, `config.<k>` or a bound `cfg_<k>` page property reaches it. Entries `Migration.qml`/`ProviderService.LEGACY`/`privacy.py` need are marked keep.

| Entry | file:line | Evidence | Risk | Recommendation |
|---|---|---|---|---|
| `schedulerAutoStart` | `config/main.xml:314` | Only a `cfg_schedulerAutoStart` alias on a checkbox (`ConfigSchedules.qml:19`). The checkbox state comes from systemd (`AUTO_ENABLED` in `SchedulerService.qml:168`) and `onToggled` calls `setAutoStart` directly. Nothing reads the saved value. | low | **Remove** the entry and the alias (and its use in `tst_config_pages.qml:161,174`). |
| `preselectedChatId` | `:316` | No reference anywhere in code, tests or docs. | low | **Remove**. |
| `preselectedChatName` | `:317` | Same. | low | **Remove**. |
| `voiceTtsModel` | `:335` | No reference anywhere (`voiceTtsModelPath` is the one in use; `voiceSttModel` is read at `VoiceManager.qml:379`). | low | **Remove**. |
| `baseUrl`, `model` | `:16`, `:22` | Not read as `configuration.baseUrl/model` by the app, but `ProviderService.LEGACY["openai"]` (`ProviderService.js:~70`) reads them for the 1.4.0 provider migration. | high | **Keep: migration.** |
| Legacy per-provider `*BaseUrl` / `*Model` (anthropic, groq, deepSeek, miniMax, fireworks, google, openRouter, mistral, cloudflare, nvidia, huggingFace, xai, lmStudio, local, ollama, litellm, maritaca, perplexity) | between `:25` and `:215` | Read only through `ProviderService.LEGACY` / `_legacyEntry` (`ProviderService.js:120-134`) during migration and the `ProvidersPanel.qml:74` pre-migration fallback. | high | **Keep: migration.** |
| `*ApiKey` entries (23 historical key settings incl. `qwenApiKey`, `moonshotApiKey`, `mimoApiKey`, `huggingfaceImageApiKey`, `replicateApiKey`, `stabilityApiKey`, `togetherImageApiKey`, `apiKey`) | various | Read by `Migration.qml:41-77`; map must match `kdeaichat/privacy.py` (tested). | high | **Keep: migration.** |
| `openRouterReferer`, `openRouterTitle` | `:92`, `:95` | Read by `ProviderService._legacyEntry` (`:128-129`). | medium | **Keep: migration.** |
| `customProvidersJson`, `chatSessionsJson`, `walletKeysRevision` | `:304`, `:269`, `:362` | Read by Migration / `ProvidersPanel.qml:85` / `main.qml` Connections. | high | **Keep.** |

No entry from the cut list is left in `main.xml` (`autoRestartPlasmaShell`, `enableMcpTools`, `mcpServersJson`, `sysInfo*`, `enableMemory`, `userMemory`, `enableCompactingContext`, `compactContextAfter`, `desktopSelectionEnabled`, `showInteractiveGuides`, `uiLanguage`, `appearanceMode` are all gone; `tests/test_requested_fixes.py` guards this). No `plasmoid.configuration.<name>` or `cfg_<name>` in the code refers to an undeclared key.

## 5. Stale translations

`translate/plasma_applet_org.kde.plasma.kdeaichat.pot` (last touched at "Label Interface Language as Beta", before 1.4.0):

| Measure | Count |
|---|---|
| Messages in the `.pot` | 216 |
| Not found anywhere in the source (exact text) | **166** |
| Not found even by their first 25 characters (certainly gone) | 163 |
| Distinct `i18n(...)` strings in the source today | 507 |

So the template is stale in both directions: about 3/4 of it is obsolete (Interactive Guides, Schedules Guide, old template editor, memory/system-info, MCP, etc.) and most of today's strings are missing. Seven machine-translated `.po`/`.mo` sets (`de es fr hi pt ru zh_CN`) carry the same obsolete entries. Risk: low. Recommendation: **regenerate** the `.pot` from the source and re-run the `do_translate*.py` scripts at the end of phase 7, rather than editing by hand.

## 6. Files that nothing references, or that belong to cut features

Every file under `contents/` (QML, JS, Python, shell, service, config) is referenced by at least one other file; no orphan component was found. Cut features are all gone from code except the items below.

| Item | file:line | Evidence | Risk | Recommendation |
|---|---|---|---|---|
| `cmd_get_memory_usage` (cut: process monitor) | `kde_ai_helper.py:641` | See section 3. | low | **Remove**. |
| Watchdog cleanup `stop_legacy_watchdog`, `_legacy_watchdog_pids`, `stopLegacyWatchdog` | `kde_ai_helper.py:714-760`, `main.qml:1196-1210`, call `:1868` | Deliberate migration (cut list "Migration" section); tests in `tests/test_legacy_watchdog_cleanup.py`. | high | **Keep: migration** for now. |
| `bench_kokoro.py` | repo root | No reference from code, docs, CI or tests; a hard-coded `python3.13` NVIDIA-libs benchmark script. | low | **Remove** (or move to `scripts/` if still wanted). |
| `store_description.txt` | repo root | Unreferenced; line 47 still advertises "Optional MCP tool support, including built-in web search". | low | **Keep but update** (store text), or remove if the store page is managed elsewhere. |
| `README.md` | lines 17, 22, 51 | Describe the "AI Memory Manager", "Resource & Memory Monitor" and "MCP Tools". | low | **Update** in phase 7 ("README and screenshots describe only what remains"). |
| `.github/assets/image5.png`, `image7.png`, `image10.png` | referenced by `README.md:17,19,22` | Screenshots of the memory manager, "Other" settings (old layout) and the memory monitor: cut or rebuilt features. | low | **Replace/remove** with the README update. |
| `SETUP.md` | `:515-540` (and `:56` "General/Appearance/Shortcuts" tab names) | Documents MCP tools and the old tab layout. | low | **Update**. |
| `user_manual.md` | `:106` | "MCP safety" note for a removed feature. | low | **Update**. |
| `docs/AUDIT_AND_OPENCODE_ROADMAP.md`, `docs/COMPREHENSIVE_AUDIT.md` | `docs/` | Unreferenced by anything; audits of the pre-rebuild code (`COMPREHENSIVE_AUDIT.md:86` discusses `enableCompactingContext`). `CLAUDE.md` still points at COMPREHENSIVE_AUDIT. | low | **Unsure**: archive or delete once phase 7 closes; update the `CLAUDE.md` pointer. |
| `docs/kirigami-formlayout-guide.md`, `docs/plasma-widget-configuration.md`, `docs/qt-layout-attached-properties.md` | `docs/` | Generic reference notes, unreferenced. | low | **Keep** (reference) unless the owner wants them gone. |
| `scripts/dev-opencode-e2e.sh`, `dev-opencode-mock.py`, `dev-pi-e2e.sh`, `dev-pi-mock.py` | `scripts/` | Referenced by `docs/development.md`, `docs/plan/04-gui.md`, `tests/test_pi_bridge.py`. | low | **Keep**. |

## 7. Old code paths inside live functions that cannot run

Only clear cases.

| Item | file:line | Evidence | Risk | Recommendation |
|---|---|---|---|---|
| Plaintext-key fallback `wallet.usable ? "" : cfg.apiKey` | `main.qml:1303-1306` | Reachable only while KWallet is unusable and a pre-migration plaintext key is still in config. Documented as intentional in `CLAUDE.md`. | high | **Keep.** |
| `legacyProviders` fallback in the providers panel | `config/ProvidersPanel.qml:74`, `ProviderService.js:136` | Runs only before migration has written `providersJson`. | high | **Keep: migration.** |
| `ConfigSchedules.qml` `cfg_schedulerAutoStart` alias | `ConfigSchedules.qml:19` | Saves a value nothing reads (section 4). | low | **Remove** with the `main.xml` entry. |
| `think` used before its declaration | `backends/DirectBackend.js:293` | `finish()` (`:291-299`) calls `think.end()` at `:293`; `var think = createThinkSplitter(...)` is declared later at **`:302`**. Works at run time because `var` is hoisted and `finish` is only called after `:302`, but static analysis warns. | low | **Fix later** (move the `var think` above `finish`, or declare `var think = null` first): not a removal. |

No branch for a removed setting remains in `main.qml`, `ConfigChat.qml`, `ConfigConnection.qml` or the `chat/` components (checked: no reference to a cut key survives).

## Summary

| Category | Rows | Low-risk "remove" | Keep / unsure |
|---|---|---|---|
| 1. QML functions/properties | 12 | 3 | 8 keep (test hooks, forwarders, migration), 1 unsure |
| 2. JS functions/exports | 7 | 7 | 0 |
| 3. Helper commands | 16 | 11 (incl. 2 aliases) | 3 unsure (`delete_venv_setup`, `opencode_server_status`, `pi_bridge_stop`), 1 keep (privacy_report), 1 keep: migration |
| 4. `main.xml` entries | 4 removable (+ migration groups kept) | 4 | all migration entries keep |
| 5. i18n strings | 166 of 216 obsolete | regenerate the `.pot` | n/a |
| 6. Files | 11 | 5 (`bench_kokoro.py`, docs/screenshots to update) | 2 unsure (old audit docs) |
| 7. Dead paths in live code | 4 | 1 | 2 keep: migration, 1 later fix (`think`) |

### Low-risk remove list (brief)

- `main.qml`: `fetchingOpenCodeConfig` (+ write in `OpenCodeMode.qml:147`), `fetchingAgentsInProgress` (+ 2 writes, + test line), `configuredSessionSource` forwarder.
- JS: `ProviderService.fetchModels` / `parseModelIds` / `modelsRequest`, `Security.safeHref`, `Security.scrubSecrets`, `Variants.listed`, `ProviderVariants.clear` (and their test cases).
- Helper: `toggle_schedule`, `update_schedule_history_status`, `migrate_history`, `write_history`, `read_history`, `delete_schedule`, `add_schedule`, `get_memory_usage` (+ `_process_memory_kb`, `_read_existing_voice_token`), `get_voice_token`, aliases `setup_voice_services` and `delete_voice_setup` (and their tests).
- `main.xml`: `schedulerAutoStart` (+ the `cfg_` alias), `preselectedChatId`, `preselectedChatName`, `voiceTtsModel`.
- Repo: `bench_kokoro.py`; refresh the `.pot`.

### Unsure

`delete_venv_setup` (may be wanted by Phase 6 for an uninstall button), `opencode_server_status`, `pi_bridge_stop`, `onCustomProvidersJsonChanged` Connections handler, `privacy_report` (only tests run it), the two old audit docs, `store_description.txt`.

### Estimated shrink

- **`main.qml`** (2283 lines): about **6 to 8 lines**. It is already clean; the only dead members are two write-only flags and one forwarder. (Everything else that looked small is live.)
- **`kde_ai_helper.py`** (829 lines): about **250 lines** with the low-risk list (functions: 12 + 23 + 40 + 8 + 14 + 7 + 9 + 23 + 45 + 9 + 3 = 193, plus blank lines and 9 dict lines, about 215 to 225), and about **290 lines** if `delete_venv_setup` (64 lines) is also removed. That takes the file from 829 to about 540 to 610 lines. It is on the shrink-only size allowlist, so the allowlist entry must be lowered.
- Tests: roughly 100 to 150 lines of test code across `test_kde_ai_helper_integration.py`, `test_security.py`, `tests/js/*` would go with them.


## Removal result

Removed (owner-approved): all low-risk rows above, plus `schedulerAutoStart` (setting and `cfg_` alias), `delete_venv_setup`, `privacy_report`, `opencode_server_status`, `pi_bridge_stop` (as a command), `docs/AUDIT_AND_OPENCODE_ROADMAP.md`, `docs/COMPREHENSIVE_AUDIT.md`, `bench_kokoro.py`. `kde_ai_helper.py`: 829 to 532 lines; `main.qml`: 2283 to 2280. The size allowlist is lowered to match. Migration items were left untouched. `think` is now declared above `finish()` in `backends/DirectBackend.js`. Guards: `tests/test_dead_code_removed.py`.

Differences from the list:
- **`ProviderVariants.clear` kept.** Four QML tests (`tst_variants_modes`, `tst_chat_info`, `tst_composer_bar`, `tst_providers_panel`) call it to reset the per-provider cache between tests; the scan only looked at app code. It is a test hook.
- **The "Start when I log in" checkbox in `ConfigSchedules.qml` kept.** It is not dead: it enables/disables the systemd unit through `SchedulerService.setAutoStart` and shows the systemd state. Only the unused `schedulerAutoStart` setting and its `cfg_` alias were removed. `tst_config_pages.qml` now checks the checkbox directly.
- **`pi_bridge_stop`**: no longer a helper command, but `cmd_pi_bridge_stop` stays in `kdeaichat/pi_bridge.py` as an unregistered function. `tests/test_pi_bridge.py` uses it in the bridge fixture and `scripts/dev-pi-e2e.sh` calls it through `python3 -c`.
- **`opencode_server_status`**: removed; its test assertion now checks `healthy()` and `find_binary()`.
- **`privacy_report`**: the command and the read-only scanner (`report`, `scan_appletsrc`, `scan_kdeaichatrc`) are removed from `kdeaichat/privacy.py` with their tests. The key map, `read_legacy_keyfile` and `remove_legacy_keyfile` stay (migration). `CLAUDE.md` is ignored by version control and is not part of this branch: its lines about `privacy_report` and `docs/COMPREHENSIVE_AUDIT.md` must be edited by hand in the main checkout.

Translations: `translate/files.txt` listed only 21 of the 57 files that call `i18n`; it now lists all of them. `translate/plasma_applet_org.kde.plasma.kdeaichat.pot` was regenerated with `xgettext --from-code=UTF-8 -C -kde -ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 -ktr2i18n:1 -kI18N_NOOP:1 -kI18N_NOOP2:1c,2 -f translate/files.txt` (522 messages; there was no extraction script in the repo). The machine-translation scripts were not run and no `.po`/`.mo` file was touched, so the seven locales still carry the old, mostly obsolete entries until that is done at the end of phase 7.

TODO (phase 7): replace the screenshots `.github/assets/image5.png` (memory manager), `image7.png` (old "Other" tab) and `image10.png` (memory monitor). The README rows for `image5` and `image10` were removed and the `image7` row text reworded; the PNG files are still there.

### Cut-list check (`docs/plan/07-cut-list.md`)

Searched `contents/`, `main.xml`, the regenerated `.pot`, `README.md`, `SETUP.md`, `user_manual.md`, `store_description.txt`, `VOICE_SETUP.md`, `tests/` and `scripts/` for every identifier in the list (watchdog, MCP, `sysInfo*`, memory, compaction, memory monitor, screen-region capture, desktop selection, open in terminal, guides, `uiLanguage`, `appearanceMode`, `popupIsDark`). Result: every row is gone from the code, `main.xml`, the `.pot` and the docs. What matches are only the deliberate watchdog cleanup (`stop_legacy_watchdog`, `stopLegacyWatchdog`, its test) and guard tests (`test_requested_fixes.py`, `test_legacy_watchdog_cleanup.py`). The old `.po`/`.mo` files still contain the cut strings (see above), and the three screenshots above still show cut features.
