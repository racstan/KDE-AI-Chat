.pragma library

// Totals for the Chat info panel, summed from what is stored on the messages.
// Token counts and costs are whatever the provider reported for each reply
// (message.tokens, message.cost); nothing is estimated, so a reply the
// provider gave no usage for adds nothing and is counted in `replies` but not
// in `repliesWithUsage`.
//
// Plain JavaScript on purpose (tested with node): no QML globals, no .import.

// messages: the chat's message list. session: {createdAt, updatedAt} (ms).
// Returns {messages, replies, repliesWithUsage, inputTokens, outputTokens,
// hasTokens, cacheRead, cacheWrite, hasCache (prompt-cache tokens, a part of the input), cost, hasCost, models, createdAt, lastActive} where times are ms
// or 0 when unknown.
function summarize(messages, session) {
    var list = messages || [];
    var stats = {"messages": 0, "replies": 0, "repliesWithUsage": 0, "inputTokens": 0, "outputTokens": 0, "cacheRead": 0, "cacheWrite": 0, "hasCache": false,
                 "hasTokens": false, "cost": 0, "hasCost": false, "models": [], "createdAt": 0, "lastActive": 0};
    var firstAt = 0, lastAt = 0;
    for (var i = 0; i < list.length; i++) {
        var m = list[i];
        if (!m)
            continue;
        if (m.at > 0) {
            if (!firstAt || m.at < firstAt) firstAt = m.at;
            if (m.at > lastAt) lastAt = m.at;
        }
        if (m.role !== "user" && m.role !== "assistant")
            continue;
        stats.messages++;
        if (m.role !== "assistant")
            continue;
        stats.replies++;
        if (m.model && stats.models.indexOf(String(m.model)) < 0)
            stats.models.push(String(m.model));
        if (m.tokens && (m.tokens.input !== undefined || m.tokens.output !== undefined)) {
            stats.repliesWithUsage++;
            stats.hasTokens = true;
            stats.inputTokens += Number(m.tokens.input) || 0;
            stats.outputTokens += Number(m.tokens.output) || 0;
            var cache = m.tokens.cache;
            if (cache && (Number(cache.read) > 0 || Number(cache.write) > 0)) {
                stats.hasCache = true;
                stats.cacheRead += Number(cache.read) || 0;
                stats.cacheWrite += Number(cache.write) || 0;
            }
        }
        if (m.cost !== undefined && m.cost !== null && isFinite(Number(m.cost)) && Number(m.cost) > 0) {
            stats.hasCost = true;
            stats.cost += Number(m.cost);
        }
    }
    var s = session || {};
    stats.createdAt = Number(s.createdAt) || firstAt;
    stats.lastActive = Number(s.updatedAt) || lastAt || stats.createdAt;
    return stats;
}

// "1,234" style grouping that does not depend on the locale in tests.
function formatCount(n) {
    return String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// A cost in dollars with enough digits for fractions of a cent.
function formatCost(dollars) {
    var d = Number(dollars) || 0;
    if (d >= 1)
        return "$" + d.toFixed(2);
    if (d >= 0.01)
        return "$" + d.toFixed(3);
    return "$" + d.toFixed(5);
}
