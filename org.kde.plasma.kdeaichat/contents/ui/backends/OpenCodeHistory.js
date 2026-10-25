.pragma library

// Turns an OpenCode session's history (GET /session/:id/message, OpenCode
// 1.18: [{info: {id, role, time: {created}, providerID, modelID, error, ...},
// parts: [...]}]) into chat messages, as the "Sync session history" button
// shows them. OpenCode stores one assistant message per step of a reply;
// consecutive ones become one reply, with the same tool cards, changed files,
// reasoning and token counts a live reply gets.
//
// Plain JavaScript (tested with node): the event mapper and the reply updater
// are passed in (OpenCodeEvents.createEventMapper, AgentEvents.applyToReply).

// deps: {createEventMapper, applyToReply, formatTime(ms) -> "HH:MM",
//        sessionId (the OpenCode session), maxChars, now (ms)}
function toMessages(history, deps) {
    var out = [];
    var reply = null;
    var mapper = null;
    var maxChars = deps.maxChars || 2000000;
    var now = deps.now || 0;

    function stamp(info) {
        var created = info.time && Number(info.time.created);
        return created > 0 ? created : now;
    }
    function clip(text) {
        return text.length > maxChars ? text.substring(0, maxChars) + "\n[history message truncated]" : text;
    }
    function apply(event) {
        if (event.type === "text_delta") {
            reply.content += event.delta;
        } else if (event.type === "reasoning_delta") {
            reply.reasoning += event.delta;
        } else if (event.type === "usage") {
            reply.tokens = {"input": event.input || 0, "output": event.output || 0};
            reply.cost = (reply.cost || 0) + (event.cost || 0);
        } else if (event.type === "error") {
            deps.applyToReply(reply, {"type": "notice", "message": event.message});
        } else if (event.type === "tool_start" || event.type === "tool_update" || event.type === "tool_end" || event.type === "file_changed") {
            deps.applyToReply(reply, event);
        }
    }

    for (var i = 0; i < (history || []).length; i++) {
        var item = history[i] || {};
        var info = item.info || {};
        var parts = item.parts || [];
        var at = stamp(info);
        if (info.role === "user") {
            reply = null;
            var texts = [];
            for (var p = 0; p < parts.length; p++) {
                if (parts[p] && parts[p].type === "text" && parts[p].synthetic !== true && parts[p].text)
                    texts.push(String(parts[p].text));
            }
            out.push({"role": "user", "content": clip(texts.join("\n\n")) || "(empty)", "model": "You", "id": String(info.id || ("msg-" + i)),
                      "at": at, "time": deps.formatTime(at), "openCodeSessionId": deps.sessionId});
            continue;
        }
        if (info.role !== "assistant")
            continue;
        if (!reply) {
            reply = {"role": "assistant", "content": "", "reasoning": "", "id": String(info.id || ("msg-" + i)), "at": at, "time": deps.formatTime(at),
                     "model": info.providerID && info.modelID ? info.providerID + "/" + info.modelID : "OpenCode", "openCodeSessionId": deps.sessionId};
            out.push(reply);
            mapper = deps.createEventMapper(deps.sessionId, apply);
        }
        mapper.handle({"type": "message.updated", "properties": {"info": {"id": info.id, "role": "assistant", "error": info.error}}});
        for (var k = 0; k < parts.length; k++)
            mapper.handle({"type": "message.part.updated", "properties": {"part": Object.assign({}, parts[k], {"messageID": info.id})}});
    }
    for (var r = 0; r < out.length; r++) {
        var msg = out[r];
        if (msg.role !== "assistant") continue;
        msg.content = clip(msg.content);
        if (!msg.content && !msg.tools && !msg.notices)
            msg.content = "(empty response)";
    }
    return out;
}
