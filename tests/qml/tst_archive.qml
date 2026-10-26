// Archived chats: out of All chats and their projects, listed in the
// Archived view with Restore and Delete (with Undo).
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 760
    height: 520

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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        Chat.ChatHeader { chat: chat; historyFull: body.historyFull }
        Chat.ChatBody {
            id: body
            chat: chat
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    Chat.UndoNotice {
        id: undo
        chat: chat
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.gridUnit * 4
    }

    HarnessTestCase {
        name: "Archive"

        function init() {
            undo.dismiss();
            chat.calls = [];
            chat.currentSessionId = "a";
            chat.messages = [];
            chat.sessions = [
                {value: "a", text: "Open chat", updatedAt: Date.now()},
                {value: "b", text: "Archived plans", archived: true, projectId: "p-1", updatedAt: Date.now() - 1000},
                {value: "c", text: "Archived notes", archived: true, updatedAt: Date.now() - 2000}
            ];
            chat.projects.list = [{id: "p-1", name: "Work", color: "#3daee9"}];
            chat.projects.view = "all";
            chat.historyOnlyMode = true;
            tryVerify(() => body.sessionList !== null);
        }

        function rows() {
            var list = body.sessionList.list;
            var out = [];
            for (var i = 0; i < list.count; i++) {
                tryVerify(() => list.itemAtIndex(i) !== null);
                out.push(list.itemAtIndex(i));
            }
            return out;
        }

        function test_01_archived_chats_leave_the_main_history() {
            compare(rows().map(r => r.modelData.value), ["a"]);
            chat.projects.view = "p-1";
            compare(body.sessionList.list.count, 0, "nor in their project");
            verify(findChild(body.sessionList, "emptyViewLabel").visible);
            chat.projects.view = "archived";
            compare(rows().map(r => r.modelData.value), ["b", "c"]);
            screenshot(root, "archived-view");
        }

        function test_02_restore_from_the_archived_view() {
            chat.projects.view = "archived";
            var r = rows()[0];
            mouseMove(r, r.width / 2, r.height / 2);
            var restore = findChild(r, "archiveButton");
            tryVerify(() => restore.visible);
            compare(restore.Accessible.name, "Restore chat");
            screenshot(root, "archived-row-hover");
            restore.clicked();
            var last = chat.calls[chat.calls.length - 1];
            compare(last.name, "archive");
            compare(last.args, ["b", false]);
            // (main.qml's setSessionArchived; FakeChat only records it.)
            chat.setSessionProperty("b", "archived", false);
            compare(rows().map(r => r.modelData.value), ["c"], "gone from Archived");
            chat.projects.view = "p-1";
            compare(rows().map(r => r.modelData.value), ["b"], "back in its project");
        }

        function test_03_delete_from_the_archived_view_with_undo() {
            chat.projects.view = "archived";
            var r = rows()[1];
            mouseMove(r, r.width / 2, r.height / 2);
            var del = findChild(r, "deleteButton");
            tryVerify(() => del.visible);
            del.clicked();
            compare(chat.sessions.map(s => s.value), ["a", "b"]);
            verify(undo.visible);
            compare(undo.text, "Chat “Archived notes” deleted");
            screenshot(root, "archived-delete-undo");
            findChild(undo, "undoButton").clicked();
            compare(chat.sessions.map(s => s.value), ["a", "b", "c"]);
            compare(chat.sessions[2].archived, true, "it comes back archived");
            compare(rows().map(r => r.modelData.value), ["b", "c"]);
        }
    }
}
