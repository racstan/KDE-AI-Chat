// Deleting a project together with its chats (chat/Projects.qml
// removeWithChats), through the real chat delete path (chat/Sessions.qml
// deleteSession), and Undo (chat/UndoNotice.qml) bringing it all back.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

TestCase {
    id: tc
    name: "ProjectDeleteChats"
    width: 520
    height: 300
    when: windowShown

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

    // The root's state and the forwarders these modules call (main.qml has the real ones).
    QtObject {
        id: chat
        property var plasmoid: QtObject { property var configuration: ({"lastSessionId": "", "autoNameChats": false, "contextMessageLimit": -1}) }
        property var sessions: []
        property string currentSessionId: ""
        property string currentSessionTitle: ""
        property var messages: []
        property bool loading: false
        property var activeXhr: null
        property int requestGeneration: 0
        property string activeRequestSessionId: ""
        property int queueCounter: 0
        property bool openCodeMode: false
        property bool piMode: false
        property int playingMessageIndex: -1
        property int currentStreamIndex: -1
        property string currentStreamText: ""
        property string currentStreamReasoning: ""
        property string currentStreamExtractedReasoning: ""
        property bool streamingResponse: false
        property int editingMessageIndex: -1
        property string editingDraft: ""
        property string editingSessionId: ""
        property string editingSessionDraft: ""
        property bool renamingCurrentChat: false
        property string currentChatRenameDraft: ""
        property bool historyOnlyMode: true
        property bool historySidePanel: false
        property var voiceManagerRef: null
        property var attachedFiles: []
        property var msgListViewRef: null
        property bool userScrolledUp: false
        property var chatStore: null
        property var memory: null
        readonly property int maxMessageChars: 2000000
        property var streamBuffer: QtObject { function clear() {} function flush() {} }
        property var store: QtObject { function save(s) {} }
        readonly property var projects: Chat.Projects { chat: chat }
        signal sessionDeleted(var session, int index)
        signal messagesDropped(string sessionId, var messages)
        function applySessionSource(s) { return "chat"; }
        function invalidateActiveRequest(p) { sender.invalidateActiveRequest(p); }
        function resetProviderStreamingState() {}
        function focusInput() {}
        function scrollToBottom(f) {}
        function processNextQueuedMessage() {}
        function persistSessions() { manager.persistSessions(); }
        function sessionIndexById(id) { return manager.sessionIndexById(id); }
        function saveCurrentSessionState(t) { manager.saveCurrentSessionState(t); }
        function switchSession(id) { manager.switchSession(id); }
        function createSession(s, p) { manager.createSession(s, p); }
        function deleteSession(id) { manager.deleteSession(id); }
        function cancelSessionRename() {}
        function clearCurrentOpenCodeSessionIfNeeded() {}
        function stopStreaming() { sender.stopStreaming(); }
        function getSessionProperty(id, k, d) { return manager.getSessionProperty(id, k, d); }
    }

    Chat.Sessions {
        id: manager
        chat: chat
        modeSyncRef: QtObject { function newChatMode() { return "chat"; } function newChatWorkspace() { return ""; } }
        helperCommandsRef: QtObject { property var deleted: []; function deleteSessionSchedules(id) { deleted = deleted.concat([id]); } }
    }
    Chat.SendController { id: sender; chat: chat }

    Chat.UndoNotice {
        id: notice
        chat: chat
        width: 500
        timeout: 5000
    }

    SignalSpy {
        id: deletedSpy
        target: chat
        signalName: "sessionDeleted"
    }

    readonly property var projectList: [{"id": "p-work", "name": "Work", "color": "#3daee9"}, {"id": "p-home", "name": "Home", "color": "#f67400"}]

    function session(id, projectId, text, extra) {
        return Object.assign({"value": id, "text": text, "projectId": projectId || "", "source": "chat",
                              "messages": [{"role": "user", "content": "in " + text}]}, extra || {});
    }

    function setUp(list, open) {
        notice.dismiss();
        chat.projects.list = projectList.slice();
        chat.projects.view = "p-work";
        chat.sessions = list;
        chat.currentSessionId = open;
        chat.messages = list[manager.sessionIndexById(open)].messages;
        chat.loading = false;
        chat.activeRequestSessionId = "";
        manager.helperCommandsRef.deleted = [];
        deletedSpy.clear();
    }

    function ids() {
        return chat.sessions.map(function(s) { return s.value; }).join(",");
    }

    function test_1_the_project_and_its_chats_go_and_undo_brings_them_back() {
        setUp([session("a", "p-work", "Report"), session("b", "", "Loose"), session("c", "p-work", "Budget", {"archived": true}),
               session("d", "p-home", "Garden")], "a");
        compare(chat.projects.chatsIn("p-work").length, 2, "archived chats count too");
        var before = ids();

        chat.projects.removeWithChats("p-work");
        compare(chat.projects.byId("p-work"), null, "the project is gone");
        compare(ids(), "b,d", "its chats are gone, the others stay");
        compare(deletedSpy.count, 2, "each through the chat delete path (memories and images listen to it)");
        compare(manager.helperCommandsRef.deleted.sort().join(","), "a,c", "and their schedules");
        verify(chat.currentSessionId === "b" || chat.currentSessionId === "d", "another chat is open");
        compare(chat.projects.view, "all");
        verify(notice.undoable !== null && notice.undoable.kind === "project", "Undo is offered");
        compare(findChild(notice, "undoText").text, "Project “Work” and its 2 chats deleted");

        notice.undo();
        verify(chat.projects.byId("p-work") !== null, "the project is back");
        compare(chat.projects.list.map(function(p) { return p.id; }).join(","), "p-work,p-home", "in its place");
        compare(ids(), before, "the chats are back in their places");
        compare(chat.sessions[0].projectId, "p-work");
        compare(chat.sessions[2].archived, true);
        compare(chat.currentSessionId, "a", "the open chat is open again");
        compare(chat.messages[0].content, "in Report");
    }

    function test_2_when_the_project_has_every_chat_an_empty_one_is_left() {
        setUp([session("a", "p-work", "Report"), session("c", "p-work", "Budget")], "c");
        chat.projects.removeWithChats("p-work");
        compare(chat.sessions.length, 1, "there is always one chat");
        compare(chat.sessions[0].projectId, "");
        compare(chat.sessions[0].messages.length, 0, "a new, empty one");
        compare(chat.currentSessionId, chat.sessions[0].value);
        compare(deletedSpy.count, 2);

        notice.undo();
        compare(ids(), "a,c", "Undo brings both back and drops the empty chat");
        compare(chat.currentSessionId, "c");
    }

    function test_3_a_reply_being_written_into_the_chat_is_stopped_first() {
        setUp([session("a", "p-work", "Report"), session("b", "", "Loose")], "a");
        chat.loading = true;
        chat.activeRequestSessionId = "a";
        var generation = chat.requestGeneration;
        chat.projects.removeWithChats("p-work");
        compare(chat.loading, false, "as when deleting that one chat");
        compare(chat.activeRequestSessionId, "");
        verify(chat.requestGeneration > generation, "its callbacks can no longer write anywhere");
        compare(ids(), "b");
    }

    function test_4_keeping_the_chats_is_still_the_plain_delete() {
        setUp([session("a", "p-work", "Report"), session("b", "", "Loose")], "a");
        chat.projects.remove("p-work");
        compare(ids(), "a,b");
        compare(chat.sessions[0].projectId, "");
        compare(deletedSpy.count, 0);
        compare(findChild(notice, "undoText").text, "Project “Work” deleted; its chats were kept");
        notice.undo();
        compare(chat.sessions[0].projectId, "p-work");
    }

    // The first item under `item` with this objectName, or null.
    function findChild(item, objectName) {
        if (!item)
            return null;
        if (item.objectName === objectName)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findChild(kids[i], objectName);
            if (found)
                return found;
        }
        return null;
    }
}
