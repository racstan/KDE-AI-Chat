// The note after a chat's model changes (chat/CommandRunner.qml, noteModelSwitch):
// in a chat with messages, the status line above the message box says that the
// provider's cache starts over. Every way of changing the model saves through
// ChatSettingsDraft.save, so they all get it: /model in the box, the picker above
// the box, Chat info's "Change…" and the chat settings form, in direct, OpenCode
// and Pi chats. Nothing for an empty chat, for the same model again, when the main
// settings win (the model does not change), or with warnModelSwitchCache off.
import QtQuick
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

    // The fake provider's /models answer, for the pickers' live lists.
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

    // The Chat info line, whose "Change…" picker opens under it.
    Chat.EffectiveLine {
        id: info
        x: 10
        y: 10
        width: 500
        chat: chat
        effective: chat.effectiveConfig(chat.currentSessionId)
        perChat: true
        providerName: function(id) { return chat.providerDisplayName(id); }
    }

    Chat.Composer {
        id: composer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        chat: chat
    }

    // The chat settings form's draft: ChatSettingsDialog's Apply saves it.
    Chat.ChatSettingsDraft {
        id: form
        rootRef: chat
        xhrFactory: root.makeXhr
    }

    HarnessTestCase {
        id: tc
        name: "ModelSwitchNotice"

        readonly property string cacheNote: "New model: the cache starts over, so the next message may cost more."

        function setup(session, config) {
            chat.plasmoid = {configuration: Object.assign({
                provider: "nvidia",
                perChatModelSettings: true,
                warnModelSwitchCache: true,
                providersJson: JSON.stringify([{id: "nvidia", name: "NVIDIA NIM", type: "openai-compat", baseUrl: "https://nim.example/v1", model: "acme/chat-big"}])
            }, config || {})};
            chat.walletApiKeys = {"nvidia": "good"};
            chat.sessions = [Object.assign({value: "a", text: "Chat", source: "provider"}, session || {})];
            chat.currentSessionId = "a";
        }

        function directChat(extra) {
            return Object.assign({ownModel: true, chatProvider: "nvidia", chatModel: "nemotron-3.5-bolt-e4b"}, extra || {});
        }
        function piChat(extra) {
            return Object.assign({source: "pi", ownModel: true, piProvider: "openai", piModel: "gpt-5", piThinking: "high"}, extra || {});
        }
        function openCodeChat(extra) {
            return Object.assign({source: "opencode", ownModel: true, openCodeProvider: "openrouter", openCodeModel: "auto", openCodeAgent: "build"}, extra || {});
        }

        function init() {
            chat.calls = [];
            chat.loading = false;
            chat.chatInputText = "";
            chat.messages = [{role: "user", content: "First", time: "10:00"}, {role: "assistant", content: "Reply", time: "10:00"}];
            chat.piThinkingModels = ({});
            chat.openCodeVariants = ({});
            chat.openCodeModelsList = [];
            chat.openCodeAgentsList = [];
            chat.piProviderModelMap = ({});
            composer.picker.xhrFactory = root.makeXhr;
            composer.picker.close();
            info.picker.xhrFactory = root.makeXhr;
            info.picker.close();
            setup(directChat());
            // Typing clears the status line's notice (CommandRunner.track), so the
            // notice of the test before this one is gone.
            composer.input.text = "x";
            composer.input.text = "";
            settleComposerFocus(composer);
        }

        function cleanup() {
            composer.picker.close();
            info.picker.close();
        }

        function notice() { return findChild(composer, "statusText").text; }
        function calls(name) { return chat.calls.filter(function(c) { return c.name === name; }); }
        function type(text) {
            for (var i = 0; i < text.length; i++)
                keyClick(text.charAt(i));
        }
        function openPicker(picker) {
            picker.open();
            tryVerify(function() { return picker.opened; }, 2000);
        }

        function test_1_switching_the_model_in_a_chat_with_messages_says_the_cache_starts_over() {
            type("/model acme/chat-small");
            keyClick(Qt.Key_Return);
            compare(chat.effectiveConfig("a").model, "acme/chat-small");
            compare(calls("send").length, 0, "a command is not sent");
            compare(notice(), cacheNote);
            screenshot(root, "model-switch-notice");
        }

        function test_2_the_picker_above_the_box_says_it_too() {
            openPicker(composer.picker);
            composer.picker.choose("model", "acme/chat-small");
            verify(!composer.picker.opened, "the picker closes once the model is chosen");
            compare(chat.effectiveConfig("a").model, "acme/chat-small");
            compare(notice(), cacheNote);
        }

        function test_3_chat_info_change_says_it_too() {
            mouseClick(findChild(info, "changeModelButton"));
            tryVerify(function() { return info.picker.opened; }, 2000);
            info.picker.choose("model", "acme/chat-small");
            compare(chat.effectiveConfig("a").model, "acme/chat-small");
            compare(notice(), cacheNote);
        }

        function test_4_the_chat_settings_form_says_it_too() {
            form.load("a");
            form.changeModel("acme/chat-small", true);
            verify(form.save(), "the form saves");
            compare(chat.effectiveConfig("a").model, "acme/chat-small");
            compare(notice(), cacheNote);
        }

        function test_5_pi_and_opencode_chats_say_it_too() {
            setup(piChat());
            openPicker(composer.picker);
            composer.picker.choose("model", "gpt-5-mini");
            compare(chat.effectiveConfig("a").model, "gpt-5-mini");
            compare(notice(), cacheNote, "Pi");

            composer.input.text = "x";
            composer.input.text = "";
            setup(openCodeChat());
            openPicker(composer.picker);
            composer.picker.choose("model", "gpt-5-mini");
            compare(chat.effectiveConfig("a").model, "gpt-5-mini");
            compare(notice(), cacheNote, "OpenCode");
        }

        function test_6_an_empty_chat_gets_no_note() {
            chat.messages = [];
            type("/model acme/chat-small");
            keyClick(Qt.Key_Return);
            compare(chat.effectiveConfig("a").model, "acme/chat-small");
            compare(notice(), "This chat now uses acme/chat-small.");
        }

        function test_7_the_same_model_again_gets_no_note() {
            type("/model nemotron-3.5-bolt-e4b");
            keyClick(Qt.Key_Return);
            compare(chat.effectiveConfig("a").model, "nemotron-3.5-bolt-e4b");
            compare(notice(), "This chat now uses nemotron-3.5-bolt-e4b.");
        }

        function test_8_with_the_setting_off_there_is_no_note() {
            setup(directChat(), {warnModelSwitchCache: false});
            type("/model acme/chat-small");
            keyClick(Qt.Key_Return);
            compare(chat.effectiveConfig("a").model, "acme/chat-small");
            compare(notice(), "This chat now uses acme/chat-small.");
        }

        function test_9_when_the_main_settings_win_the_model_stays_and_nothing_is_said_of_the_cache() {
            setup(directChat(), {perChatPriority: "main"});
            type("/model acme/chat-small");
            keyClick(Qt.Key_Return);
            compare(chat.effectiveConfig("a").model, "acme/chat-big", "the main model still applies");
            verify(notice().indexOf("main settings win") >= 0, notice());
        }

        function test_10_the_note_goes_away_by_itself() {
            type("/model acme/chat-small");
            keyClick(Qt.Key_Return);
            compare(notice(), cacheNote);
            tryVerify(function() { return notice() === ""; }, 12000, "the notice clears after its timer");
        }
    }
}
