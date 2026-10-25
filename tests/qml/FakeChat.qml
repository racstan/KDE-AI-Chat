// A stand-in for the widget root (main.qml) with what the chat view reads,
// for testing chat/ChatView.qml and its delegates offscreen.
import QtQuick
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

QtObject {
    id: fake

    property var messages: []
    property Chat.MessageModel messageModel: Chat.MessageModel {}
    onMessagesChanged: messageModel.sync(messages)

    property int currentStreamIndex: -1
    property string currentStreamText: ""
    property string currentStreamReasoning: ""
    // main.qml's throttled streaming path: deltas wait in streamBuffer and
    // reach currentStreamText at most every 33 ms (applyDelta mirrors
    // main.qml's applyBackendEvent for text_delta/reasoning_delta/done).
    readonly property int maxMessageChars: 2000000
    property Chat.StreamBuffer streamBuffer: Chat.StreamBuffer { target: fake; maxChars: fake.maxMessageChars }
    function applyDelta(event) {
        if (event.type === "text_delta" || event.type === "reasoning_delta")
            streamBuffer.add(event.type === "text_delta" ? "text" : "reasoning", event.delta);
        else if (event.type === "done")
            streamBuffer.flush();
    }
    property string currentStreamExtractedReasoning: ""
    property int editingMessageIndex: -1
    property string editingDraft: ""
    property bool userScrolledUp: false
    property var msgListViewRef: null
    property bool loading: false
    property int playingMessageIndex: -1
    property var voiceManagerRef: null
    property bool voiceEnabled: false
    property bool voiceTtsEnabled: false
    property var calls: []

    // What chat/Composer.qml reads and calls.
    signal clearChatInput()
    property string chatInputText: ""
    property var composerRef: null
    property bool expanded: true
    property bool streamingResponse: false
    property var attachedFiles: []
    function focusInput() {
        Qt.callLater(function() {
            if (fake.composerRef)
                fake.composerRef.focusInput();
        });
    }
    function sendMessage() {
        record("send", [chatInputText]);
        chatInputText = "";
        clearChatInput();
    }
    function attachmentsReadyToSend() { return true; }
    function ensureWalletLoaded() {}
    function checkClipboardForAttachments() {}
    function readClipboardText() { return ""; }
    function removeAttachedFile() { record("removeFile", arguments); }
    function stopStreaming() { record("stop", arguments); }

    // What chat/ChatHeader.qml, RenameRow.qml and SessionList.qml read.
    property bool historyOnlyMode: false
    property bool hideOnWindowDeactivate: true
    property string currentSessionId: "a"
    property string currentSessionTitle: "Trip planning"
    property bool renamingCurrentChat: false
    property string currentChatRenameDraft: ""
    property string editingSessionId: ""
    property string editingSessionDraft: ""
    property var sessions: []
    function sessionSubtitle(s) { return (s.count || 0) + " messages"; }
    function switchSession(id) { record("switch", arguments); currentSessionId = id; }
    function renameCurrentSession() { record("renameCurrent", arguments); }
    function createSession() { record("create", arguments); }
    function jumpOneMessageAbove() {}
    function jumpOneMessageBelow() {}
    function clearCurrentOpenCodeSessionIfNeeded() {}
    function saveCurrentSessionState() {}
    function startSessionRename(id) { editingSessionId = id; }
    function saveSessionRename() { record("saveRename", arguments); editingSessionId = ""; }
    function cancelSessionRename() { editingSessionId = ""; }
    function setSessionArchived() { record("archive", arguments); }
    function deleteSession() { record("deleteSession", arguments); }

    function messageDayKeyAt(i) { return "2026-10-25"; }
    function dayDividerLabelForIndex(i) { return "Today"; }
    function formatMessageTime(m, i) { return m.time || ""; }
    function formatTokensUsage(t, c) { return t.input + " in · " + t.output + " out"; }
    function fileIconName(name) { return "text-x-generic"; }
    function scrollToBottom(force) {
        if (userScrolledUp && !force) return;
        userScrolledUp = false;
        if (msgListViewRef) msgListViewRef.positionViewAtEnd();
    }
    function record(name, args) { calls = calls.concat([{name: name, args: Array.prototype.slice.call(args)}]); }
    function copyTextToClipboard() { record("copy", arguments); }
    function deleteMessage() { record("delete", arguments); }
    function retryFailedMessage() { record("retry", arguments); }
    function regenerateResponse() { record("regenerate", arguments); }
    function saveEditedMessage() { record("saveEdit", arguments); }
    function respondToPermission() { record("permission", arguments); }
    function respondToQuestion() { record("question", arguments); }
    function questionOptionSelected() { return false; }
    function toggleQuestionOption() { record("toggleOption", arguments); }
    function submitQuestionAnswer() { record("submitQuestion", arguments); }
}
