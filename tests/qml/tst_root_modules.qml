// The chat logic split out of main.qml (chat/Sessions.qml, SessionTitles.qml,
// SendController.qml, MessageEdits.qml, ChatNavigation.qml, DirectRequest.qml,
// Attachments.qml), driven through a minimal stand-in for the widget root:
// creating, switching, renaming and deleting chats, regenerating and deleting
// messages, and the view's labels.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/chat/ReplyState.js" as ReplyState

TestCase {
    id: tc
    name: "RootModules"

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
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
        property bool historyOnlyMode: false
        property bool historySidePanel: false
        property var voiceManagerRef: null
        property var attachedFiles: []
        property var msgListViewRef: null
        property bool userScrolledUp: false
        property string sessionHistoryLoadError: ""
        property bool sessionHistoryLoadBlocked: false
        property bool sessionSourceInferred: false
        property var projects: null
        property string privacyNotice: ""
        property var chatStore: QtObject {
            property string indexProblem: ""
            property bool recoveredFromBackup: false
            property var stored: null
            property int rebuilt: 0
            function loadAll() { return stored; }
            function rebuildIndex(done) { rebuilt++; indexProblem = ""; stored = [{value: "r-1", text: "Back", source: "provider", messages: []}]; done(1); }
        }
        readonly property int maxMessageChars: 2000000
        property var streamBuffer: QtObject { function clear() {} function flush() {} }
        property var store: QtObject { property int saves: 0; property var last: null; function save(s) { saves++; last = s; } }
        property int sent: 0
        property var errors: []
        signal sessionDeleted(var session, int index)
        signal messagesDropped(string sessionId, var messages)
        function applySessionSource(s) { return "chat"; }
        function invalidateActiveRequest(p) { sender.invalidateActiveRequest(p); }
        function resetProviderStreamingState() {}
        function focusInput() {}
        function scrollToBottom(f) {}
        function processNextQueuedMessage() { sender.processNextQueuedMessage(); }
        function persistSessions() { manager.persistSessions(); }
        function sortSessionsByUpdated() { manager.sortSessionsByUpdated(); }
        function sessionIndexById(id) { return manager.sessionIndexById(id); }
        function saveCurrentSessionState(t) { manager.saveCurrentSessionState(t); }
        function switchSession(id) { manager.switchSession(id); }
        function cancelSessionRename() { titles.cancelSessionRename(); }
        function clearCurrentOpenCodeSessionIfNeeded() { manager.clearCurrentOpenCodeSessionIfNeeded(); }
        function stopStreaming() { sender.stopStreaming(); }
        function sendMessageByIndex(i) { sent++; }
        function pushErrorMessage(t) { errors = errors.concat([t]); }
        function findRequestMessage(r, f, id) { return -1; }
        function getHelperPath() { return ""; }
        function getSessionProperty(id, k, d) { return manager.getSessionProperty(id, k, d); }
        function nameChatFromFirstMessage(t) { titles.nameChatFromFirstMessage(t); }
    }

    Chat.Sessions {
        id: manager
        chat: chat
        modeSyncRef: QtObject { function newChatMode() { return "chat"; } function newChatWorkspace() { return ""; } }
        helperCommandsRef: QtObject { property int n: 0; function deleteSessionSchedules(id) { n++; } }
    }
    Chat.PartialSave { id: partial; chat: chat; interval: 30 }
    Chat.SessionTitles { id: titles; chat: chat }
    Chat.SendController { id: sender; chat: chat }
    Chat.MessageEdits { id: edits; chat: chat }
    Chat.ChatNavigation { id: nav; chat: chat }
    Chat.DirectRequest { id: direct; chat: chat }
    Chat.Attachments { id: att; chat: chat }

    // A chat list that could not be read blocks saving until it is rebuilt from the chat files.
    function test_damaged_chat_list_blocks_saving_until_rebuilt() {
        chat.chatStore.indexProblem = "damaged";
        chat.chatStore.stored = [];
        manager.loadSessions();
        verify(chat.sessionHistoryLoadBlocked);
        verify(chat.sessionHistoryLoadError !== "");
        var saves = chat.store.saves;
        manager.persistSessions();
        compare(chat.store.saves, saves, "nothing is saved while blocked");

        manager.resetUnreadableSessionHistory();
        compare(chat.chatStore.rebuilt, 1);
        verify(!chat.sessionHistoryLoadBlocked);
        compare(chat.sessions[0].value, "r-1");
        compare(chat.sessions[0].source, "provider", "the mode is kept");

        chat.chatStore.recoveredFromBackup = true;
        manager.loadSessions();
        verify(chat.privacyNotice !== "", "a list restored from its backup is announced");
        chat.chatStore.recoveredFromBackup = false;
        chat.privacyNotice = "";
    }

    function test_sessions_flow() {
        manager.createSession(true);
        manager.createSession(true);
        compare(chat.sessions.length, 2);
        var second = chat.currentSessionId;
        chat.messages = [{"role": "user", "content": "hi", "at": Date.now()}, {"role": "assistant", "content": "yo", "at": Date.now()}];
        manager.saveCurrentSessionState(true);
        var first = chat.sessions[1].value;
        manager.switchSession(first);
        compare(chat.currentSessionId, first);
        compare(chat.messages.length, 0);
        manager.switchSession(second);
        compare(chat.messages.length, 2);
        titles.startSessionRename(second);
        chat.editingSessionDraft = "Renamed";
        titles.saveSessionRename(second);
        compare(chat.currentSessionTitle, "Renamed");
        // A chat's mode (source) never changes, even when overrides name one.
        verify(manager.setSessionOverrides(second, {"chatSystemPrompt": "x", "source": "pi"}));
        compare(manager.getSessionProperty(second, "chatSystemPrompt", ""), "x");
        compare(chat.sessions[manager.sessionIndexById(second)].source, "chat");
        edits.regenerateResponse(1);
        compare(chat.messages.length, 1);
        compare(chat.sent, 1);
        edits.deleteMessage(0);
        compare(chat.messages.length, 0);
        manager.deleteSession(second);
        compare(chat.sessions.length, 1);
        compare(chat.currentSessionId, first);
        compare(manager.helperCommandsRef.n, 1);
        verify(manager.sessionSubtitle(chat.sessions[0]).indexOf("Updated ") === 0);
    }

    // Archiving the open chat opens the latest chat still in the list (or a new
    // one); restoring brings it back; a new chat can start in a project.
    function test_archive_and_restore() {
        chat.sessions = [];
        manager.createSession(true);
        var older = chat.currentSessionId;
        manager.createSession(true);
        var newer = chat.currentSessionId;
        manager.setSessionArchived(newer, true);
        compare(chat.sessions[manager.sessionIndexById(newer)].archived, true);
        compare(chat.currentSessionId, older, "the open chat left the list: the other one opens");
        manager.setSessionArchived(older, true);
        compare(chat.sessions.length, 3, "nothing left in the list: a new chat");
        verify(chat.currentSessionId !== older && chat.currentSessionId !== newer);
        manager.setSessionArchived(newer, false);
        compare(chat.sessions[manager.sessionIndexById(newer)].archived, false, "restored");
        compare(chat.sessions[manager.sessionIndexById(newer)].source, "chat", "its mode is kept");
        // New chat in a project: no copy of the main default folder when the project has one.
        chat.projects = {"byId": function(id) { return id === "p-1" ? {"id": "p-1", "folder": "/srv/p"} : null; }};
        manager.createSession(true, "p-1");
        compare(chat.sessions[0].projectId, "p-1");
        compare(chat.sessions[0].openCodeWorkspaceCwd, "");
        manager.createSession(true, "p-gone");
        compare(chat.sessions[0].projectId, "", "an unknown project means none");
        chat.projects = null;
        chat.sessions = [];
        chat.currentSessionId = "";
    }

    function test_nav_and_direct() {
        chat.messages = [{"role": "user", "content": "a", "at": Date.now(), "time": ""}];
        verify(nav.dayDividerLabelForIndex(0).indexOf("Today (1)") === 0);
        compare(nav.formatTokensUsage({"input": 3, "output": 4}, 0), "Input: 3 | Output: 4");
        compare(direct.limitContextMessages([1, 2, 3]).length, 3);
        compare(direct.sessionMessages(chat.currentSessionId).length, 1);
        compare(att.fileIconName("x.pdf"), "document-pdf");
        verify(att.attachmentsReadyToSend());
        verify(att.getDocExtractorPath().endsWith("/contents/ui/doc_extractor.py"));
    }

    // A message keeps the messages it quoted when it is edited or sent again.
    function test_edit_and_resend_keep_the_quotes() {
        var quotes = [{"id": "m-1", "role": "assistant", "text": "Use rsync."}];
        chat.sent = 0;
        chat.messages = [{"role": "user", "content": "first", "quotes": quotes, "at": 1}, {"role": "assistant", "content": "reply", "at": 2}];
        chat.editingMessageIndex = 0;
        chat.editingDraft = "first, edited";
        edits.saveEditedMessage();
        compare(chat.messages.length, 1, "the reply after it is dropped");
        compare(chat.messages[0].content, "first, edited");
        compare(JSON.stringify(chat.messages[0].quotes), JSON.stringify(quotes));
        compare(chat.sent, 1);
        chat.messages = chat.messages.concat([{"role": "assistant", "content": "reply again", "at": 3}]);
        edits.regenerateResponse(0, "");
        compare(JSON.stringify(chat.messages[0].quotes), JSON.stringify(quotes), "resend: still quoted");
        compare(chat.sent, 2);
        chat.sent = 0;
        chat.messages = [];
    }

    // A chat started with "/image <prompt>" is named after the prompt, not the command.
    function test_image_chat_title() {
        chat.sessions = [];
        manager.createSession(true);
        chat.messages = [{"role": "user", "content": "/image sun hugging moon", "at": 1}];
        titles.nameChatFromFirstMessage("/image sun hugging moon");
        compare(chat.currentSessionTitle, "Image: Sun hugging moon");
        compare(chat.sessions[0].text, "Image: Sun hugging moon");
        // The model is asked to name the prompt; its title gets the same prefix.
        var source = titles.titleSource("/image sun hugging moon");
        compare(source.text, "sun hugging moon");
        verify(source.image);
        verify(titles.applyAutoTitle(chat.currentSessionId, titles.imageTitle("Sun Embracing the Moon", source.image), true));
        compare(chat.currentSessionTitle, "Image: Sun Embracing the Moon");
        // Other text is unchanged, including a path that starts with /image.
        compare(titles.titleSource("/images/cat.png is broken").text, "/images/cat.png is broken");
        verify(!titles.titleSource("how do I make an /image").image);
        chat.messages = [];
        chat.sessions = [];
        chat.currentSessionId = "";
        chat.currentSessionTitle = "";
    }

    // A message over the display limit keeps its full text: only the view cuts it, and a save writes it whole.
    function test_long_message_is_saved_in_full() {
        var big = new Array(2000002).join("x") + "END";
        verify(big.length > chat.maxMessageChars);
        chat.sessionHistoryLoadError = "";
        chat.chatStore.stored = [{value: "big-1", text: "Big", source: "provider", messages: [{role: "assistant", content: big, at: 1}]}];
        manager.loadSessions();
        compare(chat.messages[0].content.length, big.length, "loaded whole");
        verify(chat.sessionHistoryLoadError !== "", "the shortened view is announced");
        var shown = ReplyState.displayContent(chat.messages[0].content, chat.maxMessageChars);
        compare(shown.length, chat.maxMessageChars + "\n[message truncated]".length, "displayed cut");
        verify(shown.indexOf("END") < 0);
        manager.saveCurrentSessionState(true);
        compare(chat.store.last[0].messages[0].content.length, big.length, "saved whole");
        chat.sessionHistoryLoadError = "";
        chat.sessions = [];
        chat.messages = [];
        chat.currentSessionId = "";
    }

    // A reply that is streaming is saved every interval with streaming: true; chat.messages is untouched.
    function test_streaming_reply_saved_partially_and_loads_interrupted() {
        chat.sessions = [];
        manager.createSession(true);
        var id = chat.currentSessionId;
        chat.messages = [{role: "user", content: "q", at: 1}, {role: "assistant", content: "", at: 2}];
        chat.currentStreamIndex = 1;
        chat.currentStreamText = "half an ans";
        chat.store.last = null;
        chat.streamingResponse = true;
        tryVerify(function() { return chat.store.last !== null; }, 2000);
        var saved = chat.store.last.filter(function(s) { return s.value === id; })[0];
        compare(saved.messages[1].content, "half an ans");
        compare(saved.messages[1].streaming, true);
        compare(chat.messages[1].content, "", "the open chat is not changed");
        verify(chat.messages[1].streaming === undefined);

        chat.streamingResponse = false;
        chat.store.last = null;
        wait(100);
        compare(chat.store.last, null, "no more saves once the reply ends");

        // What was saved loads as interrupted, in any mode, and is not resumed.
        chat.chatStore.stored = JSON.parse(JSON.stringify([saved]));
        manager.loadSessions();
        compare(chat.messages[1].interrupted, true);
        verify(chat.messages[1].streaming === undefined);
        compare(chat.messages[1].content, "half an ans");
        chat.currentStreamIndex = -1;
        chat.currentStreamText = "";
        chat.sessions = [];
        chat.messages = [];
        chat.currentSessionId = "";
    }
}
