// The chat logic split out of main.qml (chat/Sessions.qml, SessionTitles.qml,
// SendController.qml, MessageEdits.qml, ChatNavigation.qml, DirectRequest.qml,
// Attachments.qml), driven through a minimal stand-in for the widget root:
// creating, switching, renaming and deleting chats, regenerating and deleting
// messages, and the view's labels.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

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
        readonly property int maxMessageChars: 2000000
        property var streamBuffer: QtObject { function clear() {} function flush() {} }
        property var store: QtObject { property int saves: 0; function save(s) { saves++; } }
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
    Chat.SessionTitles { id: titles; chat: chat }
    Chat.SendController { id: sender; chat: chat }
    Chat.MessageEdits { id: edits; chat: chat }
    Chat.ChatNavigation { id: nav; chat: chat }
    Chat.DirectRequest { id: direct; chat: chat }
    Chat.Attachments { id: att; chat: chat }

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
}
