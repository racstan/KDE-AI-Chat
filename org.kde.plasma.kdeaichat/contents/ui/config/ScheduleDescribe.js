.pragma library

// "Describe when": turns a sentence ("weekdays at 9 and Sunday at noon") into
// schedule rules (schedules.v2.json format) with one model request. The model
// answers with JSON: {"rules": [...]}, or {"question": "...", "options": [...]}
// when the sentence can be read more than one way; the answer is sent back in
// the same conversation until rules come. Nothing is saved from here: the
// editor shows the rules for review.
//
// Plain JavaScript on purpose (tested with node): no QML globals, no .import.

// Questions the model may ask before the editor gives up.
var MAX_QUESTIONS = 4;
var MAX_OPTIONS = 6;
var DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function _pad(n) {
    return (n < 10 ? "0" : "") + n;
}

// The system prompt; `now` (a Date) lets "tomorrow" and dates be resolved.
function systemPrompt(now) {
    var today = now.getFullYear() + "-" + _pad(now.getMonth() + 1) + "-" + _pad(now.getDate());
    return [
        "You convert a description of WHEN something should repeat into schedule rules for a desktop scheduler.",
        "Reply with ONE JSON object and nothing else: no prose, no Markdown, no code fences.",
        "",
        "Either {\"rules\": [ ... ]} when the meaning is clear,",
        "or {\"question\": \"...\", \"options\": [\"...\", \"...\"]} when the description can reasonably be read in more than one way.",
        "Ask instead of guessing. Example: \"every other day\" can mean \"the remaining weekdays\" (after another rule took some days)",
        "or \"alternate days\" (every 2 days): ask which one, with 2-4 short options that each describe one concrete reading.",
        "Do not ask about things that are clear. Never ask about the message, only about the timing.",
        "",
        "Rule formats (weekdays are numbers: 0=Sunday, 1=Monday, ..., 6=Saturday; times are 24-hour \"HH:MM\" local time):",
        "- {\"kind\":\"weekly\",\"days\":[1,2,3,4,5],\"times\":[\"09:00\"]}  (on these weekdays; add \"everyWeeks\":2 for every other week)",
        "- {\"kind\":\"daily\",\"times\":[\"15:00\"],\"everyDays\":2}  (every N days; everyDays 1 = every day)",
        "- {\"kind\":\"monthly\",\"day\":15,\"times\":[\"09:00\"]}  (day 1-31 or \"last\"; add \"everyMonths\":3 for every 3 months)",
        "- {\"kind\":\"once\",\"at\":\"2026-11-03T14:30\"}  (one time only)",
        "- {\"kind\":\"hourly\",\"everyHours\":2,\"minute\":30,\"from\":8,\"to\":18}  (everyHours is 1, 2, 3, 4, 6, 8 or 12; from/to are hours 0-23)",
        "- {\"kind\":\"minutes\",\"everyMinutes\":30}  (at least 15)",
        "Prefer weekly and daily rules. Use several rules when different days have different times,",
        "e.g. \"Mondays at 4 pm and the other days at 3 pm\" is",
        "{\"rules\":[{\"kind\":\"weekly\",\"days\":[1],\"times\":[\"16:00\"]},{\"kind\":\"weekly\",\"days\":[0,2,3,4,5,6],\"times\":[\"15:00\"]}]}.",
        "Noon is 12:00, midnight is 00:00, \"morning\" without a time is a reason to ask.",
        "",
        "Today is " + DAY_NAMES[now.getDay()] + " " + today + ", the time is " + _pad(now.getHours()) + ":" + _pad(now.getMinutes()) + "."
    ].join("\n");
}

// The messages of the conversation so far: `turns` is
// [{role: "user"|"assistant", content}] starting with the description.
function buildMessages(turns, now) {
    var out = [{"role": "system", "content": systemPrompt(now)}];
    (turns || []).forEach(function(t) {
        if (t && (t.role === "user" || t.role === "assistant"))
            out.push({"role": t.role, "content": String(t.content || "")});
    });
    return out;
}

