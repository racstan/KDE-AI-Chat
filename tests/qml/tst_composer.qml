// chat/Composer.qml: chat.focusInput() reaches the input (problem 9), and
// typing then Enter or the Send button sends the text.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 240

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    QQC2.TextField {
        id: elsewhere
        width: 100
    }

    Chat.Composer {
        id: composer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        chat: chat
    }

    HarnessTestCase {
        name: "Composer"

        function findSend(item) {
            if (item.objectName === "sendButton")
                return item;
            for (var i = 0; i < item.children.length; i++) {
                var found = findSend(item.children[i]);
                if (found)
                    return found;
            }
            return null;
        }

        function find(name) { return findChild(composer, name); }

        function init() {
            chat.calls = [];
            chat.loading = false;
            chat.currentStreamIndex = -1;
            chat.chatInputText = "";
            elsewhere.forceActiveFocus();
            tryVerify(() => elsewhere.activeFocus);
        }

        function test_1_registers_with_the_chat() {
            verify(chat.composerRef === composer);
        }

        function test_2_focusInput_focuses_the_input() {
            verify(!composer.input.activeFocus);
            chat.focusInput();
            tryVerify(() => composer.input.activeFocus, 1000, "the composer input has focus");
        }

        function test_3_type_and_enter_sends() {
            chat.focusInput();
            tryVerify(() => composer.input.activeFocus);
            keyClick("h");
            keyClick("i");
            compare(chat.chatInputText, "hi");
            keyClick(Qt.Key_Return);
            compare(chat.calls.length, 1);
            compare(chat.calls[0].name, "send");
            compare(chat.calls[0].args[0], "hi");
            compare(composer.input.text, "", "the input is cleared after sending");
        }

        function test_4_send_button_sends() {
            var send = findSend(composer);
            verify(send, "send button found");
            verify(!send.enabled, "nothing to send yet");
            chat.focusInput();
            tryVerify(() => composer.input.activeFocus);
            keyClick("o");
            keyClick("k");
            tryVerify(() => send.enabled);
            screenshot(root, "composer-typed");
            mouseClick(send);
            compare(chat.calls.length, 1);
            compare(chat.calls[0].args[0], "ok");
            compare(composer.input.text, "");
        }

        function test_5_while_a_reply_is_written_send_says_queue_and_stop_is_a_labelled_button() {
            var send = find("sendButton");
            var stop = find("stopButton");
            compare(send.text, "Send");
            verify(!stop.visible);
            chat.loading = true;
            compare(send.text, "Queue");
            verify(stop.visible);
            compare(stop.text, "Stop");
            compare(String(stop.icon.name), "media-playback-stop");
            verify(stop.Accessible.name !== "");
            chat.focusInput();
            tryVerify(() => composer.input.activeFocus);
            keyClick("a");
            tryVerify(() => send.enabled, 1000);
            mouseClick(send);
            compare(chat.calls[0].name, "send", "Queue sends (the widget queues it)");
            chat.calls = [];
            mouseClick(stop);
            compare(chat.calls.length, 1);
            compare(chat.calls[0].name, "stop");
            screenshot(root, "composer-streaming");
        }

        function test_6_the_composer_does_not_move_when_a_reply_starts() {
            var before = composer.height;
            var inputY = composer.input.mapToItem(root, 0, 0).y;
            chat.loading = true;
            wait(50);
            compare(composer.height, before, "same height while thinking");
            compare(composer.input.mapToItem(root, 0, 0).y, inputY, "the input stays where it was");
            chat.currentStreamIndex = 3;
            chat.streamingResponse = true;
            wait(50);
            compare(composer.input.mapToItem(root, 0, 0).y, inputY);
            chat.loading = false;
            chat.currentStreamIndex = -1;
            chat.streamingResponse = false;
            wait(50);
            compare(composer.input.mapToItem(root, 0, 0).y, inputY);
        }

        function test_7_the_status_line_says_what_is_going_on() {
            var text = find("statusText");
            var spinner = find("statusSpinner");
            verify(text.text.indexOf("Enter sends") === 0, "idle: the keys that work");
            verify(!spinner.running);
            chat.loading = true;
            verify(text.text.indexOf("Thinking") === 0, text.text);
            verify(text.text.indexOf("Esc") > 0, "says how to stop");
            verify(spinner.running, "a spinner before the reply has started");
            chat.currentStreamIndex = 1;
            verify(text.text.indexOf("Writing") === 0, text.text);
            verify(!spinner.running, "the reply has its own spinner next to its name");
        }

        function test_8_icon_buttons_have_accessible_names() {
            var names = [];
            function walk(item) {
                if (item.icon !== undefined && item.icon.name !== undefined && item.text === "")
                    names.push(item);
                for (var i = 0; i < item.children.length; i++) walk(item.children[i]);
            }
            walk(composer);
            verify(names.length >= 2, "found the icon-only buttons");
            for (var i = 0; i < names.length; i++)
                verify(names[i].Accessible.name !== "", "icon button " + names[i].icon.name + " has an accessible name");
        }
    }
}
