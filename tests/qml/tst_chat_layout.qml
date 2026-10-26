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

        function test_1b_a_notice_about_the_chats_mode_shows_above_the_chat() {
            var notice = findChild(body, "modeNotice");
            verify(notice !== null && !notice.visible, "no notice normally");
            chat.modeNotice = "This is a Pi chat and it can't answer right now. Pi: the Pi bridge didn't start. It stays in Pi mode (a chat never switches mode). Fix that and send again, or start a new chat in another mode.";
            wait(50);
            verify(notice.visible);
            verify(notice.height > 0 && notice.y < body.chatView.y + body.chatView.parent.y + 1, "above the messages");
            screenshot(root, "chat-layout-mode-notice");
            notice.dismissed();
            compare(chat.modeNotice, "");
            wait(30);
            verify(!notice.visible);
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
            compare(body.sessionList.list.count, 2, "the archived chat is in Archived, not All chats");
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