// The first complete {...} object in `text` (braces inside strings ignored), or "".
function _firstObject(text) {
    var start = text.indexOf("{");
    while (start >= 0) {
        var depth = 0;
        var inString = false;
        for (var i = start; i < text.length; i++) {
            var c = text.charAt(i);
            if (inString) {
                if (c === "\\") i++;
                else if (c === "\"") inString = false;
            } else if (c === "\"") {
                inString = true;
            } else if (c === "{") {
                depth++;
            } else if (c === "}") {
                depth--;
                if (depth === 0) {
                    var candidate = text.substring(start, i + 1);
                    try {
                        JSON.parse(candidate);
                        return candidate;
                    } catch (e) {
                        break;
                    }
                }
            }
        }
        start = text.indexOf("{", start + 1);
    }
    return "";
}

// The model's text with reasoning blocks and code fences removed.
function _clean(text) {
    var t = String(text || "");
    t = t.replace(/<(think|thinking|reasoning)>[\s\S]*?<\/\1>/gi, "");
    t = t.replace(/^[\s\S]*<\/(think|thinking|reasoning)>/i, "");
    return t.replace(/```(?:json)?/gi, "").trim();
}

var KINDS = ["once", "daily", "weekly", "monthly", "hourly", "minutes", "cron"];

// A rule with only the fields of its kind; null when it is unusable. Final
// validation is the helper's (schedule_preview); this only keeps the JSON tidy.
function _rule(raw) {
    if (!raw || typeof raw !== "object" || KINDS.indexOf(raw.kind) < 0)
        return null;
    var keys = {"once": ["at"], "daily": ["times", "everyDays"], "weekly": ["days", "times", "everyWeeks"],
                "monthly": ["day", "times", "everyMonths"], "hourly": ["everyHours", "minute", "from", "to"],
                "minutes": ["everyMinutes"], "cron": ["expr"]}[raw.kind];
    var out = {"kind": raw.kind};
    keys.forEach(function(k) {
        if (raw[k] !== undefined && raw[k] !== null)
            out[k] = raw[k];
    });
    if (out.times !== undefined && !Array.isArray(out.times))
        out.times = [out.times];
    if (out.times)
        out.times = out.times.map(function(t) {
            var m = /^(\d{1,2}):(\d{2})/.exec(String(t));
            return m ? _pad(Number(m[1])) + ":" + m[2] : String(t);
        });
    if (out.days !== undefined && !Array.isArray(out.days))
        out.days = [out.days];
    if (out.days)
        out.days = out.days.map(function(d) { return Number(d) === 7 ? 0 : Number(d); });
    if (raw.kind === "once" && typeof out.at === "string")
        out.at = out.at.substring(0, 16);
    return out;
}

// What the model answered: {rules: [...]} | {question, options: [...]} |
// {error: "no-json" | "no-rules" | "empty"}.
function parseReply(text) {
    var cleaned = _clean(text);
    if (!cleaned)
        return {"error": "empty"};
    var json = _firstObject(cleaned);
    if (!json)
        return {"error": "no-json"};
    var data = JSON.parse(json);
    if (typeof data.question === "string" && data.question.trim() && !(Array.isArray(data.rules) && data.rules.length)) {
        var options = Array.isArray(data.options) ? data.options : [];
        options = options.map(function(o) { return typeof o === "string" ? o.trim() : (o && o.label ? String(o.label).trim() : ""); })
            .filter(function(o) { return o; }).slice(0, MAX_OPTIONS);
        return {"question": data.question.trim(), "options": options};
    }
    var raw = Array.isArray(data.rules) ? data.rules : (data.kind ? [data] : []);
    var rules = raw.map(_rule).filter(function(r) { return r; });
    if (!rules.length)
        return {"error": "no-rules"};
    return {"rules": rules};
}
