// The chat popup's parts laid out as FullRepresentationContent does:
// header, rename row, message list, composer; and the history list.
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 640

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

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Chat.ChatHeader { id: header; chat: chat }
        Chat.RenameRow { id: renameRow; chat: chat }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Chat.ChatView {
                anchors.fill: parent
                visible: !chat.historyOnlyMode
                chat: chat
            }
            Chat.SessionList {
                id: sessionList
                anchors.fill: parent
                visible: chat.historyOnlyMode
                chat: chat
            }
        }

        Chat.Composer { chat: chat }
    }

    HarnessTestCase {
        name: "ChatLayout"

        function test_1_chat() {
            chat.messages = [
                {role: "user", content: "Where should we go in May?", time: "10:01"},
                {role: "assistant", model: "openrouter/auto", content: "Somewhere **warm**:\n\n- Lisbon\n- Valencia", time: "10:01", tokens: {input: 30, output: 12}}
            ];
            chat.renamingCurrentChat = true;
            chat.currentChatRenameDraft = "Trip planning";
            wait(50);
            verify(renameRow.visible);
            screenshot(root, "chat-layout");
            chat.renamingCurrentChat = false;
        }

        function test_2_history() {
            chat.sessions = [
                {value: "a", text: "Trip planning", count: 2},
                {value: "b", text: "OpenCode refactor", source: "opencode", count: 14},
                {value: "c", text: "Old chat", archived: true, count: 3}
            ];
            chat.historyOnlyMode = true;
            wait(50);
            compare(sessionList.list.count, 3);
            screenshot(root, "chat-layout-history");
            chat.historyOnlyMode = false;
        }
    }
}
