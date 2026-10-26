.pragma library

// "Read aloud" from the chat: a message's button (MessageActions.qml), the
// right-click menu of message text (MessageText.qml) and the shortcut
// (ChatShortcuts.qml). `chat` is the widget root: voiceManagerRef reads
// aloud (VoiceManager.qml), playingMessageIndex marks the message.

// Reads `text` (the selection, or the message) of message `index`, or stops
// when that message is being read. Returns true when it started reading.
function toggle(chat, index, text) {
    var voice = chat ? chat.voiceManagerRef : null;
    if (!voice)
        return false;
    if (voice.isPlaying && chat.playingMessageIndex === index) {
        voice.stopTTS();
        chat.playingMessageIndex = -1;
        return false;
    }
    if (!String(text || "").trim())
        return false;
    chat.playingMessageIndex = index;
    voice.playTTS(String(text));
    return true;
}

// The text the shortcut reads: the selection in the focused text (a message,
// the composer or an edit box), else the message picked with Up/Down, else
// the last reply. {text, index} (index -1: not a message) or null.
function shortcutTarget(focusItem, messages, pickedIndex, lastReplyIndex) {
    var selected = focusItem && typeof focusItem.selectedText === "string" ? focusItem.selectedText : "";
    if (selected.trim()) {
        var index = typeof focusItem.messageIndex === "number" ? focusItem.messageIndex : -1;
        return {"text": selected, "index": index};
    }
    var list = messages || [];
    var at = pickedIndex >= 0 && pickedIndex < list.length ? pickedIndex : lastReplyIndex;
    if (at >= 0 && at < list.length && String(list[at].content || "").trim())
        return {"text": String(list[at].content), "index": at};
    return null;
}
