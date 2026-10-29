.pragma library
// The starting points of an empty chat (EmptyState.qml): up to six chips.
// The user's prompt templates come first (at most three, rotating when there
// are more), then an optional "continue" chip for the latest other chat, then
// built-in suggestions from a pool that fits the chat's mode, picked by a
// seed (the chat id) so a chat keeps its chips while it is open and the next
// new chat gets different ones. The wording of the built-ins is in
// StarterTexts.qml (i18n); this module returns only their ids.

var MAX_CHIPS = 6;
var MAX_TEMPLATES = 3;

// Everyday tasks for a direct chat.
var PROVIDER_IDS = ["explain", "write", "summarise", "translate", "plan", "brainstorm", "email", "recipe",
                    "compare", "learn", "proofread", "decide", "study", "rewrite", "travel", "gift",
                    "shorter", "regex"];
// File, code and project tasks for OpenCode and Pi.
var AGENT_IDS = ["project", "bugfix", "tests", "changes", "review", "todo", "refactor", "docs", "deps", "run"];
// Offered first when the time of day fits (hour 0-23); not in the pools.
var MORNING = {provider: "planday", agent: "standup"};
var EVENING = {provider: "reflect", agent: "wrapup"};

function hash(text) {
    var h = 2166136261;
    var s = String(text === undefined || text === null ? "" : text);
    for (var i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = Math.imul(h, 16777619) >>> 0;
    }
    return h >>> 0;
}

// A small seeded random generator (mulberry32).
function rng(seed) {
    var a = hash(seed);
    return function() {
        a = (a + 0x6D2B79F5) >>> 0;
        var t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function shuffled(list, seed) {
    var out = list.slice();
    var next = rng(seed);
    for (var i = out.length - 1; i > 0; i--) {
        var j = Math.floor(next() * (i + 1));
        var t = out[i];
        out[i] = out[j];
        out[j] = t;
    }
    return out;
}

// "morning", "evening" or "" for an hour of the day.
function dayPart(hour) {
    if (hour >= 5 && hour < 11)
        return "morning";
    if (hour >= 18 && hour < 23)
        return "evening";
    return "";
}

function isAgent(mode) {
    return mode === "opencode" || mode === "pi";
}

// The pool for a mode ("provider", "opencode", "pi"): its ids, and the id
// that fits the time of day first, if any.
function poolFor(mode, hour) {
    var key = isAgent(mode) ? "agent" : "provider";
    var part = dayPart(hour);
    var timed = part === "morning" ? MORNING[key] : part === "evening" ? EVENING[key] : "";
    return {ids: (isAgent(mode) ? AGENT_IDS : PROVIDER_IDS).slice(), timed: timed};
}

// All ids a mode can show, for the wording table and tests.
function allIds(mode) {
    var key = isAgent(mode) ? "agent" : "provider";
    return (isAgent(mode) ? AGENT_IDS : PROVIDER_IDS).concat([MORNING[key], EVENING[key]]);
}

// The templates to show: all when there are up to three, else a window of
// three that moves with the seed.
function pickTemplates(templates, seed) {
    var list = (templates || []).filter(function(t) { return t && t.name; });
    if (list.length <= MAX_TEMPLATES)
        return list;
    var start = hash(seed) % list.length;
    var out = [];
    for (var i = 0; i < MAX_TEMPLATES; i++)
        out.push(list[(start + i) % list.length]);
    return out;
}

// The most recent other chat that is not archived and has a title.
function latestOther(sessions, currentId) {
    var best = null;
    var list = sessions || [];
    for (var i = 0; i < list.length; i++) {
        var s = list[i];
        if (!s || s.value === currentId || s.archived || !s.text)
            continue;
        if (s.messagesUnloaded ? s.messageCount === 0 : (Array.isArray(s.messages) && s.messages.length === 0))
            continue;
        var when = s.updatedAt || s.createdAt || 0;
        if (best === null || when > best.when)
            best = {session: s, when: when};
    }
    return best ? best.session : null;
}

// options: {mode, templates, seed, hour, sessions, currentId}
// Returns [{kind: "template", name, prompt} | {kind: "continue", id, title} | {kind: "builtin", id}].
function pick(options) {
    var o = options || {};
    var chips = pickTemplates(o.templates, o.seed).map(function(t) {
        return {kind: "template", name: t.name, prompt: t.prompt || ""};
    });
    var other = latestOther(o.sessions, o.currentId);
    if (other)
        chips.push({kind: "continue", id: other.value, title: other.text});
    var pool = poolFor(o.mode, o.hour);
    var ids = shuffled(pool.ids, String(o.seed) + "|" + o.mode);
    if (pool.timed)
        ids.unshift(pool.timed);
    for (var i = 0; chips.length < MAX_CHIPS && i < ids.length; i++)
        chips.push({kind: "builtin", id: ids[i]});
    return chips;
}
