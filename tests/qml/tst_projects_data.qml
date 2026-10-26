// chat/Projects.qml: create, edit, delete with Undo, move chats, new chat in
// a project, and the history's views; on the real component with FakeChat.
import QtQuick
import QtTest

Item {
    id: root
    width: 200
    height: 100

    FakeChat { id: chat }

    // A stand-in for store/ChatStore.qml's project file.
    QtObject {
        id: store
        property string saved: ""
        function loadProjects() { return saved; }
        function saveProjects(list) { saved = JSON.stringify(list); }
    }

    HarnessTestCase {
        name: "ProjectsData"

        function init() {
            store.saved = "";
            chat.chatStore = store;
            chat.calls = [];
            chat.currentSessionId = "a";
            chat.messages = [];
            chat.sessions = [
                {value: "a", text: "Direct chat", source: "provider", messages: []},
                {value: "b", text: "Pi chat", source: "pi", messages: [{role: "user", content: "hi"}], openCodeWorkspaceCwd: ""},
                {value: "c", text: "Old archived", source: "provider", archived: true, messages: []}
            ];
            chat.projects.load();
            chat.projects.view = "all";
        }

        function test_create_is_stored_and_loads_back() {
            var id = chat.projects.create({name: "  Work ", color: "#1cdc9a", instructions: "Answer in French.", folder: "/tmp"});
            verify(/^p-/.test(id));
            compare(chat.projects.list.length, 1);
            compare(chat.projects.byId(id).name, "Work");
            compare(JSON.parse(store.saved)[0].instructions, "Answer in French.");
            chat.projects.list = [];
            chat.projects.load();
            compare(chat.projects.byId(id).folder, "/tmp");
        }

        function test_rename_and_recolour() {
            var id = chat.projects.create({name: "Work"});
            verify(chat.projects.update(id, {name: "Home", color: "#da4453"}));
            compare(chat.projects.byId(id).name, "Home");
            compare(chat.projects.byId(id).color, "#da4453");
            compare(JSON.parse(store.saved)[0].name, "Home");
            verify(!chat.projects.update("p-nope", {name: "x"}));
        }

        function test_moving_chats_never_changes_their_mode() {
            var id = chat.projects.create({name: "Work", folder: "/srv/work"});
            chat.projects.moveChat("a", id);
            chat.projects.moveChat("b", id);
            compare(chat.getSessionProperty("a", "projectId", ""), id);
            compare(chat.getSessionProperty("a", "source", ""), "provider");
            compare(chat.getSessionProperty("b", "source", ""), "pi");
            // The direct chat follows the project's folder; the Pi chat with history keeps its own.
            compare(chat.projects.workspaceFor("a").path, "/srv/work");
            compare(chat.projects.workspaceFor("a").from, "project");
            compare(chat.getSessionProperty("b", "keepOwnFolder", false), true);
            compare(chat.projects.workspaceFor("b").path, "");
            compare(chat.projects.ofChat("a").name, "Work");
            chat.projects.moveChat("a", "");
            compare(chat.projects.ofChat("a"), null);
        }

        function test_views_filter_the_history() {
            var id = chat.projects.create({name: "Work"});
            chat.projects.moveChat("a", id);
            chat.projects.view = id;
            compare(chat.projects.visibleChats.map(s => s.value), ["a"]);
            chat.projects.view = "archived";
            compare(chat.projects.visibleChats.map(s => s.value), ["c"]);
            chat.projects.view = "all";
            compare(chat.projects.visibleChats.map(s => s.value), ["a", "b"]);
            compare(chat.projects.counts[id], 1);
        }

        function test_delete_keeps_the_chats_and_undo_brings_it_all_back() {
            var id = chat.projects.create({name: "Work"});
            chat.projects.moveChat("a", id);
            chat.projects.view = id;
            var deleted = null;
            function onDeleted(project, index, moved) { deleted = {project: project, index: index, moved: moved}; }
            chat.projects.projectDeleted.connect(onDeleted);
            chat.projects.remove(id);
            chat.projects.projectDeleted.disconnect(onDeleted);
            compare(chat.projects.list.length, 0);
            compare(chat.sessions.length, 3, "the chats stay");
            compare(chat.getSessionProperty("a", "projectId", ""), "", "and move to no project");
            compare(chat.projects.view, "all", "the deleted project's view closes");
            compare(deleted.moved, ["a"]);
            chat.projects.restore(deleted.project, deleted.index, deleted.moved);
            compare(chat.projects.byId(id).name, "Work");
            compare(chat.getSessionProperty("a", "projectId", ""), id);
        }

        function test_new_chat_starts_in_the_project_shown() {
            var id = chat.projects.create({name: "Work"});
            chat.projects.view = id;
            chat.projects.newChat();
            compare(chat.calls[chat.calls.length - 1].name, "create");
            compare(chat.calls[chat.calls.length - 1].args, [true, id]);
            chat.projects.view = "archived";
            chat.projects.newChat();
            compare(chat.calls[chat.calls.length - 1].args, [true, ""]);
            compare(chat.projects.view, "all", "a new chat isn't archived: show All chats");
        }
    }
}
