.pragma library

// Every keyboard shortcut of the chat popup, in one place: ChatShortcuts.qml
// binds them and Settings → Appearance lists them. `id` is what
// ChatShortcuts.qml looks the keys up by; `text` is a plain English label
// that the callers pass through i18n() (see ConfigAppearance.qml).
// "/" (templates) is a key of the input itself (Composer.qml); the browsing
// keys are handled by the message list and the input (ChatView.qml).
var shortcuts = [
    {id: "newChat", keys: "Ctrl+N", text: "New chat"},
    {id: "history", keys: "Ctrl+H", text: "Show or hide the history"},
    {id: "info", keys: "Ctrl+I", text: "Show or hide the chat info panel"},
    {id: "focusInput", keys: "Ctrl+L", text: "Focus the message input"},
    {id: "stop", keys: "Esc", text: "Stop the reply; cancel an edit"},
    {id: "regenerate", keys: "Ctrl+Shift+R", text: "Regenerate the last reply"},
    {id: "copyReply", keys: "Ctrl+Shift+C", text: "Copy the last reply"},
    {id: "nextChat", keys: "Ctrl+PgDown", text: "Next chat"},
    {id: "prevChat", keys: "Ctrl+PgUp", text: "Previous chat"},
    {id: "settings", keys: "Ctrl+,", text: "Open the settings"},
    {id: "editLast", keys: "Ctrl+E", text: "Edit your last message"},
    {id: "browseUp", keys: "Up", text: "Previous message (input empty)"},
    {id: "browseDown", keys: "Down", text: "Next message; past the latest, back to the input"},
    {id: "firstMessage", keys: "PgUp", text: "Jump to the first message"},
    {id: "latestMessage", keys: "PgDown", text: "Jump to the latest message"}
];

function keysFor(id) {
    for (var i = 0; i < shortcuts.length; i++) {
        if (shortcuts[i].id === id)
            return shortcuts[i].keys;
    }
    return "";
}

// Index of the newest assistant reply in `messages`, or -1.
function lastReplyIndex(messages) {
    for (var i = (messages || []).length - 1; i >= 0; i--) {
        var role = messages[i].role || "";
        if ((role === "assistant" || role === "opencode_assistant") && messages[i].content)
            return i;
    }
    return -1;
}

// Id of the chat `delta` places away from the current one in `sessions`
// (archived chats skipped), wrapping around; "" when there is no other chat.
function neighbourSessionId(sessions, currentId, delta) {
    var ids = [];
    for (var i = 0; i < (sessions || []).length; i++) {
        if (!sessions[i].archived || sessions[i].value === currentId)
            ids.push(sessions[i].value);
    }
    var at = ids.indexOf(currentId);
    if (ids.length < 2 || at < 0)
        return "";
    return ids[(at + delta + ids.length) % ids.length];
}
