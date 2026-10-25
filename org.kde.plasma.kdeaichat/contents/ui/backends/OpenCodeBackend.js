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
//   {type: "notice", level: "info", message}
//   {type: "permission_request", id, permission, patterns, metadata}
//   {type: "permission_resolved", id, reply}
//   {type: "question_request", id, questions}
//   {type: "question_resolved", id, status}               "answered" | "dismissed"
//
// Self-contained (no QML globals, no .import): the SSE parser, the event
// mapper (OpenCodeEvents.createEventMapper) and XMLHttpRequest are passed in,
// so tests run it in node.

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
    // The model's variant, by name (Variants.fromOpenCodeNames): OpenCode merges
    // that variant's options itself. Only this one key is taken from the fragment.
    if (options.variantSend && options.variantSend.variant)
        body.variant = String(options.variantSend.variant);
    return body;
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

function _json(status, text, fallback) {
    if (status < 200 || status >= 300) return fallback;
    try { return JSON.parse(text); } catch (e) { return fallback; }
}

// Runs one prompt. options:
//   baseUrl, directory, sessionId ("" = create one), title, body (promptBody),
//   xhrFactory(), parserFactory(onMessage) (DirectBackend.createSseParser),
//   mapperFactory(sessionId, emit) (OpenCodeEvents.createEventMapper),
//   onEvent(event), later(fn, ms) (runs fn after ms; default: right away),
//   maxReconnects (default 5)
// A lost event stream is reopened (the reply goes on on the server) and the
// reply caught up from the session's messages. A session the server doesn't
// know any more (HTTP 404) is replaced by a new one, once.
// Returns {abort()}.
function send(options) {
    var directory = options.directory || "";
    var later = options.later || function(fn) { fn(); };
    var maxReconnects = options.maxReconnects === undefined ? 5 : options.maxReconnects;
    var stream = null;
    var sessionId = options.sessionId || "";
    var mapper = null;
    var started = false;
    var accepted = false;
    var renewed = false;
    var closed = false;
    var reconnects = 0;

    function emit(event) {
        if (!closed) options.onEvent(event);
        if (event.type === "done") close();
    }
    function close() {
        if (closed) return;
        closed = true;
        var old = stream;
        stream = null;
        if (old) { try { old.abort(); } catch (e) {} }
    }
    function fail(message) {
        if (closed) return;
        options.onEvent({"type": "error", "message": message, "status": 0});
        options.onEvent({"type": "done", "reason": "error"});
        close();
    }
    function createSession(done) {
        _request(options.xhrFactory, "POST", url(options.baseUrl, "/session", directory), {"title": options.title || "KDE AI Chat"}, 15000,
                 function(status, text) {
            if (closed) return;
            var id = String((_json(status, text, {}) || {}).id || "");
            if (!id) {
                fail(status === 0 ? "OpenCode: could not reach the server at " + options.baseUrl + ". Is `opencode serve` running?"
                     : "OpenCode: could not create a session (HTTP " + status + ").");
                return;
            }
            sessionId = id;
            mapper = options.mapperFactory(sessionId, emit);
            options.onEvent({"type": "session", "id": id});
            done();
        });
    }
    function prompt() {
        if (started || closed) return;
        started = true;
        _request(options.xhrFactory, "POST", url(options.baseUrl, "/session/" + encodeURIComponent(sessionId) + "/prompt_async", directory),
                 options.body, 30000, function(status, text) {
            if (closed) return;
            if (status >= 200 && status < 300) {
                accepted = true;
            } else if (status === 404 && !renewed) {
                renewed = true;
                createSession(function() {
                    emit({"type": "notice", "level": "info", "message": "OpenCode no longer had this chat's session; continuing in a new one."});
                    started = false;
                    prompt();
                });
            } else {
                fail(status === 0 ? "OpenCode: could not reach the server at " + options.baseUrl + "."
                     : "OpenCode: the server refused the prompt (HTTP " + status + ")." + (text ? " " + text.substring(0, 300) : ""));
            }
        });
    }
    // After a reconnect: the reply's messages and open requests, then whether it still runs.
    function catchUp() {
        var m = mapper;
        var get = function(path, done) {
            _request(options.xhrFactory, "GET", url(options.baseUrl, path, directory), null, 15000, function(status, text) {
                if (!closed && m === mapper) done(status, text);
            });
        };
        get("/session/" + encodeURIComponent(sessionId) + "/message", function(status, text) {
            var history = _json(status, text, null);
            if (Array.isArray(history)) m.replay(history);
            get("/permission", function(s1, t1) {
                var asked = _json(s1, t1, []);
                for (var i = 0; Array.isArray(asked) && i < asked.length; i++) m.handle({"type": "permission.asked", "properties": asked[i]});
                get("/question", function(s2, t2) {
                    var questions = _json(s2, t2, []);
                    for (var j = 0; Array.isArray(questions) && j < questions.length; j++) m.handle({"type": "question.asked", "properties": questions[j]});
                    get("/session/status", function(s3, t3) {
                        var states = _json(s3, t3, null);
                        if (states && typeof states === "object")
                            m.syncStatus(!!states[sessionId] && states[sessionId].type !== "idle");
                    });
                });
            });
        });
    }
    function lost() {
        if (closed || (mapper && mapper.isFinished())) return;
        var old = stream;
        stream = null;
        if (old) { try { old.abort(); } catch (e) {} }
        if (reconnects >= maxReconnects) {
            fail("OpenCode: lost the connection to the server's event stream.");
            return;
        }
        reconnects++;
        later(function() { if (!closed) openStream(); }, 500 * Math.pow(2, reconnects - 1));
    }
    function openStream() {
        var offset = 0;
        var xhr = options.xhrFactory();
        var resumed = started;
        var parser = options.parserFactory(function(message) {
            if (closed || stream !== xhr) return;
            var obj;
            try { obj = JSON.parse(message.data); } catch (e) { return; }
            var type = (obj.payload || obj).type;
            if (type === "server.connected") {
                reconnects = 0;
                if (!started) prompt();
                else if (resumed && accepted) catchUp();
            } else if (mapper) {
                mapper.handle(obj);
            }
        });
        stream = xhr;
        xhr.onreadystatechange = function() {
            if (closed || stream !== xhr || (xhr.readyState !== 3 && xhr.readyState !== 4)) return;
            var text = xhr.responseText || "";
            parser.push(text.substring(offset));
            offset = text.length;
            if (stream === xhr && (xhr.readyState === 4 || offset > 50000000)) lost();
        };
        xhr.onerror = function() { if (stream === xhr) lost(); };
        xhr.open("GET", url(options.baseUrl, "/event", directory), true);
        xhr.send();
    }
    function begin() {
        emit({"type": "start"});
        openStream();
    }

    if (sessionId) {
        mapper = options.mapperFactory(sessionId, emit);
        begin();
    } else {
        createSession(begin);
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
