// Slash commands in the message box (chat/Commands.js, CommandRunner.qml,
// TemplateSuggestions.qml): "/" lists the commands before the templates,
// Up/Down move in the list, a command is run and never sent, and text that is
// no command is sent as it is.
import QtQuick
import QtQuick.Window
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 420

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    function makeXhr() {
        var x = {headers: {}, readyState: 0, status: 0, responseText: ""};
        x.open = function(method, url) { x.method = method; x.url = url; };
        x.setRequestHeader = function(k, v) { x.headers[k] = v; };
        x.send = function() {
            Qt.callLater(function() {
                x.status = 200;
                x.responseText = JSON.stringify({data: [{id: "acme/chat-big"}, {id: "acme/chat-small"}, {id: "nemotron-3.5-bolt-e4b"}]});
                x.readyState = 4;
                x.onreadystatechange();
            });
        };
        return x;
    }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    Chat.ChatView {
        id: view
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 120
        chat: chat
    }

    Chat.Composer {
        id: composer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        chat: chat
    }

    HarnessTestCase {
        id: tc
        name: "Commands"

        readonly property var templates: [{name: "fix", prompt: "Fix this code:"}, {name: "summarize", prompt: "Summarise the following:"}]

        function calls(name) {
            return chat.calls.filter(function(c) { return c.name === name; });
        }
        function type(text) {
            for (var i = 0; i < text.length; i++)
                keyClick(text.charAt(i));
        }
        function setup(session, config) {
            chat.plasmoid = {configuration: Object.assign({
                provider: "nvidia",
                perChatModelSettings: true,
                providersJson: JSON.stringify([{id: "nvidia", name: "NVIDIA NIM", type: "openai-compat", baseUrl: "https://nim.example/v1", model: "acme/chat-big"}])
            }, config || {})};
            chat.walletApiKeys = {"nvidia": "good"};
            chat.sessions = [Object.assign({value: "a", text: "Chat", source: "provider"}, session || {})];
            chat.currentSessionId = "a";
        }

        function init() {
            chat.calls = [];
            chat.loading = false;
            chat.chatInputText = "";
            chat.piThinkingModels = ({});
            chat.messages = [{role: "user", content: "First", time: "10:00"}, {role: "assistant", model: "m", content: "Reply", time: "10:00"}];
            chat.promptTemplates = templates;
            composer.picker.xhrFactory = root.makeXhr;
            composer.picker.close();
            setup({ownModel: true, chatProvider: "nvidia", chatModel: "nemotron-3.5-bolt-e4b"});
            view.list.clearSelection();
            composer.input.text = "";
            chat.focusInput();
            tryVerify(() => composer.input.activeFocus);
        }

        function names() {
            return composer.suggestions.entries.map(function(e) { return e.kind + ":" + e.name; });
        }
        function notice() { return findChild(composer, "statusText").text; }

        function test_1_slash_lists_commands_before_templates() {
            keyClick("/");
            tryVerify(() => composer.suggestions.visible, 1000);
            compare(names().join(" "), "command:model command:new command:mode command:image command:remember command:memories template:fix template:summarize", "/variant is not offered: no variants");
            wait(300);
            screenshot(root.Window.window.contentItem, "commands-list");
        }

        function test_2_up_down_move_in_the_list_not_in_the_messages() {
            keyClick("/");
            tryVerify(() => composer.suggestions.visible, 1000);
            keyClick(Qt.Key_Down);
            compare(composer.suggestions.current, 1);
            keyClick(Qt.Key_Down);
            compare(composer.suggestions.current, 2);
            keyClick(Qt.Key_Up);
            compare(composer.suggestions.current, 1);
            compare(view.list.selectedIndex, -1, "no message was selected");
            keyClick(Qt.Key_Tab);
            compare(composer.input.text, "/new", "Tab completes");
        }

        function test_3_new_creates_a_chat_and_is_not_sent() {
            type("/new");
            keyClick(Qt.Key_Return);
            compare(calls("create").length, 1);
            compare(calls("create")[0].args[0], true);
            compare(calls("send").length, 0);
            compare(composer.input.text, "");
            compare(notice(), "Started a new chat.");
        }

        function test_4_new_with_an_argument_is_refused_and_kept() {
            type("/new now");
            keyClick(Qt.Key_Return);
            compare(calls("create").length, 0);
            compare(calls("send").length, 0);
            compare(composer.input.text, "/new now");
            compare(notice(), "/new takes no argument.");
        }

        function test_5_model_alone_opens_the_picker() {
            type("/model");
            keyClick(Qt.Key_Return);
            tryVerify(() => composer.picker.opened, 2000);
            compare(calls("send").length, 0);
            compare(composer.input.text, "");
            composer.picker.close();
        }

        function test_6_model_with_an_argument_lists_the_models_and_applies_the_choice() {
            type("/model ");
            tryVerify(() => composer.suggestions.entries.length === 3, 3000, "the live list: " + names().join());
            type("small");
            tryVerify(() => composer.suggestions.entries.length === 1, 1000);
            compare(composer.suggestions.entries[0].name, "acme/chat-small");
            keyClick(Qt.Key_Return);
            compare(calls("send").length, 0);
            compare(composer.input.text, "");
            compare(calls("overrides").length, 1);
            compare(chat.effectiveConfig("a").model, "acme/chat-small");
            // The chat has messages, so the switch says what it costs (tst_model_switch_notice.qml).
            compare(notice(), "Switching models starts the provider's cache over, so the next message may use more input tokens.");
        }

        function test_7_model_with_an_unlisted_name_applies_it_as_typed() {
            type("/model my-own-model");
            keyClick(Qt.Key_Return);
            compare(chat.effectiveConfig("a").model, "my-own-model");
            compare(calls("send").length, 0);
        }

        function test_8_model_respects_the_per_chat_switch() {
            setup({source: "provider"}, {perChatModelSettings: false});
            type("/model ");
            // Not the current model alone: one line saying how to turn the switch on.
            tryVerify(() => composer.suggestions.entries.length === 1, 1000);
            compare(composer.suggestions.entries[0].kind, "notice");
            type("acme/chat-small");
            compare(composer.suggestions.entries[0].kind, "notice");
            wait(100);
            screenshot(composer.suggestions.contentItem, "commands-model-per-chat-off");
            // Title on its own line, the reason below it using the whole width.
            var title = findChild(composer.suggestions.contentItem, "noticeTitle");
            var text = findChild(composer.suggestions.contentItem, "noticeText");
            verify(title.visible && text.visible);
            verify(text.y >= title.y + title.height - 1, "the reason is below the title");
            verify(text.width > composer.suggestions.width * 0.8, "not squeezed: " + text.width);
            verify(text.lineCount <= 3, "a few lines, not a word per line: " + text.lineCount);
            keyClick(Qt.Key_Return);
            compare(calls("overrides").length, 0, "nothing is written");
            compare(calls("send").length, 0);
            compare(calls("openSettings").length, 1, "Enter opens the settings");
            verify(notice().indexOf("Every chat uses the main settings") === 0, notice());
        }

        function test_9_variant_is_offered_only_when_the_model_has_variants() {
            keyClick("/");
            tryVerify(() => composer.suggestions.visible, 1000);
            verify(names().indexOf("command:variant") < 0);
            composer.input.text = "";
            setup({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5"});
            chat.piThinkingModels = ({"openai/gpt-5": true});
            keyClick("/");
            tryVerify(() => composer.suggestions.visible, 1000);
            compare(names()[1], "command:variant", "listed right after /model");
            wait(300);
            screenshot(root.Window.window.contentItem, "commands-list-variant");
        }

        function test_10_variant_applies_the_pi_thinking_level() {
            setup({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5"});
            chat.piThinkingModels = ({"openai/gpt-5": true});
            type("/variant hi");
            tryVerify(() => composer.suggestions.entries.length > 0, 1000);
            compare(composer.suggestions.entries[0].name, "high");
            keyClick(Qt.Key_Return);
            compare(calls("send").length, 0);
            compare(chat.effectiveConfig("a").thinking, "high");
        }

        function test_11_variant_that_does_not_exist_is_refused() {
            setup({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5"});
            chat.piThinkingModels = ({"openai/gpt-5": true});
            type("/variant zzz");
            keyClick(Qt.Key_Return);
            compare(calls("overrides").length, 0);
            compare(calls("send").length, 0);
            compare(composer.input.text, "/variant zzz");
        }

        function test_12_mode_changes_only_the_new_chat_mode() {
            compare(chat.effectiveConfig("a").mode, "provider");
            type("/mode opencode");
            keyClick(Qt.Key_Return);
            compare(chat.plasmoid.configuration.useOpenCode, true);
            compare(chat.plasmoid.configuration.usePi, false);
            compare(chat.effectiveConfig("a").mode, "provider", "the open chat keeps its mode");
            compare(chat.sessions[0].source, "provider");
            compare(calls("send").length, 0);
            compare(notice(), "New chats will use OpenCode. This chat stays Direct.");
            type("/mode pi");
            keyClick(Qt.Key_Return);
            compare(chat.plasmoid.configuration.useOpenCode, false);
            compare(chat.plasmoid.configuration.usePi, true);
            type("/mode direct");
            keyClick(Qt.Key_Return);
            compare(chat.plasmoid.configuration.usePi, false);
            compare(chat.effectiveConfig("a").mode, "provider");
        }

        function test_13_mode_without_a_valid_mode_changes_nothing() {
            type("/mode bogus");
            keyClick(Qt.Key_Return);
            compare(chat.plasmoid.configuration.useOpenCode, undefined);
            compare(calls("send").length, 0);
            compare(composer.input.text, "/mode bogus");
        }

        function test_14_unknown_slash_text_is_sent_as_a_message() {
            type("/etc/hosts? what is it");
            keyClick(Qt.Key_Return);
            compare(calls("send").length, 1);
            compare(calls("send")[0].args[0], "/etc/hosts? what is it");
        }

        function test_15_a_template_is_still_sent() {
            type("/fix this");
            keyClick(Qt.Key_Return);
            compare(calls("send").length, 1);
            compare(calls("send")[0].args[0], "/fix this");
        }

        function test_16_a_command_on_the_send_button_is_not_sent_either() {
            type("/new");
            keyClick(Qt.Key_Escape);
            mouseClick(findChild(composer, "sendButton"));
            compare(calls("create").length, 1);
            compare(calls("send").length, 0);
        }

        function test_17_image_makes_a_picture_and_is_not_sent() {
            type("/image a red fox in the snow");
            keyClick(Qt.Key_Return);
            compare(calls("image").length, 1);
            compare(calls("image")[0].args[0], "a red fox in the snow");
            compare(calls("send").length, 0);
            compare(composer.input.text, "");
        }

        function test_18_image_needs_a_prompt_and_an_image_service() {
            type("/image");
            keyClick(Qt.Key_Return);
            compare(calls("image").length, 0);
            compare(notice(), "Write what to draw, like /image a red fox in the snow.");
            composer.input.text = "";
            chat.imageCommandResult = {"ok": false, "code": "none", "problem": ""};
            type("/image a fox");
            keyClick(Qt.Key_Return);
            compare(composer.input.text, "/image a fox", "kept, to try again after adding a service");
            verify(notice().indexOf("Add an image service first") === 0, notice());
            compare(calls("send").length, 0);
            chat.imageCommandResult = {"ok": true, "code": "", "problem": ""};
        }
    }
}
