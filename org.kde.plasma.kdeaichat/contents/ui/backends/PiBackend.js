.pragma library

// Pi backend: talks to the Pi bridge (kdeaichat/pi_bridge_server.py), which
// runs `pi --mode rpc` for each chat, and reports progress as backend events
// (see DirectBackend.js and OpenCodeBackend.js for the shared contract).
// Checked against Pi 0.84 RPC mode (docs/rpc.md in the Pi package).
//
// Pi has no permission system of its own: extensions ask through dialogs.
// A `confirm` dialog becomes a permission_request; `select`, `input` and
// `editor` dialogs become a question_request with one question. Answers go
// back with replyDialog(). `notify` dialogs and retries become
//   {type: "notice", message, level}
//
// Self-contained (no QML globals, no .import): the SSE parser and
// XMLHttpRequest are passed in, so tests run it in node.

var FILE_TOOLS = {"write": true, "edit": true};

function chatPath(chatId, action) {
    return "/chats/" + encodeURIComponent(chatId) + "/" + action;
}

function _text(content) {
    var out = [];
    for (var i = 0; i < (content || []).length; i++)
        if (content[i] && content[i].type === "text") out.push(String(content[i].text || ""));
    return out.join("\n");
}

// Turns Pi RPC events (one parsed JSON object each) into backend events.
function createEventMapper(emit) {
    var blocks = {};        // contentIndex -> {kind, emitted} for the current assistant message
    var wroteText = false;  // text was already emitted in an earlier message of this run
    var tools = {};         // toolCallId -> args
    var errored = false;
    var aborted = false;
    var finished = false;

    function delta(index, kind, text, isFull) {
        var block = blocks[index] || (blocks[index] = {"kind": kind, "text": ""});
        if (isFull) {
            // *_end carries the whole block; send only what the deltas missed.
            if (text.indexOf(block.text) !== 0 || text.length <= block.text.length) return;
            text = text.substring(block.text.length);
        }
        if (!text) return;
        if (kind === "text" && block.text === "" && wroteText)
            emit({"type": "text_delta", "delta": "\n\n"});
        block.text += text;
        if (kind === "text") wroteText = true;
        emit({"type": kind === "thinking" ? "reasoning_delta" : "text_delta", "delta": text});
    }

    function finish(reason) {
        if (finished) return;
        finished = true;
        emit({"type": "done", "reason": reason});
    }

    function fail(message) {
        if (errored) return;
        errored = true;
        emit({"type": "error", "message": message, "status": 0});
    }

    function dialog(event) {
        var method = event.method;
        var id = String(event.id || "");
        if (method === "confirm") {
            emit({"type": "permission_request", "id": id, "permission": String(event.title || "Allow?"),
                  "patterns": event.message ? [String(event.message)] : [], "metadata": {}});
        } else if (method === "select" || method === "input" || method === "editor") {
            var options = method === "select" ? (event.options || []).map(function(o) { return {"label": String(o), "description": ""}; }) : [];
            emit({"type": "question_request", "id": id, "questions": [{"header": "", "question": String(event.title || ""),
                  "options": options, "custom": method !== "select", "multiple": false}]});
        } else if (method === "notify") {
            emit({"type": "notice", "message": String(event.message || ""), "level": String(event.notifyType || "info")});
        }
    }

    return {
        "isFinished": function() { return finished; },
        "markAborted": function() { finish("aborted"); },
        "handle": function(event) {
            if (finished || !event) return;
            var type = event.type || "";
            if (type === "response") {
                if (event.command === "prompt" && event.success === false) {
                    fail("Pi refused the message: " + String(event.error || "unknown error"));
                    finish("error");
                }
            } else if (type === "message_start") {
                if ((event.message || {}).role === "assistant") blocks = {};
            } else if (type === "message_update") {
                var e = event.assistantMessageEvent || {};
                if (e.type === "text_delta" || e.type === "thinking_delta")
                    delta(e.contentIndex, e.type === "text_delta" ? "text" : "thinking", String(e.delta || ""), false);
                else if (e.type === "text_end" || e.type === "thinking_end")
                    delta(e.contentIndex, e.type === "text_end" ? "text" : "thinking", String(e.content || ""), true);
            } else if (type === "message_end") {
                var message = event.message || {};
                if (message.role !== "assistant") return;
                var usage = message.usage || {};
                if (usage.input || usage.output)
                    emit({"type": "usage", "input": usage.input || 0, "output": usage.output || 0,
                          "cost": (usage.cost || {}).total || 0});
                if (message.stopReason === "error")
                    fail("Pi: " + String(message.errorMessage || "the request failed."));
                else if (message.stopReason === "aborted")
                    aborted = true;
            } else if (type === "tool_execution_start") {
                tools[event.toolCallId] = event.args || {};
                emit({"type": "tool_start", "callId": String(event.toolCallId || ""), "name": String(event.toolName || "tool"), "input": event.args || {}});
            } else if (type === "tool_execution_end") {
                emit({"type": "tool_end", "callId": String(event.toolCallId || ""), "title": "",
                      "output": _text((event.result || {}).content).substring(0, 20000), "isError": event.isError === true});
                var args = tools[event.toolCallId] || {};
                if (!event.isError && FILE_TOOLS[event.toolName] && args.path)
                    emit({"type": "file_changed", "path": String(args.path)});
            } else if (type === "extension_ui_request") {
                dialog(event);
            } else if (type === "auto_retry_start") {
                emit({"type": "notice", "message": "Pi is retrying (attempt " + event.attempt + " of " + event.maxAttempts + "): "
                      + String(event.errorMessage || "").substring(0, 200), "level": "warning"});
            } else if (type === "extension_error") {
                emit({"type": "notice", "message": "A Pi extension failed: " + String(event.error || ""), "level": "warning"});
            } else if (type === "agent_settled") {
                finish(errored ? "error" : aborted ? "aborted" : "complete");
            } else if (type === "bridge_exit") {
                var detail = String(event.stderr || "").trim().split("\n").slice(-5).join("\n");
                fail("Pi stopped unexpectedly (exit code " + event.code + ")." + (detail ? "\n\n```\n" + detail + "\n```" : ""));
                finish("error");
            }
        }
    };
}

