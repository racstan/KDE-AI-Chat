.pragma library
// Long and unfinished replies. A message longer than the display limit keeps
// its whole text in the chat (and on disk): only the view cuts it. A reply
// still being written is saved now and then with streaming: true; a chat that
// loads with such a message shows it as interrupted and never resumes it.

// `content` as the view shows it: at most `max` characters, with a note when cut.
function displayContent(content, max) {
    var text = String(content === undefined || content === null ? "" : content);
    return max > 0 && text.length > max ? text.substring(0, max) + "\n[message truncated]" : text;
}

// A message saved while its reply was streaming is interrupted now, not streaming.
// Returns whether it was one.
function markInterrupted(message) {
    if (!message || message.streaming !== true)
        return false;
    delete message.streaming;
    message.interrupted = true;
    return true;
}

// `messages` with the streaming reply at `index` holding what has arrived so
// far, marked streaming: what is saved meanwhile. `messages` is not changed.
// null when there is nothing to save yet.
function withPartialReply(messages, index, text, reasoning) {
    if (index < 0 || index >= messages.length)
        return null;
    var copy = messages.slice();
    var reply = Object.assign({}, copy[index]);
    if (reply.role !== "assistant" || (!text && !reasoning))
        return null;
    reply.content = text || reply.content || "";
    if (reasoning)
        reply.reasoning = reasoning;
    reply.streaming = true;
    copy[index] = reply;
    return copy;
}
