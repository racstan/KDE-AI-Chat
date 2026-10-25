.pragma library

// Records agent events (OpenCode and Pi) on chat messages, in the shape the
// chat view reads:
//   reply.tools          callId -> {name, detail, status: "running"|"done"|"error", input, output}
//   reply.filesChanged   [path]
//   reply.notices        ["⚠ text"]
//   reply.contextItems   one summary line per notice, tool and file
//   permission_request and question_request messages, with the agent
//   ("harness") that asked so answers go back to it.
// Plain functions on plain objects, so tests run them in node.

var MAX_TOOL_TEXT = 4000;

function harnessName(harness) {
    return harness === "pi" ? "Pi" : "OpenCode";
}

function _toolDetail(input) {
    input = input || {};
    return String(input.filePath || input.path || input.command || input.pattern || input.query || input.url || input.question || "").substring(0, 120);
}

function contextItems(reply) {
    var items = (reply.notices || []).slice();
    var tools = reply.tools || {};
    for (var id in tools) {
        var tool = tools[id];
        items.push((tool.status === "done" ? "✓ " : tool.status === "error" ? "✗ " : "… ") + tool.name + (tool.detail ? ": " + tool.detail : ""));
    }
    var files = reply.filesChanged || [];
    for (var i = 0; i < files.length; i++)
        items.push("📝 " + files[i]);
    return items;
}

function isReplyEvent(type) {
    return type === "tool_start" || type === "tool_update" || type === "tool_end" || type === "file_changed" || type === "notice";
}

// Applies a tool, file or notice event to the reply (changed in place).
function applyToReply(reply, event) {
    if (event.type === "notice") {
        reply.notices = (reply.notices || []).concat([(event.level === "info" ? "ℹ " : "⚠ ") + event.message]).slice(-20);
    } else if (event.type === "file_changed") {
        var files = (reply.filesChanged || []).slice();
        if (files.indexOf(event.path) < 0) files.push(event.path);
        reply.filesChanged = files;
    } else {
        var tools = Object.assign({}, reply.tools || {});
        var tool = Object.assign({"name": "", "detail": "", "status": "running", "input": "", "output": ""}, tools[event.callId] || {});
        if (event.type === "tool_start") {
            tool.name = event.name;
            tool.detail = _toolDetail(event.input);
            tool.input = JSON.stringify(event.input || {}).substring(0, MAX_TOOL_TEXT);
        } else if (event.type === "tool_update") {
            tool.detail = event.title || tool.detail;
        } else {
            tool.status = event.isError ? "error" : "done";
            tool.detail = event.title || tool.detail;
            tool.output = String(event.output || "").substring(0, MAX_TOOL_TEXT);
        }
        tools[event.callId] = tool;
        reply.tools = tools;
    }
    reply.contextItems = contextItems(reply);
    return reply;
}

// extra: {harness: "opencode"|"pi"|"direct", directory (OpenCode), chatId (Pi), name (who asks; default the agent)}.
function _request(role, idField, event, extra, now) {
    extra = extra || {};
    var harness = extra.harness || "opencode";
    var msg = {"role": role, "status": "pending", "at": now, "model": extra.name || harnessName(harness), "harness": harness,
               "openCodeDirectory": extra.directory || "", "harnessChatId": extra.chatId || ""};
    msg[idField] = event.id;
    return msg;
}

function permissionMessage(event, extra, now) {
    var msg = _request("permission_request", "permissionId", event, extra, now);
    var detail = (event.patterns || []).join("\n");
    msg.id = "perm-" + event.id;
    msg.tool = event.permission;
    msg.arguments = event.patterns;
    // Pi's dialogs are yes/no; OpenCode can also remember the answer.
    msg.canAlways = msg.harness !== "pi";
    msg.content = msg.model + " asks for permission: **" + event.permission + "**" + (detail ? "\n\n```\n" + detail + "\n```" : "");
    return msg;
}

function questionMessage(event, extra, now) {
    var msg = _request("question_request", "questionId", event, extra, now);
    var questions = [];
    var summary = [];
    var allowCustom = true;
    for (var q = 0; q < Math.min(20, (event.questions || []).length); q++) {
        var item = event.questions[q] || {};
        var custom = item.custom !== false;
        if (!custom) allowCustom = false;
        questions.push({"header": String(item.header || ""), "question": String(item.question || ""), "multiple": item.multiple === true, "custom": custom,
                        "options": (item.options || []).slice(0, 100).map(function(o) {
                            return {"label": String((o || {}).label || ""), "description": String((o || {}).description || "")};
                        })});
        summary.push((item.header ? "**" + item.header + "**: " : "") + String(item.question || ""));
    }
    msg.id = "question-" + event.id;
    msg.questions = questions;
    msg.allowCustom = allowCustom;
    msg.content = msg.model + " is asking:\n\n" + summary.join("\n\n");
    return msg;
}
