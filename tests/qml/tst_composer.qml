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

        function init() {
            chat.calls = [];
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
    }
}
