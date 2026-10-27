// Incognito chats (chat/Incognito.qml): never written to disk, no memories in
// or out, not named by the model, gone when left; leaving one with messages
// asks first (chat/IncognitoLeaveDialog.qml); the header marks it
// (chat/IncognitoBadge.qml). The chat logic runs on a stand-in root with the
// real chat/Sessions.qml and a real store/ChatStore.qml writing to
// build/test-chats/, whose folder is listed afterwards.
import QtQuick
import QtQuick.Layouts
import QtTest
import Qt.labs.folderlistmodel
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

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

    readonly property string folder: decodeURIComponent(String(Qt.resolvedUrl("../../build/test-chats/")).replace(/^file:\/\//, ""))
        + "applet-incognito-" + Date.now()

    // What the store was asked to save (ids per call) and the helper commands run.
    property var saves: []
    property var helperCalls: []
    property var written: []

    Store.ChatStore {
        id: realStore
        directory: root.folder
        saveDelay: 10
        runHelper: function(command, payload, onDone) { root.helperCalls = root.helperCalls.concat([{command: command, payload: payload}]); if (onDone) onDone(""); }
        onFileWritten: function(name) { root.written = root.written.concat([name]); }
    }

    // The stand-in for main.qml: its state and the forwarders these modules call.
    QtObject {
        id: chat
        property var plasmoid: QtObject { property var configuration: ({"lastSessionId": "", "autoNameChats": true, "incognitoAskBeforeLeaving": true}) }
        property var sessions: []
        property string currentSessionId: ""
        property string currentSessionTitle: ""
        property var messages: []
        property bool loading: false
        property var activeXhr: null
        property int requestGeneration: 0
        property string activeRequestSessionId: ""
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
        property bool historyOnlyMode: false
        property bool historySidePanel: false
        property var voiceManagerRef: null
        property var msgListViewRef: null
        property bool userScrolledUp: false
        property string sessionHistoryLoadError: ""
        property bool sessionHistoryLoadBlocked: false
        property bool sessionSourceInferred: false
        property var projects: null
        readonly property int maxMessageChars: 2000000
        property var streamBuffer: QtObject { function clear() {} function flush() {} }
        property var chatStore: realStore
        // store/Storage.qml: save() is recorded, then handed to the real store.
        property var store: QtObject {
            function save(list) {
                root.saves = root.saves.concat([list.map(function(s) { return s.value; })]);
                realStore.save(list);
            }
            function runHelper(command, payload, onDone) { realStore.runHelper(command, payload, onDone); }
        }
        property var memoryStore: QtObject {
            property bool enabled: true
            property var list: [{"id": "m-1", "text": "I live in Lisbon", "scope": "all", "enabled": true}]
            property int adds: 0
            function add(fields, callback) { adds++; callback(true, {"added": ["m-2"]}); }
            function byId(id) { return null; }
        }
        readonly property var memory: memoryModule
        readonly property var incognito: incognitoModule
        signal sessionDeleted(var session, int index)
        signal messagesDropped(string sessionId, var messages)
        function applySessionSource(s) { return "chat"; }
        function invalidateActiveRequest(p) {}
        function focusInput() {}
        function scrollToBottom(f) {}
        function processNextQueuedMessage() {}
        function persistSessions() { manager.persistSessions(); }
        function sessionIndexById(id) { return manager.sessionIndexById(id); }
        function saveCurrentSessionState(t) { manager.saveCurrentSessionState(t); }
        function switchSession(id, then) { manager.switchSession(id, then); }
        function createSession(s, p, i) { manager.createSession(s, p, i); }
        function cancelSessionRename() {}
        function getSessionProperty(id, k, d) { return manager.getSessionProperty(id, k, d); }
        function setSessionProperty(id, k, v) { manager.setSessionProperty(id, k, v); }
        function openCodeBaseUrl() { return ""; }
        function getEffectiveProvider() { return "openai"; }
        function getProviderConfig() { return {"model": "m", "baseUrl": "http://127.0.0.1:9", "apiKey": "k"}; }
    }

    Chat.Sessions {
        id: manager
        chat: chat
        modeSyncRef: QtObject { function newChatMode() { return "provider"; } function newChatWorkspace() { return ""; } }
        helperCommandsRef: QtObject { function deleteSessionSchedules(id) {} }
    }
    Chat.SessionTitles { id: titles; chat: chat }
    Chat.Memory { id: memoryModule; chat: chat }
    Chat.Incognito { id: incognitoModule; chat: chat }
    Chat.IncognitoLeaveDialog { id: leaveDialog; chat: chat }

    FolderListModel {
        id: listing
        folder: "file://" + root.folder
        showDirs: true
        showHidden: true
    }

    SignalSpy { id: askSpy; target: incognitoModule; signalName: "leaveRequested" }

    // The header with the incognito mark, on the usual stand-in (tests/qml/FakeChat.qml).
    FakeChat { id: fake }
    Rectangle {
        anchors.fill: parent
        visible: popup.visible
        color: Kirigami.Theme.backgroundColor
    }
    ColumnLayout {
        id: popup
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        visible: false
        Chat.ChatHeader { id: header; chat: fake }
        Chat.ChatBody { id: body; chat: fake; Layout.fillWidth: true; Layout.fillHeight: true }
    }

    HarnessTestCase {
        name: "Incognito"

        // Lists the chat folder again (it may not have existed when last listed).
        function relist() {
            listing.folder = "";
            listing.folder = "file://" + root.folder;
            tryVerify(function() { return listing.status === FolderListModel.Ready && listing.count > 0; });
        }

        function files() {
            var names = [];
            for (var i = 0; i < listing.count; i++)
                names.push(listing.get(i, "fileName"));
            return names;
        }

        function initTestCase() {
            var ready = false;
            realStore.prepare(function() { ready = true; });
            verify(ready);
            // One ordinary chat, stored.
            manager.createSession(true);
            chat.messages = [{"id": "m-a", "role": "user", "content": "keep me", "at": 1}];
            manager.saveCurrentSessionState(true);
            realStore.flush();
            relist();
            verify(files().indexOf("index.ini") >= 0, files().join(", "));
        }

        function test_1_nothing_of_an_incognito_chat_is_written() {
            var stored = chat.currentSessionId;
            compare(chat.plasmoid.configuration.lastSessionId, stored);
            root.saves = [];
            root.written = [];
            incognitoModule.start();
            var id = chat.currentSessionId;
            verify(id.indexOf("s-incognito-") === 0, id);
            verify(incognitoModule.active);
            compare(chat.sessions[0].incognito, true);
            compare(chat.sessions[0].source, "provider", "it starts in the main mode");
            // A conversation in it: the title from the first message, a reply, saved state.
            chat.messages = [{"id": "m-1", "role": "user", "content": "my secret plan", "at": 2}];
            titles.nameChatFromFirstMessage("my secret plan");
            compare(chat.currentSessionTitle, "My secret plan");
            chat.messages = chat.messages.concat([{"id": "m-2", "role": "assistant", "content": "noted", "at": 3}]);
            manager.saveCurrentSessionState(true);
            manager.setSessionProperty(id, "chatSystemPrompt", "be brief");
            realStore.flush();
            wait(50);
            compare(root.saves.length, 0, "the store is never asked to save while only the incognito chat changes");
            compare(root.written.length, 0, "no file is written");
            compare(chat.plasmoid.configuration.lastSessionId, stored, "not remembered as the last chat");
            // Memories: none used, none added.
            verify(!memoryModule.activeFor(id));
            compare(memoryModule.forRequest(id).block, "");
            verify(!memoryModule.remember("remember my plan", "all", id, null));
            compare(chat.memoryStore.adds, 0);
            // The model is not asked to name it.
            titles.maybeGenerateChatTitle();
            verify(!titles.requested[id]);
            // A change to a stored chat is saved, without the incognito chat.
            manager.setSessionProperty(stored, "chatSystemPrompt", "x");
            compare(root.saves.length, 1);
            compare(root.saves[0], [stored]);
            realStore.flush();
            var everything = JSON.stringify(root.written) + realStore._read("index.ini", "sessions");
            verify(everything.indexOf("incognito") < 0 && everything.indexOf("secret") < 0, everything);
            relist();
            compare(files().filter(function(n) { return n.indexOf("incognito") >= 0; }), [], files().join(", "));
            // As after a restart: the folder holds only the stored chat.
            var reader = Qt.createQmlObject('import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store; Store.ChatStore {}', root, "reader.qml");
            reader.directory = root.folder;
            var loaded = reader.loadAll();
            compare(loaded.map(function(s) { return s.value; }), [stored]);
            reader.destroy();
        }

        function test_2_leaving_asks_first_and_the_chat_is_gone() {
            var id = chat.currentSessionId;
            verify(incognitoModule.isIncognito(id));
            var stored = chat.sessions.filter(function(s) { return !incognitoModule.isIncognito(s.value); })[0].value;
            askSpy.clear();
            manager.switchSession(stored);
            compare(askSpy.count, 1, "asked before leaving");
            compare(chat.currentSessionId, id, "still open while the question is up");
            tryVerify(function() { return leaveDialog.opened; });
            showIncognitoChat();
            wait(100);
            screenshot(root.Window.window.contentItem, "incognito-leave-dialog");  // the overlay too
            mouseClick(findChild(leaveDialog.contentItem, "incognitoStayButton"));
            tryVerify(function() { return !leaveDialog.opened; });
            compare(chat.currentSessionId, id, "Stay keeps it");
            popup.visible = false;
            // Leave: the chat is gone, with its pictures (helper incognito_cleanup).
            root.helperCalls = [];
            manager.createSession(true);
            compare(askSpy.count, 2);
            tryVerify(function() { return leaveDialog.opened; });
            mouseClick(findChild(leaveDialog.contentItem, "incognitoLeaveButton"));
            tryVerify(function() { return !leaveDialog.opened; });
            verify(!incognitoModule.isIncognito(chat.currentSessionId));
            compare(manager.sessionIndexById(id), -1, "gone from the chat list");
            var cleanup = root.helperCalls.filter(function(c) { return c.command === "incognito_cleanup"; });
            compare(cleanup.length, 1);
            compare(cleanup[0].payload.chat, id);
            compare(chat.plasmoid.configuration.incognitoAskBeforeLeaving, true);
        }

        function test_3_dont_ask_again_and_empty_chats_go_without_asking() {
            askSpy.clear();
            incognitoModule.start();
            var empty = chat.currentSessionId;
            manager.createSession(true);
            compare(askSpy.count, 0, "an empty incognito chat goes without a question");
            compare(manager.sessionIndexById(empty), -1);
            incognitoModule.start();
            chat.messages = [{"id": "m-9", "role": "user", "content": "x", "at": 1}];
            incognitoModule.close();
            compare(askSpy.count, 1);
            tryVerify(function() { return leaveDialog.opened; });
            mouseClick(leaveDialog.dontAskAgain);
            mouseClick(findChild(leaveDialog.contentItem, "incognitoLeaveButton"));
            tryVerify(function() { return !leaveDialog.opened; });
            compare(chat.plasmoid.configuration.incognitoAskBeforeLeaving, false);
            verify(!incognitoModule.active, "closed");
            incognitoModule.start();
            chat.messages = [{"id": "m-10", "role": "user", "content": "y", "at": 1}];
            incognitoModule.close();
            compare(askSpy.count, 1, "not asked again");
            verify(!incognitoModule.active);
            chat.plasmoid.configuration.incognitoAskBeforeLeaving = true;
        }

        // The popup with an incognito chat open (on FakeChat).
        function showIncognitoChat() {
            popup.visible = true;
            fake.messages = [{role: "user", content: "Something private", time: "10:01"}, {role: "assistant", content: "Not saved.", time: "10:01"}];
            fake.sessions = [{value: "s-incognito-1-1", text: "Something private", incognito: true, updatedAt: Date.now()},
                             {value: "a", text: "Trip planning", updatedAt: Date.now()}];
            fake.currentSessionId = "s-incognito-1-1";
            fake.currentSessionTitle = "Something private";
        }

        function test_4_the_header_marks_it() {
            showIncognitoChat();
            var badge = findChild(header, "incognitoBadge");
            tryVerify(function() { return badge.visible; });
            compare(findChild(badge, "incognitoLabel").text, "Incognito — not saved");
            verify(findChild(badge, "incognitoLabel").visible);
            verify(!findChild(header, "incognitoButton").visible, "no New incognito button while one is open");
            wait(100);
            screenshot(root, "incognito-chat");
            // Narrow: the mark keeps its icon and close button.
            root.width = 500;
            wait(100);
            verify(badge.visible);
            verify(badge.x + badge.width <= header.width);
            screenshot(root, "incognito-chat-narrow");
            root.width = 760;
            // An ordinary chat: no mark, the button to start one instead.
            fake.currentSessionId = "a";
            verify(!badge.visible);
            verify(findChild(header, "incognitoButton").visible);
            fake.calls = [];
            mouseClick(findChild(header, "incognitoButton"));
            compare(fake.calls.filter(function(c) { return c.name === "create"; })[0].args, [true, "", true]);
            popup.visible = false;
        }
    }
}
