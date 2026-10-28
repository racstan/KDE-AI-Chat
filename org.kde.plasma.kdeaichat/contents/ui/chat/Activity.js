.pragma library

// One reply's activity (the model's thinking and the steps it takes) in the
// order it happened, for chat/ActivityBox.qml. Direct and Pi replies only.
//
//   message.activity = [
//     {kind: "thinking", text, ms}   a stretch of thinking and how long it took (ms 0 = unknown)
//     {kind: "tool", id}             a tool call; its state is message.tools[id]
//     {kind: "notice", text}         "ℹ text" / "⚠ text" (AgentEvents.js)
//     {kind: "file", text}           a changed file's path
//   ]
//
// A stretch of thinking is added when something else happens (a step, the end
// of the reply), so the live text stays in the chat's stream buffer and nothing
// here runs per streamed delta. Messages saved before this have no `activity`:
// items() then builds the list from their reasoning, tools, notices, files and
// contextItems. Plain functions on plain objects, so tests run them in node.

function thinkingChars(activity) {
    var n = 0;
    for (var i = 0; i < (activity || []).length; i++)
        if (activity[i].kind === "thinking")
            n += activity[i].text.length;
    return n;
}

// `activity` plus the thinking in `reasoning` (all of the reply's thinking so
// far) that isn't in it yet, as one stretch that took end - start ms.
function closeThinking(activity, reasoning, start, end) {
    activity = activity || [];
    var tail = String(reasoning || "").substring(thinkingChars(activity));
    if (tail === "")
        return activity;
    return activity.concat([{"kind": "thinking", "text": tail, "ms": start > 0 && end >= start ? end - start : 0}]);
}

// `activity` plus what a tool, file or notice event adds (nothing for updates and ends).
// `reply` is the message after the event was applied to it (AgentEvents.applyToReply).
function record(activity, event, reply) {
    activity = activity || [];
    var entry = null;
    if (event.type === "tool_start") {
        for (var i = 0; i < activity.length; i++)
            if (activity[i].kind === "tool" && activity[i].id === event.callId)
                return activity;
        entry = {"kind": "tool", "id": event.callId};
    } else if (event.type === "notice") {
        var notices = reply.notices || [];
        entry = {"kind": "notice", "text": notices.length > 0 ? notices[notices.length - 1] : String(event.message || "")};
    } else if (event.type === "file_changed") {
        for (var j = 0; j < activity.length; j++)
            if (activity[j].kind === "file" && activity[j].text === event.path)
                return activity;
        entry = {"kind": "file", "text": event.path};
    }
    return entry ? activity.concat([entry]) : activity;
}

// Whether the message has anything to show in the box.
function hasContent(message) {
    var m = message || {};
    return !!(m.reasoning || (m.activity && m.activity.length > 0) || (m.contextItems && m.contextItems.length > 0));
}

// The steps and thinking to list, oldest first:
//   {kind: "thinking", text, ms} | {kind: "tool", tool} | {kind: "notice", text} | {kind: "file", text} | {kind: "line", text}
// Thinking that is in message.reasoning but not in the activity (a reply
// that was cut off) comes last.
function items(message) {
    var m = message || {};
    var out = [];
    var tools = m.tools || {};
    if (Array.isArray(m.activity)) {
        for (var i = 0; i < m.activity.length; i++) {
            var a = m.activity[i];
            if (a.kind === "tool")
                out.push({"kind": "tool", "tool": tools[a.id] || {"name": "", "status": "running"}});
            else
                out.push({"kind": a.kind, "text": a.text, "ms": a.ms || 0});
        }
        var rest = String(m.reasoning || "").substring(thinkingChars(m.activity));
        if (rest !== "")
            out.push({"kind": "thinking", "text": rest, "ms": 0});
        return out;
    }
    // Saved before the activity list: thinking first, then the steps by kind.
    if (m.reasoning)
        out.push({"kind": "thinking", "text": String(m.reasoning), "ms": 0});
    var structured = Object.keys(tools).length > 0 || (m.notices || []).length > 0 || (m.filesChanged || []).length > 0;
    if (structured) {
        (m.notices || []).forEach(function(t) { out.push({"kind": "notice", "text": t, "ms": 0}); });
        Object.keys(tools).forEach(function(id) { out.push({"kind": "tool", "tool": tools[id]}); });
        (m.filesChanged || []).forEach(function(t) { out.push({"kind": "file", "text": t, "ms": 0}); });
    } else {
        (m.contextItems || []).forEach(function(t) { out.push({"kind": "line", "text": t, "ms": 0}); });
    }
    return out;
}

// Numbers for the one-line summary: {ms, steps, failed, running (name of a tool running now)}.
function summary(list) {
    var s = {"ms": 0, "steps": 0, "failed": 0, "running": ""};
    for (var i = 0; i < list.length; i++) {
        var it = list[i];
        if (it.kind === "thinking") {
            s.ms += it.ms || 0;
            continue;
        }
        s.steps++;
        if (it.kind === "tool" && it.tool.status === "error")
            s.failed++;
        if (it.kind === "tool" && it.tool.status === "running")
            s.running = it.tool.name || "";
    }
    return s;
}

// Whole seconds for "Thought for N s", at least 1.
function seconds(ms) {
    return Math.max(1, Math.round(ms / 1000));
}
