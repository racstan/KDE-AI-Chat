.pragma library

// Runs of messages from one sender. The chat view shows the sender's name and
// time on the first message of a run only (like a group chat): your messages,
// or the AI's with the same model. The AI's tool steps, its questions and
// permission requests and its answers are one run until you write something or
// an error comes in. Plain functions on plain objects, so tests run them in node.

function _isRequest(role) {
    return role === "permission_request" || role === "question_request";
}

// Who a message is from: "you", "ai:<model>", a request card as the AI turn it
// belongs to (the nearest message before it that isn't a card), or its own
// (a queued message or an error: always its own heading).
function senderKey(messages, index) {
    var m = messages[index] || {};
    var role = m.role || "";
    if (role === "user")
        return "you";
    // A queued message says so in its header, an error has its own heading.
    if (role === "queued" || role === "error")
        return role + ":" + index;
    if (_isRequest(role)) {
        var j = index - 1;
        while (j >= 0 && _isRequest((messages[j] || {}).role || ""))
            j--;
        if (j >= 0 && (messages[j].role || "") === "assistant")
            return senderKey(messages, j);
        return "request:" + (m.model || "");
    }
    return role + ":" + (m.model || "");
}

// True when the message at `index` begins a run (shows its header).
function startsRun(messages, index) {
    return index <= 0 || senderKey(messages, index) !== senderKey(messages, index - 1);
}
