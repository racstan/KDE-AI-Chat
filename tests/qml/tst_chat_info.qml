// The Chat info panel (ChatSettingsDialog.qml): this chat's totals summed from
// per-message usage, and the per-chat settings it still saves.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui
import "../../org.kde.plasma.kdeaichat/contents/ui/ProviderVariants.js" as ProviderVariants

Item {
    id: root
    width: 760
    height: 700

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    // The provider's /models answer for the variant tests.
    property var listBody: ({data: [
        {id: "gpt-5", reasoning: {supported_efforts: ["low", "medium", "high"]}},
        {id: "gpt-4o"}]})
    function makeXhr() {
        var x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = function(method, url) { x.method = method; x.url = url; };
        x.setRequestHeader = function(k, v) { x.headers[k] = v; };
        x.send = function() {
            Qt.callLater(function() {
                x.status = 200;
                x.responseText = JSON.stringify(root.listBody);
                x.readyState = 4;
                x.onreadystatechange();
            });
        };
        return x;
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    Ui.ChatSettingsDialog {
        id: dialog
        rootRef: chat
        hostItem: root
    }

    HarnessTestCase {
        name: "ChatInfo"

        readonly property real created: new Date(2026, 9, 20, 9, 30).getTime()
        readonly property real active: new Date(2026, 9, 25, 14, 5).getTime()

        function init() {
            dialog.close();
            ProviderVariants.clear();
            chat.openCodeVariants = ({});
            chat.piThinkingModels = ({});
            dialog.draft.xhrFactory = null;
            chat.calls = [];
            chat.currentSessionId = "a";
            chat.currentSessionTitle = "Trip planning";
            chat.openCodeMode = false;
            chat.plasmoid = {configuration: {
                provider: "openai",
                perChatModelSettings: true,
                perChatPriority: "chat",
                providersJson: JSON.stringify([
                    {id: "openai", name: "OpenAI", type: "openai-compat", baseUrl: "", model: "gpt-4o"},
                    {id: "ollama", name: "Ollama", type: "openai-compat", baseUrl: "", model: "llama3"}
                ])
            }};
            chat.sessions = [{value: "a", text: "Trip planning", createdAt: created, updatedAt: active,
                              chatProvider: "", chatModel: "gpt-4o-mini", responseLength: 2,
                              chatSystemPromptEnabled: true, chatSystemPrompt: "Be brief."}];
            chat.messages = [
                {role: "user", content: "Where?", at: created},
                {role: "assistant", model: "gpt-4o", content: "Lisbon", at: created + 1000, tokens: {input: 30, output: 212}, cost: 0.001},
                {role: "user", content: "And then?", at: created + 2000},
                {role: "assistant", model: "gpt-4o", content: "Porto", at: created + 3000, tokens: {input: 1260, output: 14}, cost: 0.0005},
                {role: "assistant", model: "claude-sonnet", content: "Faro", at: active, tokens: {input: 7, output: 1}}
            ];
            wait(10);
        }

        function find(item, name) {
            if (item.objectName === name) return item;
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++) {
                var found = find(kids[i], name);
                if (found) return found;
            }
            return null;
        }

        function value(name) {
            var label = find(dialog, name);
            verify(label !== null, name + " exists");
            return label;
        }

        function openPanel() {
            dialog.toggleForSession("a");
            verify(dialog.visible);
            wait(50);
        }

        function findForm() {
            function walk(item) {
                if (item.hasOwnProperty("providerCombo") && item.hasOwnProperty("draft")) return item;
                var kids = item.children || [];
                for (var i = 0; i < kids.length; i++) {
                    var f = walk(kids[i]);
                    if (f) return f;
                }
                return null;
            }
            var f = walk(dialog.contentItem ? dialog.contentItem : dialog);
            return f;
        }

        function test_01_totals_are_summed_from_the_messages() {
            openPanel();
            compare(value("messagesValue").text, "5");
            compare(value("inputValue").text, "1,297");
            compare(value("outputValue").text, "227");
            compare(value("costValue").text, "$0.00150");
            verify(value("costValue").visible);
            compare(value("modelsValue").text, "gpt-4o\nclaude-sonnet");
            compare(value("createdValue").text, new Date(created).toLocaleString(Qt.locale(), Locale.ShortFormat));
            compare(value("lastValue").text, new Date(active).toLocaleString(Qt.locale(), Locale.ShortFormat));
            verify(!value("unreportedNote").visible, "every reply reported usage");
            screenshot(root, "chat-info");
        }

        function test_02_nothing_is_estimated_when_the_provider_gave_no_usage() {
            chat.messages = [
                {role: "user", content: "Hi", at: created},
                {role: "assistant", model: "local-model", content: "Hello", at: created + 1},
                {role: "assistant", model: "local-model", content: "Again", at: created + 2, tokens: {input: 10, output: 4}}
            ];
            openPanel();
            compare(value("inputValue").text, "10");
            compare(value("outputValue").text, "4");
            verify(!value("costValue").visible, "no cost reported, no cost row");
            verify(value("unreportedNote").visible);
            verify(value("unreportedNote").text.indexOf("1 reply") >= 0, value("unreportedNote").text);
            chat.messages = [{role: "assistant", model: "local-model", content: "Hello", at: created + 1}];
            wait(20);
            compare(value("inputValue").text, "Not reported");
            compare(value("outputValue").text, "Not reported");
            screenshot(root, "chat-info-unreported");
        }

        function test_03_an_empty_chat_shows_zeros() {
            chat.messages = [];
            openPanel();
            compare(value("messagesValue").text, "0");
            compare(value("inputValue").text, "0");
            verify(!value("costValue").visible);
            verify(!value("modelsValue").visible);
        }

        function test_04_totals_follow_new_messages() {
            openPanel();
            compare(value("outputValue").text, "227");
            chat.messages = chat.messages.concat([{role: "assistant", model: "gpt-4o", content: "More", at: active + 5, tokens: {input: 3, output: 100}, cost: 0.0104}]);
            tryCompare(value("outputValue"), "text", "327");
            compare(value("inputValue").text, "1,300");
            compare(value("messagesValue").text, "6");
            compare(value("costValue").text, "$0.012");
        }

        function test_05_shows_the_chats_settings() {
            openPanel();
            var form = findForm();
            verify(form !== null, "settings form");
            compare(form.modelCombo.editText, "gpt-4o-mini");
            compare(form.systemCheck.checked, true);
            compare(form.systemArea.text, "Be brief.");
            compare(form.responseLengthCombo.currentIndex, 2);
            compare(form.providerCombo.currentIndex, 0);
            verify(!dialog.draft.dirty, "loading is not an edit");
        }

        function test_06_edits_are_saved_with_apply() {
            openPanel();
            var form = findForm();
            form.modelCombo.forceActiveFocus();
            form.modelCombo.editText = "gpt-4.1";
            form.providerCombo.currentIndex = 2;
            form.providerCombo.activated(2);
            compare(dialog.draft.provider, "ollama");
            form.modelCombo.forceActiveFocus();
            form.modelCombo.editText = "llama3.2";
            form.systemArea.text = "Answer in French.";
            form.responseLengthCombo.currentIndex = 4;
            form.responseLengthCombo.activated(4);
            verify(dialog.draft.dirty);
            compare(chat.calls.length, 0, "nothing is saved before Apply");
            dialog._save();
            var call = chat.calls[chat.calls.length - 1];
            compare(call.name, "overrides");
            compare(call.args[0], "a");
            var o = call.args[1];
            verify(!("source" in o), "the panel never writes a chat's mode");
            compare(o.chatProvider, "ollama");
            compare(o.chatModel, "llama3.2");
            compare(o.chatSystemPrompt, "Answer in French.");
            compare(o.chatSystemPromptEnabled, true);
            compare(o.responseLength, 4);
            verify(!dialog.visible, "Apply closes the panel");
        }

        function test_07_choosing_the_default_provider_saves_no_override() {
            openPanel();
            var form = findForm();
            form.providerCombo.currentIndex = 1;
            form.providerCombo.activated(1);
            compare(dialog.draft.provider, "openai");
            dialog._save();
            compare(chat.calls[chat.calls.length - 1].args[1].chatProvider, "", "the global provider is the default, not an override");
        }

        function test_08_reset_goes_back_to_the_saved_settings() {
            openPanel();
            var form = findForm();
            form.systemArea.text = "Changed";
            form.responseLengthCombo.currentIndex = 1;
            form.responseLengthCombo.activated(1);
            verify(dialog.draft.dirty);
            dialog.draft.reset();
            wait(20);
            compare(form.systemArea.text, "Be brief.");
            compare(form.responseLengthCombo.currentIndex, 2);
            verify(!dialog.draft.dirty);
        }

        function test_09a_working_folder_in_every_mode() {
            for (const source of ["provider", "opencode", "pi"]) {
                chat.sessions = [{value: "a", text: "Trip planning", source: source}];
                openPanel();
                var form = findForm();
                verify(visibleIn(form.cwdField), source);
                compare(form.cwdField.placeholderText, "No workspace");
                compare(form.cwdField.text, "");
                form.cwdField.text = "/home/me/" + source;
                dialog._save();
                compare(chat.calls[chat.calls.length - 1].args[1].openCodeWorkspaceCwd, "/home/me/" + source);
            }
        }

        function test_09_agent_modes_keep_their_settings() {
            chat.sessions = [{value: "a", text: "Trip planning", source: "opencode"}];
            openPanel();
            var form = findForm();
            compare(dialog.draft.mode, "opencode");
            verify(!form.systemArea.visible, "OpenCode has its own instructions");
            verify(form.cwdField.visible);
            form.cwdField.text = "/home/me/project";
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            verify(!("source" in o));
            compare(o.openCodeWorkspaceCwd, "/home/me/project");
            chat.sessions = [{value: "a", text: "Trip planning", source: "pi", ownModel: true, piModel: "qwen"}];
            openPanel();
            dialog.draft.load("a");
            wait(20);
            compare(dialog.draft.mode, "pi");
            verify(form.cwdField.visible);
            dialog.draft.piThinking = "high";
            dialog._save();
            o = chat.calls[chat.calls.length - 1].args[1];
            verify(!("source" in o));
            compare(o.piThinking, "high");
        }

        function test_10_toggle_and_escape_close_the_panel() {
            dialog.toggleForSession("a");
            verify(dialog.visible);
            dialog.toggleForSession("a");
            verify(!dialog.visible);
            dialog.toggleForSession("a");
            verify(dialog.visible);
            dialog.forceActiveFocus();
            keyClick(Qt.Key_Escape);
            verify(!dialog.visible);
        }

        function test_11_the_panel_follows_the_current_chat() {
            chat.sessions = chat.sessions.concat([{value: "b", text: "Other", chatModel: "other-model", chatSystemPrompt: "x"}]);
            openPanel();
            var form = findForm();
            chat.currentSessionId = "b";
            chat.currentSessionTitle = "Other";
            tryCompare(form.modelCombo, "editText", "other-model");
            compare(dialog.draft.sessionId, "b");
        }

        function test_12_a_failed_model_list_says_so_without_losing_the_model() {
            openPanel();
            var form = findForm();
            tryVerify(() => dialog.draft.status !== "");
            verify(dialog.draft.statusError, "no server URL: " + dialog.draft.status);
            compare(form.modelCombo.editText, "gpt-4o-mini");
        }

        // ── Per-chat model settings are opt-in ───────────────────────────────

        function configure(extra) {
            var c = Object.assign({}, chat.plasmoid.configuration, extra);
            chat.plasmoid = {configuration: c};
            wait(20);
        }

        function visibleIn(item) {
            // Visible all the way up to the panel.
            for (var n = item; n && n !== dialog; n = n.parent) {
                if (!n.visible) return false;
            }
            return true;
        }

        function test_13_the_default_hides_the_model_controls_and_shows_main_settings() {
            configure({perChatModelSettings: false});
            openPanel();
            var form = findForm();
            verify(!visibleIn(form.providerCombo), "no provider choice");
            verify(!visibleIn(form.modelCombo), "no model choice");
            verify(!visibleIn(find(dialog, "ownModelCheck")), "no per-chat switch in the chat either");
            verify(visibleIn(form.systemArea), "chat instructions are not a model setting");
            verify(visibleIn(form.responseLengthCombo));
            compare(value("effectiveLine").text, "Using OpenAI \u00b7 gpt-4o (from main settings)");
            verify(value("effectiveNote").visible);
            verify(value("effectiveNote").text.indexOf("Every chat uses the main settings") === 0);
            screenshot(root, "chat-info-main-settings");
            // Apply keeps the model settings the chat has, and writes none.
            form.systemArea.text = "Only this changed.";
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.chatSystemPrompt, "Only this changed.");
            verify(!("chatModel" in o) && !("source" in o) && !("chatProvider" in o) && !("ownModel" in o), JSON.stringify(Object.keys(o)));
            compare(chat.sessions[0].chatModel, "gpt-4o-mini", "kept in storage");
        }

        function test_14_switch_on_shows_the_chats_own_settings_and_where_they_come_from() {
            openPanel();
            var form = findForm();
            verify(visibleIn(form.providerCombo));
            verify(visibleIn(form.modelCombo));
            verify(visibleIn(find(dialog, "ownModelCheck")));
            compare(find(dialog, "ownModelCheck").checked, true, "the chat has its own model: legacy chats count");
            compare(value("effectiveLine").text, "Using OpenAI \u00b7 gpt-4o-mini (from this chat's settings)");
            verify(!value("effectiveNote").visible);
            screenshot(root, "chat-info-chat-settings");
        }

        function test_15_main_settings_win_is_said_and_applied() {
            configure({perChatPriority: "main"});
            openPanel();
            compare(value("effectiveLine").text, "Using OpenAI \u00b7 gpt-4o (from main settings)");
            verify(value("effectiveNote").visible);
            verify(value("effectiveNote").text.indexOf("Main settings win") === 0);
        }

        function test_16_a_chat_without_own_settings_can_opt_in() {
            chat.sessions = [{value: "a", text: "Trip planning", createdAt: created, updatedAt: active, source: "provider"}];
            openPanel();
            var form = findForm();
            var check = find(dialog, "ownModelCheck");
            compare(check.checked, false, "a source alone is not an override");
            verify(!visibleIn(form.providerCombo));
            compare(value("effectiveLine").text, "Using OpenAI \u00b7 gpt-4o (from main settings)");
            check.toggled();
            check.checked = true;
            check.toggled();
            tryVerify(() => visibleIn(form.providerCombo));
            verify(dialog.draft.dirty);
            form.providerCombo.currentIndex = 2;
            form.providerCombo.activated(2);
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.ownModel, true);
            compare(o.chatProvider, "ollama");
            compare(value("effectiveLine").text, "Using Ollama \u00b7 llama3 (from this chat's settings)");
        }

        function test_17_unchecking_keeps_the_settings_but_stops_using_them() {
            openPanel();
            var check = find(dialog, "ownModelCheck");
            check.checked = false;
            check.toggled();
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.ownModel, false);
            verify(!("chatModel" in o), "the model stays as it was");
            compare(chat.sessions[0].chatModel, "gpt-4o-mini");
            compare(value("effectiveLine").text, "Using OpenAI \u00b7 gpt-4o (from main settings)");
        }

        function test_18_agent_modes_in_the_line_and_the_panel_follows_the_settings() {
            // Main settings: OpenCode + OpenCode Zen; this chat: Pi + OpenAI. The chat stays a Pi chat.
            configure({useOpenCode: true, openCodeProvider: "opencode", openCodeModel: "zen-x", piProvider: "ollama", piModel: "qwen"});
            chat.sessions = [{value: "a", text: "Trip planning", createdAt: created, updatedAt: active, ownModel: true,
                              source: "pi", piProvider: "openai", piModel: "gpt-y"}];
            openPanel();
            compare(value("effectiveLine").text, "Using Pi \u00b7 openai \u00b7 gpt-y (from this chat's settings)");
            configure({perChatPriority: "main"});
            compare(value("effectiveLine").text, "Using Pi \u00b7 ollama \u00b7 qwen (from main settings)");
            configure({perChatModelSettings: false, perChatPriority: "chat"});
            compare(value("effectiveLine").text, "Using Pi \u00b7 ollama \u00b7 qwen (from main settings)");
            // The working folder is offered because this is an agent chat.
            verify(visibleIn(findForm().cwdField));
            configure({perChatModelSettings: true});
            compare(value("effectiveLine").text, "Using Pi \u00b7 openai \u00b7 gpt-y (from this chat's settings)");
        }

        // ── A chat keeps its mode ───────────────────────────────────────────

        function test_19_the_mode_is_shown_read_only() {
            for (const m of [["provider", "direct provider"], ["opencode", "OpenCode"], ["pi", "Pi"]]) {
                chat.sessions = [{value: "a", text: "Trip planning", source: m[0]}];
                configure({useOpenCode: m[0] !== "opencode"});
                openPanel();
                dialog.draft.load("a");
                wait(20);
                compare(value("modeLabel").text, "Mode: " + m[1] + " (set when the chat was started)");
                verify(visibleIn(value("modeLabel")));
                compare(dialog.draft.mode, m[0], "the main mode does not decide it");
                if (m[0] === "pi")
                    screenshot(root, "chat-info-mode-readonly");
                dialog._save();
                verify(!("source" in chat.calls[chat.calls.length - 1].args[1]), "save never writes the mode");
            }
            // Even when a draft's mode were changed, saving does not write it.
            chat.sessions = [{value: "a", text: "Trip planning", source: "pi", ownModel: true}];
            openPanel();
            dialog.draft.mode = "provider";
            dialog._save();
            verify(!("source" in chat.calls[chat.calls.length - 1].args[1]));
        }

        // ── Empty instructions are off ──────────────────────────────────────

        function test_20_a_chat_without_instructions_has_the_box_unchecked() {
            openPanel();
            for (const text of [undefined, "", "   \n "]) {
                chat.sessions = [{value: "a", text: "Trip planning", source: "provider", chatSystemPrompt: text}];
                dialog.draft.load("a");
                wait(20);
                var form = findForm();
                compare(form.systemCheck.checked, false, JSON.stringify(text));
                verify(!form.systemArea.enabled, "the text box waits for the box");
            }
            screenshot(root, "chat-info-no-instructions");
            chat.sessions = [{value: "a", text: "Trip planning", source: "provider", chatSystemPrompt: "Be brief.", chatSystemPromptEnabled: true}];
            dialog.draft.load("a");
            wait(20);
            compare(findForm().systemCheck.checked, true);
            chat.sessions = [{value: "a", text: "Trip planning", source: "provider", chatSystemPrompt: "Be brief.", chatSystemPromptEnabled: false}];
            dialog.draft.load("a");
            wait(20);
            compare(findForm().systemCheck.checked, false, "switched off by the user, text kept");
            compare(findForm().systemArea.text, "Be brief.");
        }

        function test_21_turning_it_on_with_no_text_sends_and_saves_nothing() {
            chat.sessions = [{value: "a", text: "Trip planning", source: "provider"}];
            openPanel();
            var form = findForm();
            form.systemCheck.checked = true;
            verify(dialog.draft.systemEnabled);
            verify(form.systemArea.enabled);
            wait(50);
            screenshot(root, "chat-info-instructions-on-empty");
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            verify(!("chatSystemPrompt" in o) && !("chatSystemPromptEnabled" in o), "no override saved: " + JSON.stringify(o));
            // Blank text counts as empty.
            openPanel();
            form = findForm();
            form.systemCheck.checked = true;
            form.systemArea.text = "  \n ";
            dialog._save();
            o = chat.calls[chat.calls.length - 1].args[1];
            verify(!("chatSystemPrompt" in o) && !("chatSystemPromptEnabled" in o), JSON.stringify(o));
            // Real text is saved and switched on.
            openPanel();
            form = findForm();
            form.systemCheck.checked = true;
            form.systemArea.text = "Be formal.";
            dialog._save();
            o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.chatSystemPrompt, "Be formal.");
            compare(o.chatSystemPromptEnabled, true);
        }

        function test_22_clearing_the_instructions_saves_them_as_empty_and_leaves_the_flag() {
            chat.sessions = [{value: "a", text: "Trip planning", source: "provider", chatSystemPrompt: "Old.", chatSystemPromptEnabled: true}];
            openPanel();
            var form = findForm();
            compare(form.systemCheck.checked, true);
            form.systemArea.text = "";
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.chatSystemPrompt, "");
            compare(o.chatSystemPromptEnabled, true, "the default; nothing special is switched");
        }
        // --- Variants (reasoning levels): a picker only when the model has any ---

        function variantSetup(session) {
            configure({providersJson: JSON.stringify([
                {id: "openai", name: "OpenAI", type: "openai-compat", baseUrl: "https://oa.example/v1", model: "gpt-4o"}])});
            chat.walletApiKeys = {"openai": "k"};
            dialog.draft.xhrFactory = root.makeXhr;
            chat.sessions = [Object.assign({value: "a", text: "Trip planning"}, session)];
        }

        function test_23_a_direct_model_with_variants_gets_a_picker_and_the_choice_is_saved() {
            variantSetup({source: "provider", ownModel: true, chatModel: "gpt-5"});
            openPanel();
            var form = findForm();
            tryVerify(function() { return form.variantPicker.visible; }, 3000, "gpt-5 reports low, medium, high");
            compare(form.variantPicker.count, 4, "Default and the three levels");
            compare(form.variantPicker.currentText, "Default");
            form.variantPicker.currentIndex = 3;
            form.variantPicker.activated(3);
            compare(dialog.draft.variant, "high");
            verify(dialog.draft.dirty);
            // (Earlier tests clicked this box, which detaches its binding; show the draft's state.)
            find(dialog, "ownModelCheck").checked = dialog.draft.ownModel;
            screenshot(root, "chat-info-variant");
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.chatVariant, "high");
            compare(o.chatModel, "gpt-5");
            // Reopened, the stored id is what the picker shows.
            openPanel();
            form = findForm();
            tryVerify(function() { return form.variantPicker.visible && form.variantPicker.currentText === "High"; }, 3000);
        }

        function test_24_a_model_without_variants_has_no_picker_and_another_model_drops_the_variant() {
            variantSetup({source: "provider", ownModel: true, chatModel: "gpt-4o", chatVariant: "high"});
            openPanel();
            var form = findForm();
            tryVerify(function() { return dialog.draft.modelCandidates.length > 0; }, 3000);
            wait(50);
            verify(!form.variantPicker.visible, "gpt-4o reports none: no picker");
            // Typing a model that has variants shows the picker, with no variant chosen.
            form.modelCombo.forceActiveFocus();
            form.modelCombo.editText = "gpt-5";
            tryVerify(function() { return form.variantPicker.visible; }, 3000);
            compare(dialog.draft.variant, "", "the old model's variant is not kept");
            dialog._save();
            compare(chat.calls[chat.calls.length - 1].args[1].chatVariant, "");
        }

        function test_25_a_provider_that_reports_nothing_never_shows_a_picker() {
            root.listBody = {data: [{id: "gpt-5"}, {id: "gpt-4o"}]};
            variantSetup({source: "provider", ownModel: true, chatModel: "gpt-5"});
            openPanel();
            var form = findForm();
            tryVerify(function() { return dialog.draft.modelCandidates.length > 0; }, 3000);
            wait(50);
            verify(!form.variantPicker.visible);
            root.listBody = {data: [{id: "gpt-5", reasoning: {supported_efforts: ["low", "medium", "high"]}}, {id: "gpt-4o"}]};
        }

        function test_26_opencode_variants_come_from_the_servers_catalogue() {
            variantSetup({source: "opencode", ownModel: true, openCodeProvider: "openrouter", openCodeModel: "auto", openCodeVariant: "low"});
            chat.openCodeVariants = {"openrouter/auto": ["low", "high"], "openrouter/free": ["low"]};
            openPanel();
            var form = findForm();
            verify(form.variantPicker.visible);
            compare(form.variantPicker.count, 3);
            compare(form.variantPicker.currentText, "Low");
            form.variantPicker.currentIndex = 2;
            form.variantPicker.activated(2);
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.openCodeVariant, "high");
            compare(o.chatVariant, "", "another mode's field is not touched");
            // A model the catalogue gives no variants for: no picker.
            chat.openCodeVariants = {"openrouter/free": ["low"]};
            dialog.draft.load("a");
            wait(20);
            verify(!form.variantPicker.visible);
        }

        function test_27_pi_thinking_picker_only_for_a_thinking_model() {
            variantSetup({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5", piThinking: "high"});
            chat.piThinkingModels = {"openai/gpt-5": true};
            openPanel();
            var form = findForm();
            var thinking = find(dialog, "thinkingPicker");
            verify(thinking !== null && thinking.visible, "gpt-5 thinks");
            compare(thinking.currentText, "High");
            compare(thinking.count, 8, "Default and Pi's seven levels");
            thinking.currentIndex = 4;
            thinking.activated(4);
            dialog._save();
            compare(chat.calls[chat.calls.length - 1].args[1].piThinking, "medium");
            chat.piThinkingModels = {};
            dialog.draft.load("a");
            wait(20);
            verify(!thinking.visible, "a model Pi does not mark as thinking: no picker");
        }
    }
}
