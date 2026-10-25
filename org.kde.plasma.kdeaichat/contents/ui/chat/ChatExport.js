.pragma library

// Builds a saved copy of a chat as Markdown, plain text or JSON.
//
// Plain JavaScript on purpose (tested with node): no QML globals, no .import.
//
// chat = {
//   title,                 chat title
//   createdAt, exportedAt  ms since the epoch (0 / missing when unknown)
//   mode                   "provider" | "opencode" | "pi"
//   provider, model        what the chat uses now (display strings)
//   messages               the chat's message list (see below)
// }
// A message is {role: user|queued|assistant|error, content, time, at, model,
// reasoning, attachments: [{name, type, mimeType, size}], quotes: [{id, role,
// text}] (the messages it quoted), tools: {id: {name,
// detail, status, input, output}}, filesChanged, tokens, cost}. Other roles
// (permission and question cards) and any UI state are left out.
//
// opts = {includeReasoning: false}. Reasoning is left out unless asked for;
// then it goes in a clearly marked section.
//
// JSON layout (version 1):
//   {format: "kdeaichat-chat", version: 1, title, exportedAt, createdAt, mode,
//    provider, model,
//    messages: [{role: "user"|"assistant"|"error", time, model, text,
//                quotes?: [{role: "user"|"assistant", text}],
//                reasoning?, attachments: [{name, type, mimeType, size}],
//                toolCalls: [{name, status, input, output}], filesChanged,
//                tokens?, cost?}]}
// Times are ISO 8601 strings (UTC) or null.

var FORMATS = [
    {"id": "markdown", "label": "Markdown files (*.md)", "ext": "md"},
    {"id": "text", "label": "Plain text files (*.txt)", "ext": "txt"},
    {"id": "json", "label": "JSON files (*.json)", "ext": "json"}
];

var MODE_NAMES = {"provider": "Direct", "opencode": "OpenCode", "pi": "Pi"};
var MAX_INPUT = 200;
var MAX_SUMMARY = 160;

function filterLabels() {
    return FORMATS.map(function(f) { return f.label; });
}

// The format and final path for a save: the chosen filter decides the format
// and the extension (swapping a known export extension, or adding one).
function resolveTarget(path, filterIndex) {
    var fmt = FORMATS[filterIndex] || FORMATS[0];
    var p = String(path || "");
    var slash = p.lastIndexOf("/");
    var dir = p.substring(0, slash + 1);
    var name = p.substring(slash + 1);
    name = name.replace(/\.(md|markdown|txt|json)$/i, "");
    if (name === "")
        name = "chat";
    return {"format": fmt.id, "ext": fmt.ext, "path": dir + name + "." + fmt.ext};
}

function _pad(n) {
    return n < 10 ? "0" + n : String(n);
}

function _local(ms) {
    var d = new Date(ms);
    return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate()) + " " + _pad(d.getHours()) + ":" + _pad(d.getMinutes());
}

function _iso(ms) {
    return ms > 0 ? new Date(ms).toISOString() : null;
}

// Strips what must not reach a file: control and zero-width characters,
// carriage returns and <think> blocks (reasoning, which is left out here).
function clean(text) {
    return String(text === undefined || text === null ? "" : text)
        .replace(/\r\n?/g, "\n")
        .replace(/<think>[\s\S]*?(<\/think>|$)/gi, "").replace(/<\/think>/gi, "")
        .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f​-‍⁠﻿]/g, "")
        .replace(/\s+$/, "");
}

function _oneLine(text, max) {
    var s = clean(text).replace(/\s+/g, " ").trim();
    return s.length > max ? s.substring(0, max - 1) + "…" : s;
}

