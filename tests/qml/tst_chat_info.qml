// The Chat info panel (ChatSettingsDialog.qml): this chat's totals summed from
// per-message usage, and the per-chat settings it still saves.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui

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
            chat.calls = [];
            chat.currentSessionId = "a";
            chat.currentSessionTitle = "Trip planning";
            chat.openCodeMode = false;
            chat.plasmoid = {configuration: {
                provider: "openai",
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
            compare(o.source, "provider");
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

        function test_09_agent_modes_keep_their_settings() {
            openPanel();
            var form = findForm();
            dialog.draft.setMode("opencode");
            wait(20);
            verify(!form.systemArea.visible, "OpenCode has its own instructions");
            verify(form.cwdField.visible);
            form.cwdField.text = "/home/me/project";
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.source, "opencode");
            compare(o.openCodeWorkspaceCwd, "/home/me/project");
            compare(o.openCodeAgent, "");
            openPanel();
            dialog.draft.setMode("pi");
            wait(20);
            verify(form.cwdField.visible);
            dialog.draft.piThinking = "high";
            dialog._save();
            o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.source, "pi");
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
    }
}
