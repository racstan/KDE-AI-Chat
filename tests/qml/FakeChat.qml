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
