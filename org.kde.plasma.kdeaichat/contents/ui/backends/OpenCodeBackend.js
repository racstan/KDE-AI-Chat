.pragma library

// OpenCode backend: drives a running `opencode serve` over its HTTP API and
// reports progress as backend events (see DirectBackend.js for the shared
// contract). Checked against OpenCode 1.18 (`/doc`): sessions and prompts use
// the v1 routes with `?directory=`, progress comes from the `/event` stream.
//
// Events, in addition to the shared start/text_delta/reasoning_delta/usage/
// error/done:
//   {type: "session", id}                                 server session id to remember
//   {type: "tool_start", callId, name, input}
//   {type: "tool_update", callId, title}
//   {type: "tool_end", callId, output, title, isError}
//   {type: "file_changed", path}
//   {type: "permission_request", id, permission, patterns, metadata}
//   {type: "permission_resolved", id, reply}
//   {type: "question_request", id, questions}
//   {type: "question_resolved", id, status}               "answered" | "dismissed"
//
// Self-contained (no QML globals, no .import): the SSE parser and
// XMLHttpRequest are passed in, so tests run it in node.

function url(baseUrl, path, directory) {
    var base = String(baseUrl || "").replace(/\/+$/, "").replace(/\/v1$/, "");
    return base + path + (directory ? (path.indexOf("?") < 0 ? "?" : "&") + "directory=" + encodeURIComponent(directory) : "");
}

// Body for POST /session/:id/prompt_async.
function promptBody(options) {
    var body = {"parts": options.parts || []};
    if (options.agent)
        body.agent = options.agent;
    if (options.providerId && options.modelId && (!options.agent || options.useAgentModel === false))
        body.model = {"providerID": options.providerId, "modelID": options.modelId};
    if (options.system)
        body.system = options.system;
    return body;
}

function _errorText(error, fallback) {
    if (!error) return fallback;
    if (typeof error === "string") return error;
    var data = error.data || {};
    return String(data.message || error.message || error.name || fallback);
}

// Turns OpenCode events for one server session into backend events.
// emit(event) receives them; handle(eventObj) takes one parsed event (either
// {type, properties} from /event or {directory, payload} from /global/event).
function createEventMapper(sessionId, emit) {
    var roles = {};          // messageID -> "user" | "assistant"
    var parts = {};          // partID -> {kind: "text"|"reasoning"|..., emitted}
    var waiting = {};        // messageID -> [events] seen before its role was known
    var tools = {};          // callID -> last status
    var busy = false;
    var errored = false;
    var finished = false;

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
            tools[callId] = state.status || "pending";
        } else if (part.type === "step-finish" && part.tokens) {
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

    return {
        "isFinished": function() { return finished; },
        "markAborted": function() {
            if (finished) return;
            finished = true;
            emit({"type": "done", "reason": "aborted"});
        },
        "handle": function(eventObj) {
            if (finished || !eventObj) return;
            if (eventObj.payload && !eventObj.properties)
                eventObj = eventObj.payload;
            var type = eventObj.type || "";
            var props = eventObj.properties || {};
            if (props.sessionID !== undefined && props.sessionID !== sessionId)
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
                if (busy && props.file) emit({"type": "file_changed", "path": String(props.file)});
            } else if (type === "permission.asked" || type === "permission.v2.asked") {
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
    };
}

// One HTTP request; calls done(status, responseText).
function _request(xhrFactory, method, target, body, timeoutMs, done) {
    var xhr = xhrFactory();
    try {
        xhr.open(method, target, true);
        if (timeoutMs > 0) xhr.timeout = timeoutMs;
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) done(xhr.status, xhr.responseText || "");
        };
        xhr.onerror = function() { done(0, ""); };
        xhr.ontimeout = function() { done(-1, ""); };
        xhr.send(body === null ? null : JSON.stringify(body));
    } catch (e) {
        done(0, String(e));
    }
    return xhr;
}

