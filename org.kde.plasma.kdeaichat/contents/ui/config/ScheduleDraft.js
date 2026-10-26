.pragma library

// The schedule editor's draft: a schedules.v2.json definition (see
// kdeaichat/schedule_model.py) edited in place, one rule at a time. Every
// function returns new objects, so QML bindings see the change.
//
// Plain JavaScript on purpose (tested with node): no QML globals, no .import.
// Weekdays are 0=Sun..6=Sat (JavaScript getDay()); times are local "HH:MM".

var KINDS = ["weekly", "daily", "monthly", "once", "hourly", "minutes", "cron"];
var HOUR_STEPS = [1, 2, 3, 4, 6, 8, 12];
var MIN_EVERY_MINUTES = 15;
// Monday first, as the chips are shown.
var WEEK = [1, 2, 3, 4, 5, 6, 0];
var DEFAULT_TIME = "09:00";
var SCHEDULE_KEYS = ["id", "name", "enabled", "archived", "chatId", "message", "notify", "rules",
                     "startDate", "endDate", "limitCount", "catchUp", "createdAt", "editedAt"];

function _pad(n) {
    return (n < 10 ? "0" : "") + n;
}

function _copy(value) {
    return JSON.parse(JSON.stringify(value));
}

// "YYYY-MM-DD" of a Date, in local time.
function dateText(date) {
    return date.getFullYear() + "-" + _pad(date.getMonth() + 1) + "-" + _pad(date.getDate());
}

// "9", "9:5", "09:00", "0900", "9.30" -> "HH:MM", or "" when it isn't a time.
function normalizeTime(text) {
    var t = String(text === undefined || text === null ? "" : text).trim();
    var m = /^(\d{1,2})(?:[:.h]?(\d{2}))?$/.exec(t) || /^(\d{1,2})[:.](\d)$/.exec(t);
    if (!m)
        return "";
    var h = Number(m[1]);
    var min = m[2] === undefined ? 0 : Number(m[2]);
    if (h > 23 || min > 59)
        return "";
    return _pad(h) + ":" + _pad(min);
}

// "YYYY-MM-DD" when it is a real date, else "".
function normalizeDate(text) {
    var t = String(text || "").trim();
    var m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(t);
    if (!m)
        return "";
    var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    if (d.getFullYear() !== Number(m[1]) || d.getMonth() !== Number(m[2]) - 1 || d.getDate() !== Number(m[3]))
        return "";
    return dateText(d);
}

// Weekdays no weekly rule covers yet (Monday first), all of them if none is left.
function uncoveredDays(rules) {
    var covered = {};
    (rules || []).forEach(function(r) {
        if (r && r.kind === "weekly")
            (r.days || []).forEach(function(d) { covered[d] = true; });
    });
    var free = WEEK.filter(function(d) { return !covered[d]; });
    return free.length ? free : WEEK.slice(0, 5);
}

function _tomorrowAt(now, time) {
    var d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    return dateText(d) + "T" + time;
}

// A new rule of `kind`. A new weekly rule ticks the weekdays the other
// weekly rules leave free (the editor's answer to "except Monday").
function defaultRule(kind, rules, now) {
    now = now || new Date();
    switch (kind) {
    case "once": return {"kind": "once", "at": _tomorrowAt(now, DEFAULT_TIME)};
    case "daily": return {"kind": "daily", "times": [DEFAULT_TIME], "everyDays": 1};
    case "monthly": return {"kind": "monthly", "day": 1, "times": [DEFAULT_TIME], "everyMonths": 1};
    case "hourly": return {"kind": "hourly", "everyHours": 1, "minute": 0, "from": 0, "to": 23};
    case "minutes": return {"kind": "minutes", "everyMinutes": 30};
    case "cron": return {"kind": "cron", "expr": "0 9 * * 1-5"};
    }
    var days = uncoveredDays(rules).slice().sort(function(a, b) { return a - b; });
    return {"kind": "weekly", "days": days, "times": [DEFAULT_TIME], "everyWeeks": 1};
}

