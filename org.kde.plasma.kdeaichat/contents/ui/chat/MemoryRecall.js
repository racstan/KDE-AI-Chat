.pragma library

// Which memories go with a request. Plain JavaScript on purpose (tested with
// node): no QML globals.
//
// A memory is {id, text, scope: "all" | "project" | "chat", projectId, chatId,
// pinned, enabled, created} (kdeaichat/memory.py). A chat gets the enabled
// memories for every chat, its project's and its own (applicable). Of those,
// recall() sends the pinned ones first, then the ones that best match what
// is being asked (BM25 over the applicable memories), as long as they fit in
// a character budget. Same input, same answer.

var DEFAULT_BUDGET = 2000;
var QUERY_MESSAGES = 3;          // the message being answered and the two before it
var QUERY_CHARS_PER_MESSAGE = 2000;
var HEADING = "## Things the user asked you to remember";

var K1 = 1.2;
var B = 0.75;

var STOPWORDS = {};
("a about above after again against all am an and any are as at be because been before being below between both but by "
 + "can could did do does doing down during each few for from further had has have having he her here hers herself him "
 + "himself his how i if in into is it its itself just me more most my myself no nor not now of off on once only or other "
 + "our ours ourselves out over own same she should so some such than that the their theirs them themselves then there "
 + "these they this those through to too under until up very was we were what when where which while who whom why will "
 + "with would you your yours yourself yourselves also get got let lets please tell know want like make use using one "
 + "im ive dont doesnt didnt cant wont isnt arent thats whats").split(" ").forEach(function(word) { STOPWORDS[word] = true; });

function _s(value) {
    return value === undefined || value === null ? "" : String(value);
}

// Lowercase words without punctuation or stopwords; a plural "s" is dropped
// so "projects" matches "project".
function tokenize(text) {
    var words = _s(text).toLowerCase().replace(/['’]/g, "")
        .split(/[\s.,;:!?()\[\]{}"`<>\/\\|@#$%^&*+=~_—–-]+/);
    var out = [];
    for (var i = 0; i < words.length; i++) {
        var word = words[i];
        if (word.length < 2 || STOPWORDS[word])
            continue;
        if (word.length > 3 && word.charAt(word.length - 1) === "s" && word.charAt(word.length - 2) !== "s")
            word = word.substring(0, word.length - 1);
        out.push(word);
    }
    return out;
}

// The memories a chat may use: enabled, and for every chat, the chat's
// project or the chat itself. chat: {id, projectId}.
function applicable(memories, chat) {
    var id = _s(chat && chat.id);
    var projectId = _s(chat && chat.projectId);
    return (memories || []).filter(function(m) {
        if (!m || m.enabled === false || !_s(m.text).trim())
            return false;
        if (m.scope === "all")
            return true;
        if (m.scope === "project")
            return projectId !== "" && _s(m.projectId) === projectId;
        if (m.scope === "chat")
            return id !== "" && _s(m.chatId) === id;
        return false;
    });
}

// What recall() matches against: the text of the last `count` messages
// (the newest is the one being answered).
function queryFor(messages, count) {
    var list = messages || [];
    var n = count === undefined ? QUERY_MESSAGES : count;
    var parts = [];
    for (var i = Math.max(0, list.length - n); i < list.length; i++) {
        var content = list[i] ? list[i].content : "";
        if (typeof content === "string" && content)
            parts.push(content.substring(0, QUERY_CHARS_PER_MESSAGE));
    }
    return parts.join("\n");
}

// BM25 score of each memory for `query`, idf taken over `memories`.
function scores(memories, query) {
    var terms = {};
    tokenize(query).forEach(function(t) { terms[t] = true; });
    var queryTerms = Object.keys(terms);
    var docs = memories.map(function(m) { return tokenize(m.text); });
    var n = docs.length;
    var total = 0;
    var df = {};
    docs.forEach(function(doc) {
        total += doc.length;
        var seen = {};
        doc.forEach(function(t) {
            if (!seen[t]) {
                seen[t] = true;
                df[t] = (df[t] || 0) + 1;
            }
        });
    });
    var avg = n > 0 ? total / n || 1 : 1;
    return docs.map(function(doc) {
        var tf = {};
        doc.forEach(function(t) { tf[t] = (tf[t] || 0) + 1; });
        var score = 0;
        queryTerms.forEach(function(t) {
            if (!tf[t])
                return;
            var idf = Math.log(1 + (n - df[t] + 0.5) / (df[t] + 0.5));
            score += idf * tf[t] * (K1 + 1) / (tf[t] + K1 * (1 - B + B * doc.length / avg));
        });
        return score;
    });
}

// One memory as a line of the block (later lines of its text indented).
function line(memory) {
    return "- " + _s(memory.text).trim().replace(/\n/g, "\n  ");
}

function _byCreated(a, b) {
    var d = (Number(a.created) || 0) - (Number(b.created) || 0);
    return d !== 0 ? d : (_s(a.id) < _s(b.id) ? -1 : (_s(a.id) > _s(b.id) ? 1 : 0));
}

// The memories to send: {memories, ids, block}. memories are the applicable
// ones (see applicable()); query is the text being answered (queryFor()).
// Pinned memories come first (oldest first), then matches by score; one that
// doesn't fit in what is left of the budget is skipped. block is "" when
// nothing is chosen.
function recall(memories, query, budget) {
    var limit = budget === undefined ? DEFAULT_BUDGET : Number(budget) || 0;
    var list = (memories || []).filter(function(m) { return m && _s(m.text).trim(); });
    var score = scores(list, query);
    var ranked = list.map(function(m, i) { return {"memory": m, "score": score[i]}; });
    var pinned = ranked.filter(function(r) { return r.memory.pinned === true; })
        .sort(function(a, b) { return _byCreated(a.memory, b.memory); });
    var matched = ranked.filter(function(r) { return r.memory.pinned !== true && r.score > 0; })
        .sort(function(a, b) { return b.score - a.score || _byCreated(a.memory, b.memory); });
    var chosen = [];
    var used = HEADING.length;
    pinned.concat(matched).forEach(function(r) {
        var size = line(r.memory).length + 1;
        if (used + size <= limit) {
            chosen.push(r.memory);
            used += size;
        }
    });
    return {
        "memories": chosen,
        "ids": chosen.map(function(m) { return _s(m.id); }),
        "block": block(chosen)
    };
}

function block(chosen) {
    if (!chosen || chosen.length === 0)
        return "";
    return HEADING + "\n" + chosen.map(line).join("\n");
}