// Runs one prompt. options:
//   baseUrl, directory, sessionId ("" = create one), title, body (promptBody),
//   xhrFactory(), parserFactory(onMessage) (DirectBackend.createSseParser),
//   onEvent(event)
// Returns {abort()}.
function send(options) {
    var directory = options.directory || "";
    var stream = null;
    var sessionId = options.sessionId || "";
    var mapper = null;
    var started = false;
    var closed = false;

    function emit(event) {
        if (!closed) options.onEvent(event);
        if (event.type === "done") close();
    }
    function close() {
        if (closed) return;
        closed = true;
        if (stream) { try { stream.abort(); } catch (e) {} }
    }
    function fail(message) {
        if (closed) return;
        options.onEvent({"type": "error", "message": message, "status": 0});
        options.onEvent({"type": "done", "reason": "error"});
        close();
    }
    function prompt() {
        if (started || closed) return;
        started = true;
        _request(options.xhrFactory, "POST", url(options.baseUrl, "/session/" + encodeURIComponent(sessionId) + "/prompt_async", directory),
                 options.body, 30000, function(status, text) {
            if (status < 200 || status >= 300)
                fail(status === 0 ? "OpenCode: could not reach the server at " + options.baseUrl + "."
                     : "OpenCode: the server refused the prompt (HTTP " + status + ")." + (text ? " " + text.substring(0, 300) : ""));
        });
    }
    function openStream() {
        var offset = 0;
        var parser = options.parserFactory(function(message) {
            var obj;
            try { obj = JSON.parse(message.data); } catch (e) { return; }
            var type = (obj.payload || obj).type;
            if (type === "server.connected") prompt();
            else if (mapper) mapper.handle(obj);
        });
        stream = options.xhrFactory();
        stream.onreadystatechange = function() {
            if (stream.readyState !== 3 && stream.readyState !== 4) return;
            var text = stream.responseText || "";
            parser.push(text.substring(offset));
            offset = text.length;
            if (offset > 50000000) { close(); fail("OpenCode: the event stream grew too large."); }
            if (stream.readyState === 4 && !closed) fail("OpenCode: the server closed the event stream.");
        };
        stream.onerror = function() { fail("OpenCode: lost the connection to the server's event stream."); };
        stream.open("GET", url(options.baseUrl, "/event", directory), true);
        stream.send();
    }
    function begin() {
        mapper = createEventMapper(sessionId, emit);
        emit({"type": "start"});
        openStream();
    }

    if (sessionId) {
        begin();
    } else {
        _request(options.xhrFactory, "POST", url(options.baseUrl, "/session", directory), {"title": options.title || "KDE AI Chat"}, 15000,
                 function(status, text) {
            var id = "";
            try { id = status >= 200 && status < 300 ? String(JSON.parse(text).id || "") : ""; } catch (e) { id = ""; }
            if (!id) {
                fail(status === 0 ? "OpenCode: could not reach the server at " + options.baseUrl + ". Is `opencode serve` running?"
                     : "OpenCode: could not create a session (HTTP " + status + ").");
                return;
            }
            sessionId = id;
            options.onEvent({"type": "session", "id": id});
            begin();
        });
    }

    return {
        "abort": function() {
            if (closed) return;
            if (sessionId)
                _request(options.xhrFactory, "POST", url(options.baseUrl, "/session/" + encodeURIComponent(sessionId) + "/abort", directory), null, 10000, function() {});
            if (mapper) mapper.markAborted();
            else { options.onEvent({"type": "done", "reason": "aborted"}); close(); }
        }
    };
}

// Answers a permission request: reply is "once" | "always" | "reject".
function replyPermission(options, requestId, reply, done) {
    _request(options.xhrFactory, "POST", url(options.baseUrl, "/permission/" + encodeURIComponent(requestId) + "/reply", options.directory),
             {"reply": reply}, 15000, function(status) { if (done) done(status >= 200 && status < 300, status); });
}

// Answers a question: answers is one array of selected labels per question;
// null rejects it.
function replyQuestion(options, requestId, answers, done) {
    var path = "/question/" + encodeURIComponent(requestId) + (answers === null ? "/reject" : "/reply");
    _request(options.xhrFactory, "POST", url(options.baseUrl, path, options.directory),
             answers === null ? null : {"answers": answers}, 15000, function(status) { if (done) done(status >= 200 && status < 300, status); });
}
