// The chat popup's parts laid out as FullRepresentationContent does:
// header, rename row, message list, composer; and the history list.
import QtCore
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

        Chat.ChatBody {
            id: body
            chat: chat
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
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
            tryVerify(() => body.sessionList !== null);
            compare(body.sessionList.list.count, 3);
            verify(body.historyFull, "520 px is narrow: the history replaces the chat");
            screenshot(root, "chat-layout-history");
            chat.historyOnlyMode = false;
        }

        function test_3_export_suggests_the_documents_folder() {
            const docs = String(StandardPaths.writableLocation(StandardPaths.DocumentsLocation));
            const name = header.exportFileName();
            verify(name.indexOf(docs.replace(/\/+$/, "") + "/") === 0, name);
            verify(/\/Trip_planning_\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d\.md$/.test(name), name);
        }
    }
}