// One HTTP request to the bridge; calls done(status, responseText).
function _request(options, method, path, body, timeoutMs, done) {
    var xhr = options.xhrFactory();
    try {
        xhr.open(method, options.baseUrl + path, true);
        if (timeoutMs > 0) xhr.timeout = timeoutMs;
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.setRequestHeader("Authorization", "Bearer " + options.token);
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

function _errorFrom(text) {
    try { return String(JSON.parse(text).error || ""); } catch (e) { return ""; }
}

// Runs one prompt. options:
//   baseUrl, token, chatId, body ({directory, provider, model, thinking, message, images}),
//   xhrFactory(), parserFactory(onMessage) (DirectBackend.createSseParser),
//   onEvent(event),
//   timers ({start(ms, fn) -> handle, clear(handle)}; QML has no setTimeout) and stallMs
//   (default STALL_MS): the watchdog, see below. Without timers there is none.
// Returns {abort()}.
//
// Watchdog: once the bridge has accepted the prompt, every Pi event restarts a
// stallMs timer, so a slow model that keeps sending (thinking deltas, tool
// output) is never cut off. When it fires with no event at all since the
// prompt, Pi never started on it; when events came but stopped, the bridge's
// /status is asked, and Pi still running there means a long tool or a dialog
// the user hasn't answered yet (keep waiting), anything else ends the reply
// with an error. The timer is cleared on done, error and abort.
var STALL_MS = 60000;

function send(options) {
    var stream = null;
    var timer = null;
    var accepted = false;   // the bridge took the prompt
    var gotEvent = false;   // Pi sent something since then
    var stamp = 0;          // counts events, so a late status answer can tell it is stale
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
        stopTimer();
        if (stream) { try { stream.abort(); } catch (e) {} }
    }
    function stopTimer() {
        if (timer !== null && options.timers) options.timers.clear(timer);
        timer = null;
    }
    function arm() {
        stopTimer();
        if (closed || !accepted || !options.timers) return;
        timer = options.timers.start(options.stallMs || STALL_MS, onStall);
    }
    function stalled(why) {
        if (closed) return;
        // Free the chat for Try again: a Pi that never answered may still hold it as busy.
        _request(options, "POST", chatPath(options.chatId, "close"), {}, 10000, function() {});
        fail("Pi stopped responding (" + why + ").");
    }
    function onStall() {
        timer = null;
        if (closed) return;
        if (!gotEvent) { stalled("it never started on your message"); return; }
        var seen = stamp;
        _request(options, "GET", chatPath(options.chatId, "status"), null, 10000, function(status, text) {
            if (closed || seen !== stamp) return;
            var info = {};
            try { info = JSON.parse(text); } catch (e) {}
            if (status === 200 && info.running === true) arm();
            else stalled("it is no longer working on your message");
        });
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
        _request(options, "POST", chatPath(options.chatId, "prompt"), options.body, 30000, function(status, text) {
            if (status < 200 || status >= 300)
                fail(status === 0 ? "Pi: lost the connection to the Pi bridge."
                     : "Pi: " + (_errorFrom(text) || "the bridge refused the message (HTTP " + status + ")."));
            else if (!closed) { accepted = true; arm(); }
        });
    }

    mapper = createEventMapper(emit);
    emit({"type": "start"});
    var offset = 0;
    var parser = options.parserFactory(function(message) {
        var obj;
        try { obj = JSON.parse(message.data); } catch (e) { return; }
        if (obj.type === "bridge_connected") prompt();
        else {
            gotEvent = true;
            stamp++;
            arm();
            mapper.handle(obj);
        }
    });
    stream = options.xhrFactory();
    stream.onreadystatechange = function() {
        if (stream.readyState !== 3 && stream.readyState !== 4) return;
        var text = stream.responseText || "";
        parser.push(text.substring(offset));
        offset = text.length;
        if (offset > 50000000) { close(); fail("Pi: the event stream grew too large."); }
        if (stream.readyState === 4 && !closed)
            fail(stream.status === 401 ? "Pi: the bridge didn't accept the widget's token." : "Pi: the bridge closed the event stream.");
    };
    stream.onerror = function() { fail("Pi: lost the connection to the Pi bridge."); };
    stream.open("GET", options.baseUrl + chatPath(options.chatId, "events"), true);
    stream.setRequestHeader("Authorization", "Bearer " + options.token);
    stream.send();

    return {
        "abort": function() {
            if (closed) return;
            _request(options, "POST", chatPath(options.chatId, "abort"), {}, 10000, function() {});
            mapper.markAborted();
        }
    };
}

// Answers an extension dialog. response is {value}, {confirmed} or {cancelled: true}.
function replyDialog(options, chatId, requestId, response, done) {
    var body = Object.assign({"id": requestId}, response);
    _request(options, "POST", chatPath(chatId, "ui-response"), body, 15000, function(status) {
        if (done) done(status >= 200 && status < 300, status);
    });
}