// `rule` as `kind`, keeping its times (and the first time for "once").
function changeKind(rule, kind, rules, now) {
    if (!rule || rule.kind === kind)
        return _copy(rule);
    var others = (rules || []).filter(function(r) { return r !== rule; });
    var next = defaultRule(kind, others, now);
    var times = rule.times && rule.times.length ? rule.times.slice() : null;
    if (!times && rule.kind === "once" && rule.at)
        times = [String(rule.at).substring(11, 16)];
    if (times && next.times)
        next.times = times;
    if (times && kind === "once")
        next.at = next.at.substring(0, 11) + times[0];
    if (kind === "once" && rule.kind === "once")
        next.at = rule.at;
    return next;
}

function toggleDay(rule, day) {
    var next = _copy(rule);
    var days = (next.days || []).slice();
    var at = days.indexOf(day);
    if (at >= 0)
        days.splice(at, 1);
    else
        days.push(day);
    next.days = days.sort(function(a, b) { return a - b; });
    return next;
}

// Sets day presets: "every" (all), "weekdays", "weekends".
function setDays(rule, preset) {
    var next = _copy(rule);
    next.days = preset === "weekdays" ? [1, 2, 3, 4, 5] : preset === "weekends" ? [0, 6] : [0, 1, 2, 3, 4, 5, 6];
    return next;
}

// Adds a time an hour after the last one (or 09:00).
function addTime(rule) {
    var next = _copy(rule);
    var times = (next.times || []).slice();
    var last = times.length ? times[times.length - 1] : "";
    var h = last ? (Number(last.substring(0, 2)) + 1) % 24 : 9;
    var candidate = _pad(h) + ":" + (last ? last.substring(3, 5) : "00");
    while (times.indexOf(candidate) >= 0 && times.length < 24) {
        h = (h + 1) % 24;
        candidate = _pad(h) + ":" + candidate.substring(3, 5);
    }
    times.push(candidate);
    next.times = times;
    return next;
}

function removeTime(rule, index) {
    var next = _copy(rule);
    next.times = (next.times || []).filter(function(t, i) { return i !== index; });
    return next;
}

// Sets one time; an invalid text is kept as typed (the field shows the error).
function setTime(rule, index, text) {
    var next = _copy(rule);
    var times = (next.times || []).slice();
    times[index] = normalizeTime(text) || String(text);
    next.times = times;
    return next;
}

function setField(rule, key, value) {
    var next = _copy(rule);
    next[key] = value;
    return next;
}

function replaceRule(rules, index, rule) {
    var next = (rules || []).slice();
    next[index] = rule;
    return next;
}

function removeRule(rules, index) {
    return (rules || []).filter(function(r, i) { return i !== index; });
}

// Problems the editor can see without the helper, one per rule ("" = fine).
function ruleProblem(rule) {
    if (!rule)
        return "missing";
    if (rule.times !== undefined) {
        if (!rule.times.length)
            return "no-times";
        for (var i = 0; i < rule.times.length; i++)
            if (normalizeTime(rule.times[i]) !== rule.times[i])
                return "bad-time";
    }
    if (rule.kind === "weekly" && !(rule.days || []).length)
        return "no-days";
    if (rule.kind === "once" && !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(String(rule.at || "")))
        return "bad-time";
    if (rule.kind === "minutes" && Number(rule.everyMinutes) < MIN_EVERY_MINUTES)
        return "too-often";
    if (rule.kind === "cron" && String(rule.expr || "").trim().split(/\s+/).length !== 5)
        return "bad-cron";
    return "";
}

// A blank schedule for `chatId` with one rule: weekdays at 09:00.
function newSchedule(chatId, now) {
    return {"id": "", "name": "", "enabled": true, "chatId": chatId || "", "message": "", "notify": true,
            "rules": [setDays(defaultRule("weekly", [], now), "weekdays")], "startDate": null, "endDate": null, "limitCount": null,
            "catchUp": {"enabled": false, "withinHours": 12}};
}