function _esc(text) {
    return String(text).replace(/([*_`\\])/g, "\\$1");
}

function _speaker(m) {
    if (m.role === "assistant")
        return m.model ? "Assistant (" + _oneLine(m.model, 80) + ")" : "Assistant";
    return m.role === "error" ? "Error" : "You";
}

function _role(m) {
    return m.role === "queued" ? "user" : m.role;
}

function _when(m) {
    return m.at > 0 ? _local(m.at) : String(m.time || "");
}

function _fmtSize(bytes) {
    bytes = Number(bytes) || 0;
    if (bytes <= 0)
        return "";
    if (bytes < 1024)
        return bytes + " B";
    return bytes < 1048576 ? Math.round(bytes / 1024) + " KB" : (bytes / 1048576).toFixed(1) + " MB";
}

function _attachments(m) {
    var out = [];
    var list = m.attachments || [];
    for (var i = 0; i < list.length; i++) {
        var a = list[i] || {};
        var name = _oneLine(a.name || a.path || "", 200);
        if (name)
            out.push({"name": name, "type": String(a.type || ""), "mimeType": String(a.mimeType || ""), "size": Number(a.size) || 0});
    }
    return out;
}

// What the message quoted: [{role, speaker, text}], in the order it was sent.
function _quotes(m) {
    var out = [];
    var list = m.quotes || [];
    for (var i = 0; i < list.length; i++) {
        var q = list[i] || {};
        var text = clean(q.text);
        if (text)
            out.push({"role": q.role === "assistant" ? "assistant" : "user",
                      "speaker": q.role === "assistant" ? "Assistant" : "You", "text": text});
    }
    return out;
}

// "> **You:** first line" and the rest of the lines as a Markdown block quote.
function _quoteMarkdown(q) {
    var lines = q.text.split("\n").map(function(l) { return l === "" ? ">" : "> " + l; });
    lines[0] = lines[0].replace(/^>( |$)/, "> **" + q.speaker + ":** ");
    return lines.join("\n");
}

function _tools(m) {
    var out = [];
    var tools = m.tools || {};
    for (var id in tools) {
        var t = tools[id] || {};
        var input = t.input;
        if (input && typeof input === "object")
            input = JSON.stringify(input);
        out.push({"name": _oneLine(t.name || "tool", 80), "status": String(t.status || ""),
                  "detail": _oneLine(t.detail, MAX_INPUT), "input": clean(input), "output": clean(t.output)});
    }
    return out;
}

// What a message says: error, user and assistant only, nothing empty.
function _entries(chat, opts) {
    var out = [];
    var list = chat.messages || [];
    for (var i = 0; i < list.length; i++) {
        var m = list[i];
        if (!m || typeof m !== "object")
            continue;
        var role = _role(m);
        if (role !== "user" && role !== "assistant" && role !== "error")
            continue;
        var e = {"role": role, "speaker": _speaker(m), "when": _when(m), "at": m.at > 0 ? m.at : 0,
                 "model": role === "assistant" ? String(m.model || "") : "",
                 "text": clean(m.content), "reasoning": opts.includeReasoning ? clean(m.reasoning) : "",
                 "attachments": _attachments(m), "quotes": role === "user" ? _quotes(m) : [], "tools": _tools(m),
                 "filesChanged": (m.filesChanged || []).map(function(f) { return _oneLine(f, 300); }),
                 "tokens": m.tokens || null, "cost": m.cost > 0 ? Number(m.cost) : 0};
        if (!e.text && !e.reasoning && e.attachments.length === 0 && e.tools.length === 0 && e.filesChanged.length === 0)
            continue;
        out.push(e);
    }
    return out;
}

function _details(chat, count) {
    var rows = [["Exported", _local(chat.exportedAt > 0 ? chat.exportedAt : Date.now())]];
    if (chat.createdAt > 0)
        rows.push(["Created", _local(chat.createdAt)]);
    rows.push(["Mode", MODE_NAMES[chat.mode] || "Direct"]);
    if (chat.provider)
        rows.push(["Provider", _oneLine(chat.provider, 100)]);
    if (chat.model)
        rows.push(["Model", _oneLine(chat.model, 100)]);
    rows.push(["Messages", String(count)]);
    return rows;
}

function _title(chat) {
    return _oneLine(chat.title, 200) || "Untitled chat";
}

// Closes a code fence the message left open (a cut-off reply), so the rest of
// the file is not swallowed by it.
function _closeFences(text) {
    var count = (text.match(/^[ \t]*```/gm) || []).length;
    return count % 2 === 1 ? text + "\n```" : text;
}

function _summary(output) {
    if (!output)
        return "";
    var lines = output.split("\n").filter(function(l) { return l.trim() !== ""; });
    if (lines.length === 0)
        return "";
    var s = _oneLine(lines[0], MAX_SUMMARY);
    return lines.length > 1 ? s + " (" + lines.length + " lines)" : s;
}

function _toolLines(t) {
    var line = t.name + (t.detail ? ": " + t.detail : t.input ? ": " + _oneLine(t.input, MAX_INPUT) : "");
    var status = t.status === "error" ? "failed" : t.status;
    return {"line": line + (status ? " [" + status + "]" : ""), "result": _summary(t.output)};
}

function toMarkdown(chat, opts) {
    opts = opts || {};
    var entries = _entries(chat, opts);
    var out = ["# " + _title(chat), ""];
    var d = _details(chat, entries.length);
    for (var i = 0; i < d.length; i++)
        out.push("- **" + d[i][0] + ":** " + _esc(d[i][1]));
    out.push("", "---", "");
    if (entries.length === 0)
        out.push("*This chat has no messages.*", "");
    for (var n = 0; n < entries.length; n++) {
        var e = entries[n];
        out.push("## " + _esc(e.speaker) + (e.when ? " · " + e.when : ""), "");
        for (var qi = 0; qi < e.quotes.length; qi++)
            out.push(_quoteMarkdown(e.quotes[qi]), "");
        if (e.role === "error")
            out.push(_closeFences(e.text).replace(/^/gm, "> "), "");
        else if (e.text)
            out.push(_closeFences(e.text), "");
        if (e.reasoning)
            out.push("**Reasoning**", "", _closeFences(e.reasoning).replace(/^/gm, "> "), "");
        if (e.attachments.length > 0) {
            out.push("**Attachments**", "");
            for (var a = 0; a < e.attachments.length; a++) {
                var sz = _fmtSize(e.attachments[a].size);
                out.push("- " + _esc(e.attachments[a].name) + (sz ? " (" + sz + ")" : ""));
            }
            out.push("");
        }
        if (e.tools.length > 0) {
            out.push("**Tool calls**", "");
            for (var t = 0; t < e.tools.length; t++) {
                var tl = _toolLines(e.tools[t]);
                out.push("- `" + tl.line.replace(/`/g, "'") + "`" + (tl.result ? "\n  Result: " + _esc(tl.result) : ""));
            }
            out.push("");
        }
        if (e.filesChanged.length > 0)
            out.push("**Files changed**", "", e.filesChanged.map(function(f) { return "- `" + f.replace(/`/g, "'") + "`"; }).join("\n"), "");
    }
    return out.join("\n").replace(/\n{3,}/g, "\n\n").replace(/\s+$/, "") + "\n";
}

function toText(chat, opts) {
    opts = opts || {};
    var entries = _entries(chat, opts);
    var rule = new Array(61).join("=");
    var thin = new Array(61).join("-");
    var out = [rule, _title(chat), rule];
    var d = _details(chat, entries.length);
    for (var i = 0; i < d.length; i++)
        out.push(d[i][0] + ": " + d[i][1]);
    out.push("", "");
    if (entries.length === 0)
        out.push("(This chat has no messages.)", "");
    for (var n = 0; n < entries.length; n++) {
        var e = entries[n];
        out.push(e.speaker + (e.when ? "  [" + e.when + "]" : ""), thin);
        for (var qi = 0; qi < e.quotes.length; qi++)
            out.push(e.quotes[qi].text.replace(/^/gm, "> ").replace(/^> /, "> " + e.quotes[qi].speaker + ": "), "");
        if (e.text)
            out.push((e.role === "error" ? "Error: " : "") + _closeFences(e.text));
        if (e.reasoning)
            out.push("", "[Reasoning]", _closeFences(e.reasoning).replace(/^/gm, "  "));
        if (e.attachments.length > 0)
            out.push("", "Attachments: " + e.attachments.map(function(a) { return a.name; }).join(", "));
        for (var t = 0; t < e.tools.length; t++) {
            var tl = _toolLines(e.tools[t]);
            out.push("", "Tool: " + tl.line + (tl.result ? "\n  Result: " + tl.result : ""));
        }
        if (e.filesChanged.length > 0)
            out.push("", "Files changed: " + e.filesChanged.join(", "));
        out.push("", "");
    }
    return out.join("\n").replace(/\n{3,}/g, "\n\n").replace(/\s+$/, "") + "\n";
}

function toJson(chat, opts) {
    opts = opts || {};
    var messages = _entries(chat, opts).map(function(e) {
        var m = {"role": e.role, "time": _iso(e.at), "model": e.model || null, "text": e.text};
        if (e.reasoning)
            m.reasoning = e.reasoning;
        if (e.quotes.length > 0)
            m.quotes = e.quotes.map(function(q) { return {"role": q.role, "text": q.text}; });
        m.attachments = e.attachments;
        m.toolCalls = e.tools.map(function(t) {
            return {"name": t.name, "status": t.status || null, "input": t.input, "output": t.output};
        });
        m.filesChanged = e.filesChanged;
        if (e.tokens)
            m.tokens = e.tokens;
        if (e.cost)
            m.cost = e.cost;
        return m;
    });
    return JSON.stringify({
        "format": "kdeaichat-chat", "version": 1, "title": _title(chat),
        "exportedAt": _iso(chat.exportedAt > 0 ? chat.exportedAt : Date.now()),
        "createdAt": _iso(chat.createdAt), "mode": chat.mode || "provider",
        "provider": chat.provider || null, "model": chat.model || null, "messages": messages
    }, null, 2) + "\n";
}

// formatId: "markdown" | "text" | "json".
function build(formatId, chat, opts) {
    chat = chat || {};
    if (formatId === "json")
        return toJson(chat, opts);
    return formatId === "text" ? toText(chat, opts) : toMarkdown(chat, opts);
}
