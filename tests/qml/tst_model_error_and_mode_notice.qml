// Two notices that point at the way out without changing a chat's mode:
//  - an error about the model (it can't read images, it isn't available) has a
//    Change model button: Settings, or the quick picker when chats have their
//    own model settings (chat/ErrorActions.qml);
//  - chat/ModeMismatchBanner.qml says when Settings select another mode for
//    new chats than the open chat has, and offers a new chat.
import QtQuick
import QtQuick.Layouts
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 420

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.split("%" + i).join(arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    QtObject {
        id: cfg
        property bool useOpenCode: false
        property bool usePi: false
        property bool perChatModelSettings: false
        property string perChatPriority: "chat"
        property string provider: "openai"
    }

    FakeChat {
        id: chat
        plasmoid: ({configuration: cfg})
    }

    QtObject {
        id: fakeComposer
        property int opened: 0
        readonly property var picker: QtObject {
            function open() { fakeComposer.opened += 1; }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    ColumnLayout {
        anchors.fill: parent
        Chat.ModeMismatchBanner {
            id: banner
            chat: chat
        }
        Chat.ChatView {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true
            chat: chat
        }
    }

    HarnessTestCase {
        name: "ModelErrorAndModeNotice"

        readonly property string imageError: "⚠️ Request to https://api.deepseek.com/v1/chat/completions failed (HTTP 400): Failed to deserialize the JSON body: unknown variant `image_url`, this model does not support image input"

        function init() {
            chat.calls = [];
            chat.composerRef = null;
            fakeComposer.opened = 0;
            cfg.useOpenCode = false;
            cfg.usePi = false;
            cfg.perChatModelSettings = false;
            chat.sessions = [{value: "a", text: "Direct", source: "provider", messages: []}];
            chat.currentSessionId = "a";
            banner.dismissedKeys = ({});
            chat.messages = [];
        }

        function errorCard(content) {
            chat.messages = [{role: "user", content: "Look", time: "10:00"}, {role: "error", content: content, time: "10:00"}];
            wait(100);
            var d = view.list.itemAtIndex(1);
            verify(d, "error delegate");
            return d;
        }

        function test_image_error_offers_change_model_in_settings() {
            var d = errorCard(imageError);
            compare(findChild(d, "messageBody").text.indexOf("This model can't read images."), 0);
            var button = findChild(d, "changeModelButton");
            verify(button.visible);
            compare(button.text, "Change model");
            verify(!findChild(d, "settingsButton").visible, "Change model replaces Open settings");
            screenshot(root, "model-error-change-model");
            mouseClick(button);
            compare(chat.calls[chat.calls.length - 1].name, "openSettings");
            compare(fakeComposer.opened, 0);
        }

        function test_model_not_found_offers_change_model() {
            var d = errorCard("Request to https://x/v1/chat/completions failed (HTTP 404): The model `gpt-9` does not exist");
            verify(findChild(d, "changeModelButton").visible);
        }

        function test_per_chat_settings_open_the_picker_instead() {
            cfg.perChatModelSettings = true;
            chat.composerRef = fakeComposer;
            var d = errorCard(imageError);
            mouseClick(findChild(d, "changeModelButton"));
            compare(fakeComposer.opened, 1);
            compare(chat.calls.filter(function(c) { return c.name === "openSettings"; }).length, 0);
            compare(chat.sessions[0].source, "provider", "the chat keeps its mode");
        }

        function test_other_errors_have_no_change_model() {
            var d = errorCard("Request to https://x failed (HTTP 429): slow down");
            verify(!findChild(d, "changeModelButton").visible);
        }

        function test_mode_notice_when_modes_differ() {
            verify(!banner.visible, "same mode: no notice");
            cfg.usePi = true;
            tryVerify(function() { return banner.visible; });
            compare(banner.text, "The mode is now Pi. This chat stays in Direct mode, because a chat can't change mode. Start a new chat to use Pi.");
            screenshot(root, "mode-notice");
            mouseClick(banner.children[0].children[1]);
            compare(chat.calls[chat.calls.length - 1].name, "create");
            compare(chat.calls[chat.calls.length - 1].args[0], true);
            compare(chat.sessions[0].source, "provider", "the chat keeps its mode");
        }

        function test_mode_notice_gone_in_a_chat_of_the_current_mode() {
            cfg.usePi = true;
            tryVerify(function() { return banner.visible; });
            chat.sessions = chat.sessions.concat([{value: "p", text: "Pi", source: "pi", messages: []}]);
            chat.currentSessionId = "p";
            tryVerify(function() { return !banner.visible; });
            chat.currentSessionId = "a";
            tryVerify(function() { return banner.visible; });
        }

        function test_mode_notice_can_be_dismissed_per_chat() {
            cfg.useOpenCode = true;
            tryVerify(function() { return banner.visible; });
            verify(banner.text.indexOf("The mode is now OpenCode.") === 0);
            banner.dismissed();
            verify(!banner.visible);
            chat.sessions = chat.sessions.concat([{value: "b", text: "Direct 2", source: "provider", messages: []}]);
            chat.currentSessionId = "b";
            tryVerify(function() { return banner.visible; }, 1000, "another chat still shows it");
        }
    }
}
