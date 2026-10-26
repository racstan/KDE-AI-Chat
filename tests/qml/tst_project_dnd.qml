// Dragging a chat row of the history onto a project moves the chat there
// (chat/SessionList.qml's DragHandler, chat/ProjectsSidebar.qml's DropArea),
// with the same move as the menu's Move to project.
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 760
    height: 600

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

    Chat.ChatBody {
        id: body
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        chat: chat
    }

    QtObject {
        id: store
        property string saved: ""
        function loadProjects() { return saved; }
        function saveProjects(list) { saved = JSON.stringify(list); }
    }

    HarnessTestCase {
        name: "ProjectDragAndDrop"

        function init() {
            store.saved = JSON.stringify([
                {id: "p-work", name: "Work", color: "#3daee9"},
                {id: "p-home", name: "Home", color: "#f67400"}
            ]);
            chat.chatStore = store;
            chat.currentSessionId = "a";
            chat.messages = [];
            var now = Date.now();
            chat.sessions = [
                {value: "a", text: "Quarterly report", source: "provider", projectId: "p-work", updatedAt: now},
                {value: "b", text: "Garden plans", source: "provider", updatedAt: now - 1000},
                {value: "c", text: "Loose chat", source: "pi", updatedAt: now - 2000}
            ];
            chat.projects.load();
            chat.projects.view = "all";
            chat.historyOnlyMode = true;
            tryVerify(() => body.sessionList !== null);
            tryVerify(() => Math.abs(body.historyPane.width - body.historyPane.shownWidth) < 0.5, 3000);
            wait(50);
        }

        function projectRow(name) {
            return findChildren(body.sessionList.sidebar, "viewRow").find(r => r.modelData.name === name);
        }
        function chatRow(index) {
            var item = body.sessionList.list.itemAtIndex(index);
            verify(item, "chat row " + index);
            return item;
        }
        function projectOf(id) {
            return chat.sessions.find(s => s.value === id).projectId || "";
        }

        // Presses on `from`, moves in steps to the middle of `to` and releases there.
        function dragTo(from, to, shot) {
            var start = from.mapToItem(root, 30, from.height / 2);
            var end = to.mapToItem(root, to.width / 2, to.height / 2);
            mousePress(root, start.x, start.y);
            for (var i = 1; i <= 12; i++)
                mouseMove(root, start.x + (end.x - start.x) * i / 12, start.y + (end.y - start.y) * i / 12);
            wait(30);
            var ghost = findChild(body.sessionList, "dragGhost");
            verify(ghost.visible, "the dragged chat's label follows the pointer");
            if (shot)
                screenshot(root, shot);
            mouseRelease(root, end.x, end.y);
            wait(30);
            verify(!ghost.visible, "the label goes away on release");
        }

        function test_drop_on_a_project_moves_the_chat() {
            compare(projectOf("b"), "");
            dragTo(chatRow(1), projectRow("Home"), "project-dnd-dragging");
            compare(projectOf("b"), "p-home", "dropped on Home: the chat is in Home");
            compare(chat.sessions.find(s => s.value === "b").source, "provider", "its mode is kept");
            compare(projectRow("Home").count, 1);
            // From one project to another.
            dragTo(chatRow(0), projectRow("Home"));
            compare(projectOf("a"), "p-home");
        }

        function test_drop_outside_a_project_changes_nothing() {
            dragTo(chatRow(1), projectRow("All chats"));
            compare(projectOf("b"), "", "All chats is not a project");
            dragTo(chatRow(2), projectRow("Archived"));
            compare(projectOf("c"), "");
            verify(!chat.sessions.find(s => s.value === "c").archived, "nothing archived by a drop");
        }

        function test_a_click_still_opens_the_chat() {
            mouseClick(chatRow(1));
            compare(chat.currentSessionId, "b");
            compare(projectOf("b"), "");
        }
    }
}
