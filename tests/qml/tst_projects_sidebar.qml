// The projects sidebar in the history (chat/ProjectsSidebar.qml, SessionList,
// ProjectEditor, ProjectMenu): views filter the history, projects are created,
// renamed, recoloured and deleted (with Undo), chats move into projects from
// their menu, and New chat starts in the project shown.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
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
    function i18np(one, many, n) {
        var text = n === 1 ? one : many;
        for (var i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), arguments[i]);
        return text;
    }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Chat.ChatHeader { id: header; chat: chat; historyFull: body.historyFull }
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

    QtObject {
        id: store
        property string saved: ""
        function loadProjects() { return saved; }
        function saveProjects(list) { saved = JSON.stringify(list); }
    }

    HarnessTestCase {
        name: "ProjectsSidebar"

        function init() {
            root.width = 760;
            undo.dismiss();
            body.projectEditor.close();
            tryVerify(() => !body.projectEditor.visible);
            store.saved = JSON.stringify([
                {id: "p-work", name: "Work", color: "#3daee9", instructions: "Answer in French.", folder: "/srv/work"},
                {id: "p-home", name: "Home", color: "#f67400"}
            ]);
            chat.chatStore = store;
            chat.calls = [];
            chat.currentSessionId = "a";
            chat.messages = [];
            var now = Date.now();
            chat.sessions = [
                {value: "a", text: "Quarterly report", source: "provider", projectId: "p-work", updatedAt: now},
                {value: "b", text: "Garden plans", source: "provider", projectId: "p-home", updatedAt: now - 1000},
                {value: "c", text: "Loose chat", source: "pi", updatedAt: now - 2000},
                {value: "d", text: "Old budget", source: "provider", projectId: "p-work", archived: true, updatedAt: now - 3000}
            ];
            chat.projects.load();
            chat.projects.view = "all";
            chat.historyOnlyMode = true;
            tryVerify(() => body.sessionList !== null);
            wait(20);
        }

        function sidebarRows() { return findChildren(body.sessionList.sidebar, "viewRow"); }
        function rowNamed(name) { return sidebarRows().find(r => r.modelData.name === name); }
        function titles() {
            var out = [];
            var list = body.sessionList.list;
            for (var i = 0; i < list.count; i++)
                out.push(list.model[i].text);
            return out;
        }

        function test_01_views_list_all_chats_each_project_and_archived() {
            tryVerify(() => sidebarRows().length === 4);
            compare(sidebarRows().map(r => r.modelData.name), ["All chats", "Work", "Home", "Archived"]);
            compare(rowNamed("All chats").count, 3);
            compare(rowNamed("Work").count, 1, "the archived Work chat is counted under Archived");
            compare(rowNamed("Archived").count, 1);
            compare(titles(), ["Quarterly report", "Garden plans", "Loose chat"]);
            // A chat in a project shows the project's colour in All chats.
            var dots = findChildren(body.sessionList.list, "projectDot").filter(d => d.visible);
            compare(dots.length, 2);
            screenshot(root, "projects-sidebar-all");
        }

        function test_02_choosing_a_view_filters_the_history() {
            mouseClick(rowNamed("Work"));
            compare(chat.projects.view, "p-work");
            compare(titles(), ["Quarterly report"]);
            compare(findChild(body.sessionList, "viewTitle").text, "Work");
            verify(findChild(body.sessionList, "newChatInViewButton").visible);
            screenshot(root, "projects-sidebar-project");
            mouseClick(rowNamed("Archived"));
            compare(titles(), ["Old budget"]);
            compare(findChild(body.sessionList, "viewTitle").text, "Archived chats");
            verify(!findChild(body.sessionList, "newChatInViewButton").visible, "no new chats in Archived");
            mouseClick(rowNamed("All chats"));
            compare(titles().length, 3);
        }

        function test_03_create_a_project_in_the_editor() {
            mouseClick(findChild(body.sessionList.sidebar, "newProjectButton"));
            var editor = body.projectEditor;
            tryVerify(() => editor.opened);
            compare(editor.projectId, "");
            keyClick(Qt.Key_T); keyClick(Qt.Key_R); keyClick(Qt.Key_I); keyClick(Qt.Key_P);
            compare(editor.name, "trip");
            var swatches = findChildren(editor.contentItem, "colorSwatch");
            compare(swatches.length, chat.projects.colors.length);
            mouseClick(swatches[4]);
            findChild(editor.contentItem, "projectInstructions").text = "Plan cheap trains.";
            screenshot(root.Window.window.contentItem, "project-editor-new");
            mouseClick(findChild(editor.contentItem, "saveProject"));
            tryVerify(() => !editor.visible);
            var p = chat.projects.list[2];
            compare(p.name, "trip");
            compare(p.color, chat.projects.colors[4]);
            compare(p.instructions, "Plan cheap trains.");
            compare(JSON.parse(store.saved).length, 3, "stored");
            tryVerify(() => sidebarRows().length === 5);
        }

        function test_04_rename_and_recolour() {
            var r = rowNamed("Home");
            mouseMove(r, r.width / 2, r.height / 2);
            var edit = findChild(r, "editProjectButton");
            tryVerify(() => edit.visible);
            mouseClick(edit);
            var editor = body.projectEditor;
            tryVerify(() => editor.opened);
            compare(editor.projectId, "p-home");
            compare(findChild(editor.contentItem, "projectName").text, "Home");
            findChild(editor.contentItem, "projectName").text = "House";
            mouseClick(findChildren(editor.contentItem, "colorSwatch")[1]);
            screenshot(root.Window.window.contentItem, "project-editor-edit");
            mouseClick(findChild(editor.contentItem, "saveProject"));
            tryVerify(() => !editor.visible);
            compare(chat.projects.byId("p-home").name, "House");
            compare(chat.projects.byId("p-home").color, chat.projects.colors[1]);
        }

        function test_05_delete_keeps_the_chats_and_undo_brings_the_project_back() {
            mouseClick(rowNamed("Work"));
            chat.projects.openEditor("p-work", "");
            var editor = body.projectEditor;
            tryVerify(() => editor.opened);
            mouseClick(findChild(editor.contentItem, "deleteProject"));
            tryVerify(() => !editor.visible);
            compare(chat.projects.byId("p-work"), null);
            compare(chat.sessions.length, 4, "no chat was deleted");
            compare(chat.getSessionProperty("a", "projectId", ""), "");
            compare(chat.getSessionProperty("d", "projectId", ""), "");
            compare(chat.projects.view, "all");
            verify(undo.visible);
            compare(undo.text, "Project “Work” deleted; its chats were kept");
            screenshot(root, "project-deleted-undo");
            mouseClick(findChild(undo, "undoButton"));
            compare(chat.projects.list[0].name, "Work", "back in its place");
            compare(chat.getSessionProperty("a", "projectId", ""), "p-work");
            compare(chat.getSessionProperty("d", "projectId", ""), "p-work");
        }

        function test_06_move_a_chat_from_its_menu_mode_unchanged() {
            var list = body.sessionList.list;
            tryVerify(() => list.itemAtIndex(2) !== null);
            var row = list.itemAtIndex(2);
            compare(row.modelData.value, "c");
            mouseClick(row, row.width / 2, row.height / 2, Qt.RightButton);
            var menu = body.sessionList.rowMenu;
            tryVerify(() => menu.opened);
            screenshot(root.Window.window.contentItem, "history-row-menu");
            // The submenu's items: trigger the one for Work.
            var sub = null;
            for (var i = 0; i < menu.count; i++) {
                var it = menu.itemAt(i);
                if (it && it.subMenu)
                    sub = it.subMenu;
            }
            verify(sub !== null, "Move to project is a submenu");
            var work = null;
            for (var j = 0; j < sub.count; j++) {
                if (sub.itemAt(j) && sub.itemAt(j).text === "Work")
                    work = sub.itemAt(j);
            }
            verify(work !== null);
            work.triggered();
            menu.close();
            compare(chat.getSessionProperty("c", "projectId", ""), "p-work");
            compare(chat.getSessionProperty("c", "source", ""), "pi", "the mode never changes");
        }

        function test_07_move_the_open_chat_from_the_header_menu() {
            var sub = findChild(header, "moreButton").projectMenu;
            compare(sub.title, "Move to project");
            var none = null;
            for (var j = 0; j < sub.count; j++) {
                if (sub.itemAt(j) && sub.itemAt(j).text === "No project")
                    none = sub.itemAt(j);
            }
            verify(none.checked === false, "the open chat is in Work");
            none.triggered();
            compare(chat.getSessionProperty("a", "projectId", "x"), "");
            compare(chat.getSessionProperty("a", "source", ""), "provider");
        }

        function test_08_new_chat_inside_a_project() {
            mouseClick(rowNamed("Home"));
            mouseClick(findChild(body.sessionList, "newChatInViewButton"));
            var last = chat.calls[chat.calls.length - 1];
            compare(last.name, "create");
            compare(last.args, [true, "p-home"]);
            // The header's New chat does the same while the history is open.
            chat.calls = [];
            mouseClick(findChild(header, "newChatButton"));
            compare(chat.calls[0].args, [true, "p-home"]);
        }

        function test_09_narrow_popup_shows_the_sidebar_instead_of_the_chat() {
            root.width = 520;
            tryVerify(() => body.historyFull);
            verify(!body.chatView.visible);
            verify(body.sessionList.sidebar.visible);
            mouseClick(rowNamed("Work"));
            compare(titles(), ["Quarterly report"]);
            screenshot(root, "projects-sidebar-narrow");
        }

        function test_10_delete_a_project_with_its_chats_after_confirming() {
            root.width = 520;
            mouseClick(rowNamed("Work"), 20, 10, Qt.RightButton);
            var overlay = root.QQC2.Overlay.overlay;
            var keep = null, withChats = null;
            tryVerify(function() {
                keep = findChild(overlay, "deleteProjectItem");
                withChats = findChild(overlay, "deleteProjectWithChatsItem");
                return keep !== null && withChats !== null && withChats.visible;
            }, 2000, "the menu offers both");
            verify(withChats.enabled, "Work has chats");
            wait(400); // the menu fades in
            screenshot(root.Window.window.contentItem, "project-delete-menu");
            mouseClick(withChats);
            var text = null;
            tryVerify(function() { text = findChild(overlay, "projectDeleteText"); return text !== null && text.visible && text.width > 0; }, 2000, "it asks first");
            verify(text.text.indexOf("Delete the project “Work” and its 2 chats?") === 0, text.text);
            verify(text.text.indexOf("Undo") > 0, "says what Undo brings back");
            var box = text.mapToItem(root, 0, 0);
            verify(box.x >= 0 && box.x + text.width <= root.width, "fits the narrow popup");
            wait(400); // the menu fades out, the question in
            screenshot(root.Window.window.contentItem, "project-delete-confirm");
            chat.calls = [];
            mouseClick(findChild(overlay, "projectDeleteConfirmButton"));
            tryVerify(() => findChild(overlay, "projectDeleteText") === null, 2000, "it closes");
            compare(chat.calls.filter(c => c.name === "deleteSession").map(c => c.args[0]).sort(), ["a", "d"], "through the chat delete path");
            compare(chat.projects.byId("p-work"), null);
            compare(chat.sessions.map(s => s.value), ["b", "c"]);
            compare(undo.text, "Project “Work” and its 2 chats deleted");
            screenshot(root, "project-deleted-with-chats-undo");
            mouseClick(findChild(undo, "undoButton"));
            compare(chat.projects.list[0].name, "Work");
            compare(chat.sessions.map(s => s.value), ["a", "b", "c", "d"], "the chats are back");
            compare(chat.getSessionProperty("d", "projectId", ""), "p-work");
        }

        function test_11_cancel_deletes_nothing_and_an_empty_project_has_no_chats_to_delete() {
            var confirm = body.sessionList.sidebar.confirmDeleteWithChats("p-home");
            tryVerify(() => confirm.opened);
            compare(confirm.count, 1);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !confirm.visible);
            verify(chat.projects.byId("p-home") !== null);
            compare(chat.sessions.length, 4);
            var id = chat.projects.create({"name": "Empty"});
            compare(chat.projects.chatsIn(id).length, 0);
        }
    }
}