// An editable copy of a listed schedule (drops what the list added).
function fromListItem(item) {
    var draft = {};
    SCHEDULE_KEYS.forEach(function(k) {
        if (item && item[k] !== undefined)
            draft[k] = _copy(item[k]);
    });
    draft.rules = draft.rules || [];
    draft.catchUp = draft.catchUp || {"enabled": false, "withinHours": 12};
    if (draft.notify === undefined)
        draft.notify = true;
    if (item && item.needsReview) {
        // A migrated draft is off until the user finishes it; saving turns it on.
        draft.enabled = true;
        if (!draft.rules.length)
            draft.rules = [defaultRule("weekly", [])];
    }
    return draft;
}

// What schedule_save gets: only definition keys, empty id for a new one.
function forSave(draft) {
    var out = {};
    SCHEDULE_KEYS.forEach(function(k) {
        if (draft[k] !== undefined)
            out[k] = _copy(draft[k]);
    });
    if (!out.id)
        delete out.id;
    out.name = String(out.name || "").trim();
    out.startDate = normalizeDate(out.startDate) || null;
    out.endDate = normalizeDate(out.endDate) || null;
    var limit = Number(out.limitCount);
    out.limitCount = limit > 0 ? Math.floor(limit) : null;
    return out;
}

// What a migrated draft still lacks: a subset of ["chat", "time", "message"].
function missingParts(item) {
    var missing = [];
    if (!item || !item.chatId)
        missing.push("chat");
    if (!item || !(item.rules || []).length)
        missing.push("time");
    if (!item || !String(item.message || "").trim())
        missing.push("message");
    return missing;
}

// The chats a schedule can target: [{id, title}] from chat metadata
// (index.ini sessions: {value, text, archived}), archived chats left out
// unless one is the current target.
function chatChoices(sessions, keepId) {
    var out = [];
    (sessions || []).forEach(function(s) {
        if (s && s.value && (!s.archived || s.value === keepId))
            out.push({"id": String(s.value), "title": String(s.text || "").trim() || "New Chat"});
    });
    return out;
}

function chatTitle(sessions, chatId) {
    for (var i = 0; i < (sessions || []).length; i++)
        if (sessions[i] && sessions[i].value === chatId)
            return String(sessions[i].text || "").trim() || "New Chat";
    return "";
}

// The last result, from the run state: {state, text, at}. state is "none",
// "ok", "error", "missed", "skipped", "finished" or "pending" (due, not run).
function lastResult(runState) {
    var s = runState || {};
    var status = String(s.lastStatus || "");
    var at = s.lastRunAt || s.lastScheduledFor || "";
    if (s.finished && !status)
        return {"state": "finished", "text": "", "at": s.finishedAt || ""};
    if (!status)
        return {"state": "none", "text": "", "at": ""};
    if (status === "ok")
        return {"state": "ok", "text": "", "at": at};
    if (status === "missed")
        return {"state": "missed", "text": "", "at": s.lastScheduledFor || at};
    if (status === "due-not-run")
        return {"state": "pending", "text": "", "at": s.lastScheduledFor || at};
    if (/^error/.test(status))
        return {"state": "error", "text": status.replace(/^error:?\s*/, ""), "at": at};
    return {"state": "skipped", "text": status, "at": at};
}

// "2026-10-26T16:00:00" -> Date (local), or null.
function parseLocal(text) {
    var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(String(text || ""));
    return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5])) : null;
}

// 0 = today, 1 = tomorrow, -1 = yesterday, else null.
function dayOffset(date, now) {
    if (!date)
        return null;
    var a = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    var b = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var days = Math.round((a - b) / 86400000);
    return days >= -1 && days <= 1 ? days : null;
}
