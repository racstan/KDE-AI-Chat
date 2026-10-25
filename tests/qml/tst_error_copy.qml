// An error card has a Copy button that copies the full message (status, URL,
// provider detail), and shows the model error in plain words.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 360

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

    Chat.ChatView {
        id: view
        anchors.fill: parent
        chat: chat
    }

    HarnessTestCase {
        name: "ErrorCopy"

        readonly property string raw: "⚠️ Request to https://integrate.api.nvidia.com/v1/chat/completions failed (HTTP 404): Function '767b5b9a-1': Not found for account 'TSF5_x'"
        readonly property string full: raw.replace(/^⚠️\s*/, "")

        function init() {
            chat.calls = [];
            chat.messages = [
                {role: "user", content: "Hello", time: "10:00"},
                {role: "error", content: raw, time: "10:00"}
            ];
            wait(50);
        }

        function test_copy_button_copies_the_full_error() {
            var delegate = view.list.itemAtIndex(1);
            verify(delegate, "error delegate");
            var button = null;
            tryVerify(function() { button = findChild(delegate, "copyErrorButton"); return button !== null; }, 3000);
            compare(button.QQC2.ToolTip.text, "Copy error");
            screenshot(root, "error-card-copy");
            mouseClick(button);
            compare(chat.calls.length, 1);
            compare(chat.calls[0].name, "copy");
            compare(chat.calls[0].args[0], full);
            compare(button.icon.name, "checkmark", "feedback while copied");
            tryCompare(button, "text", "Copy error", 3000);
        }
    }
}
