.pragma library

// OpenCode's /event stream -> backend events (the shared contract in
// DirectBackend.js, plus the OpenCode ones listed in OpenCodeBackend.js), for
// one server session. Used for live replies (OpenCodeBackend.send) and for
// synced history (OpenCodeHistory.js). Checked against OpenCode 1.18.
//
// Plain JavaScript (no QML globals, no .import), so tests run it in node.

function _errorText(error, fallback) {
    if (!error) return fallback;
    if (typeof error === "string") return error;
    var data = error.data || {};
    return String(data.message || error.message || error.name || fallback);
}

// Turns OpenCode events for one server session into backend events.
// emit(event) receives them; handle(eventObj) takes one parsed event (either
// {type, properties} from /event or {directory, payload} from /global/event).
// The /event stream carries every session of the folder: only this session's
// reply is shown, plus the permission and question requests of the subagent
// sessions it starts (their own session ids, parentID = this session), which
// wait for an answer just like this session's own.
function createEventMapper(sessionId, emit) {
    var roles = {};          // messageID -> "user" | "assistant"
    var parts = {};          // partID -> {kind: "text"|"reasoning"|..., emitted}
    var waiting = {};        // messageID -> [events] seen before its role was known
    var tools = {};          // callID -> last status
    var counted = {};        // step-finish partIDs whose usage was reported
    var children = {};       // sessionID -> true: subagent sessions started by this one
    var busy = false;
    var errored = false;
    var finished = false;

    function related(id) { return id === sessionId || children[id] === true; }

    function toolRunning() {
        for (var id in tools) {
            if (tools[id] === "pending" || tools[id] === "running") return true;
        }
        return false;
    }

    function partFromAssistant(part) {
        var role = roles[part.messageID];
        if (role === undefined) {
            (waiting[part.messageID] = waiting[part.messageID] || []).push(part);
            return false;
        }
        return role === "assistant";
    }

    function emitText(partId, kind, text) {
        var state = parts[partId] || (parts[partId] = {"kind": kind, "emitted": 0});
        state.kind = kind;
        if (text.length > state.emitted) {
            emit({"type": kind === "reasoning" ? "reasoning_delta" : "text_delta", "delta": text.substring(state.emitted)});
            state.emitted = text.length;
        }
    }

    function handlePart(part) {
        if (!partFromAssistant(part))
            return;
        if (part.type === "text" || part.type === "reasoning") {
            emitText(part.id, part.type, String(part.text || ""));
        } else if (part.type === "tool") {
            var state = part.state || {};
            var callId = part.callID || part.id;
            if (tools[callId] === undefined)
                emit({"type": "tool_start", "callId": callId, "name": String(part.tool || "tool"), "input": state.input || {}});
            if (state.status === "running" && state.title && tools[callId] !== "running")
                emit({"type": "tool_update", "callId": callId, "title": String(state.title)});
            if ((state.status === "completed" || state.status === "error") && tools[callId] !== "completed" && tools[callId] !== "error") {
                emit({"type": "tool_end", "callId": callId, "title": String(state.title || ""),
                      "output": String(state.status === "error" ? (state.error || "") : (state.output || "")).substring(0, 20000),
                      "isError": state.status === "error"});
            }
            if (tools[callId] !== "completed" && tools[callId] !== "error")
                tools[callId] = state.status || "pending";
        } else if (part.type === "step-finish" && part.tokens && !counted[part.id]) {
            counted[part.id] = true;
            emit({"type": "usage", "input": part.tokens.input || 0, "output": part.tokens.output || 0,
                  "reasoning": part.tokens.reasoning || 0, "cost": part.cost || 0});
        } else if (part.type === "patch") {
            for (var i = 0; i < (part.files || []).length; i++)
                emit({"type": "file_changed", "path": String(part.files[i])});
        }
    }

    function finish() {
        if (finished) return;
        finished = true;
        emit({"type": "done", "reason": errored ? "error" : "complete"});
    }

    // Permission and question requests (and their answers), from this session
    // or one of its subagents. Returns false for other event types.
    function handleRequest(type, props) {
        if (type === "permission.asked" || type === "permission.v2.asked") {
            emit({"type": "permission_request", "id": String(props.id || ""), "permission": String(props.permission || props.action || ""),
                  "patterns": props.patterns || props.resources || [], "metadata": props.metadata || {}});
        } else if (type === "permission.replied" || type === "permission.v2.replied") {
            emit({"type": "permission_resolved", "id": String(props.requestID || ""), "reply": String(props.reply || "")});
        } else if (type === "question.asked" || type === "question.v2.asked") {
            emit({"type": "question_request", "id": String(props.id || ""), "questions": props.questions || []});
        } else if (type === "question.replied" || type === "question.v2.replied") {
            emit({"type": "question_resolved", "id": String(props.requestID || ""), "status": "answered"});
        } else if (type === "question.rejected" || type === "question.v2.rejected") {
            emit({"type": "question_resolved", "id": String(props.requestID || ""), "status": "dismissed"});
        } else {
            return false;
        }
        return true;
    }

    function handle(eventObj) {
        if (finished || !eventObj) return;
        if (eventObj.payload && !eventObj.properties)
            eventObj = eventObj.payload;
        var type = eventObj.type || "";
        var props = eventObj.properties || {};
        if (type === "session.created" || type === "session.updated") {
            var session = props.info || {};
            if (session.id && session.parentID && related(session.parentID))
                children[session.id] = true;
            return;
        }
        if (props.sessionID !== undefined && !related(props.sessionID))
            return;
        if (handleRequest(type, props) || (props.sessionID !== undefined && props.sessionID !== sessionId))
            return;
        if (type === "message.updated") {
            var info = props.info || {};
            if (!info.id) return;
            var known = roles[info.id] !== undefined;
            roles[info.id] = info.role;
            if (!known && waiting[info.id]) {
                var queued = waiting[info.id];
                delete waiting[info.id];
                for (var q = 0; q < queued.length; q++) handlePart(queued[q]);
            }
            if (info.role === "assistant" && info.error && !errored) {
                errored = true;
                emit({"type": "error", "message": "OpenCode: " + _errorText(info.error, "the request failed."), "status": 0});
            }
        } else if (type === "message.part.updated") {
            if (props.part) handlePart(props.part);
        } else if (type === "message.part.delta") {
            var state = parts[props.partID];
            if (props.field === "text" && state && roles[props.messageID] === "assistant") {
                emit({"type": state.kind === "reasoning" ? "reasoning_delta" : "text_delta", "delta": String(props.delta || "")});
                state.emitted += String(props.delta || "").length;
            }
        } else if (type === "file.edited") {
            // Carries no session id: only counted while one of this reply's tools runs.
            if (busy && props.file && toolRunning()) emit({"type": "file_changed", "path": String(props.file)});
        } else if (type === "session.error") {
            if (!errored) {
                errored = true;
                emit({"type": "error", "message": "OpenCode: " + _errorText(props.error, "session error."), "status": 0});
            }
        } else if (type === "session.status") {
            var status = (props.status || {}).type;
            if (status === "busy") busy = true;
            else if (status === "idle" && busy) finish();
        } else if (type === "session.idle") {
            if (busy) finish();
        }
    }

    return {
        "handle": handle,
        "isFinished": function() { return finished; },
        "markAborted": function() {
            if (finished) return;
            finished = true;
            emit({"type": "done", "reason": "aborted"});
        },
        // Catches up after the event stream was lost: history is the answer of
        // GET /session/:id/message; the messages after the last user message
        // are this reply. Text already shown is not repeated.
        "replay": function(history) {
            var last = -1;
            for (var i = 0; i < history.length; i++) {
                if (((history[i] || {}).info || {}).role === "user") last = i;
            }
            for (var m = last + 1; m < history.length; m++) {
                var item = history[m] || {};
                handle({"type": "message.updated", "properties": {"sessionID": sessionId, "info": item.info || {}}});
                for (var p = 0; p < (item.parts || []).length; p++)
                    handle({"type": "message.part.updated", "properties": {"sessionID": sessionId, "part": item.parts[p]}});
            }
        },
        // The session's state after a catch-up: still working, or done.
        "syncStatus": function(isBusy) {
            if (isBusy) busy = true;
            else finish();
        }
    };
}
