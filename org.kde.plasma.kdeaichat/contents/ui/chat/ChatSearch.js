.pragma library

// Search across all chats of the widget (chat/ChatSearchPanel.qml): chat
// titles and message text, in every chat (archived ones and chats in
// projects too, never an incognito chat). Plain JavaScript (tested with node).
//
// The search runs over the chats already in memory: store/ChatStore.qml
// loads every chat with its messages when the widget starts, so reading the
// chat files again in a helper process would only be slower. One regular
// expression per query (case-insensitive, the query taken literally) finds
// the match in the original text, so the snippet shows it exactly as written.
//
// A result is
//   {chatId, title, archived, projectId, source, kind: "title" | "message",
//    messageId, messageIndex, role, before, match, after, at}
// where before + match + after is the snippet (match is the found text).

var MAX_RESULTS = 100;   // results in all
var PER_CHAT = 5;        // message results per chat
var BEFORE = 40;         // characters of context before the match
var AFTER = 90;          // and after it
var MIN_QUERY = 2;       // shorter queries find nothing (too many hits to be useful)

function _s(value) {
    return value === undefined || value === null ? "" : String(value);
}

// The query as searched: trimmed, runs of spaces as one.
function normalizeQuery(query) {
    return _s(query).replace(/\s+/g, " ").trim();
}

function _escapeRegExp(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// A pattern for the query (spaces match any whitespace), or null when it is too short.
function patternFor(query) {
    var q = normalizeQuery(query);
    if (q.length < MIN_QUERY)
        return null;
    return new RegExp(_escapeRegExp(q).replace(/ /g, "\\s+"), "i");
}

function isIncognito(session) {
    return !!session && (session.incognito === true || _s(session.value).indexOf("s-incognito-") === 0);
}

// The text around a match, on one line: {before, match, after}.
function snippet(text, index, length) {
    var start = Math.max(0, index - BEFORE);
    var end = Math.min(text.length, index + length + AFTER);
    // On one line, without Markdown's marks (code fences and their language, `, **, __, # headings).
    var one = function(t) {
        return t.replace(/```[\w+#.-]*/g, " ").replace(/`|\*\*|__/g, "").replace(/(^|\n)#+ /g, "$1").replace(/\s+/g, " ");
    };
    var before = one(text.substring(start, index));
    var after = one(text.substring(index + length, end));
    // Start at a word when the context was cut.
    if (start > 0) {
        var space = before.indexOf(" ");
        before = "…" + (space >= 0 && space < before.length - 1 ? before.substring(space + 1) : before);
    }
    if (end < text.length)
        after = after + "…";
    return {"before": before, "match": one(text.substr(index, length)), "after": after};
}

function _result(session, kind, extra) {
    return Object.assign({
        "chatId": _s(session.value),
        "title": _s(session.text).replace(/\s+/g, " ").trim(),
        "archived": session.archived === true,
        "projectId": _s(session.projectId),
        "source": _s(session.source),
        "kind": kind,
        "messageId": "",
        "messageIndex": -1,
        "role": "",
        "at": Number(session.updatedAt || session.createdAt || 0)
    }, extra);
}

// Searches `sessions` (chat.sessions) for `query`. Returns {results, more}:
// more is true when results were left out (the per-chat or total limit).
// options: {maxResults, perChat} to change the limits.
function search(sessions, query, options) {
    var pattern = patternFor(query);
    var out = {"results": [], "more": false};
    if (!pattern)
        return out;
    var maxResults = options && options.maxResults > 0 ? options.maxResults : MAX_RESULTS;
    var perChat = options && options.perChat > 0 ? options.perChat : PER_CHAT;
    var list = sessions || [];
    for (var i = 0; i < list.length; i++) {
        var session = list[i];
        if (out.more && out.results.length >= maxResults)
            break;
        if (!session || isIncognito(session))
            continue;
        var title = _s(session.text);
        var found = pattern.exec(title);
        if (found && out.results.length >= maxResults) {
            out.more = true;
            break;
        }
        if (found)
            out.results.push(_result(session, "title", snippet(title, found.index, found[0].length)));
        var messages = session.messages || [];
        var inChat = 0;
        // Newest first: the latest mention is usually the one looked for.
        for (var j = messages.length - 1; j >= 0; j--) {
            var message = messages[j];
            var content = message && typeof message.content === "string" ? message.content : "";
            if (content === "")
                continue;
            found = pattern.exec(content);
            if (!found)
                continue;
            if (inChat >= perChat || out.results.length >= maxResults) {
                out.more = true;
                break;
            }
            inChat++;
            out.results.push(_result(session, "message", Object.assign({
                "messageId": _s(message.id),
                "messageIndex": j,
                "role": _s(message.role),
                "at": Number(message.at || session.updatedAt || 0)
            }, snippet(content, found.index, found[0].length))));
        }
    }
    return out;
}

function escapeHtml(text) {
    return _s(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// The snippet as styled text (Text.StyledText) with the match marked: bold and
// underlined, in the text colour, so it reads in light and dark colour schemes
// alike. (Text.StyledText did not draw a span's background or colour style when
// checked, so the match is marked with what it does draw.) Every part is escaped.
function highlighted(result) {
    return escapeHtml(result.before) + "<b><u>" + escapeHtml(result.match) + "</u></b>" + escapeHtml(result.after);
}
