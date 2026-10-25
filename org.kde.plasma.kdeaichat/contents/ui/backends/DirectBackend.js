.pragma library

// Direct API backend: talks to an OpenAI-compatible or Anthropic endpoint
// with the user's key and reports progress as backend events.
//
// Event contract (shared by every backend; Phase 3 adds tool/permission
// events):
//   {type: "start"}
//   {type: "text_delta", delta}        visible answer text
//   {type: "reasoning_delta", delta}   model reasoning / <think> content
//   {type: "usage", input, output, cost?}  as the provider reported it, never an
//                                      estimate; cost only where it reports one
//                                      (OpenRouter); one per OpenAI-style request
//   {type: "error", message, status}   the request failed; "done" follows
//   {type: "done", reason}             "complete" | "aborted" | "error"
//
// Self-contained on purpose: no QML globals and no .import, so tests run it
// in node with a fake XMLHttpRequest.

var DEFAULT_MAX_TOKENS = 4096;
var MAX_RESPONSE_BYTES = 20000000;

// An OpenAI-style stream only carries token counts when asked
// (stream_options.include_usage). Every streaming request asks; a server that
// answers 400/422 naming the field gets the request again without it, and
// its base URL is remembered so that happens once per session.
var _rejectsStreamOptions = {};

// --- Server-sent events -----------------------------------------------------

// Feeds raw text chunks; calls onMessage({event, data}) per SSE message.
function createSseParser(onMessage) {
    var buffer = "", eventName = "", dataLines = [];

    function dispatch() {
        if (dataLines.length > 0)
            onMessage({"event": eventName || "message", "data": dataLines.join("\n")});
        eventName = "";
        dataLines = [];
    }

    function line(text) {
        if (text === "") {
            dispatch();
            return;
        }
        if (text.charAt(0) === ":")
            return;
        var colon = text.indexOf(":");
        var field = colon < 0 ? text : text.substring(0, colon);
        var value = colon < 0 ? "" : text.substring(colon + 1);
        if (value.charAt(0) === " ")
            value = value.substring(1);
        if (field === "data")
            dataLines.push(value);
        else if (field === "event")
            eventName = value;
    }

    return {
        "push": function(chunk) {
            buffer += chunk;
            // Walk the lines by index and cut the buffer once: cutting it
            // per line copies the rest each time (quadratic in a big chunk).
            var start = 0;
            var newline;
            while ((newline = buffer.indexOf("\n", start)) >= 0) {
                var text = buffer.substring(start, newline);
                start = newline + 1;
                if (text.charAt(text.length - 1) === "\r")
                    text = text.substring(0, text.length - 1);
                line(text);
            }
            if (start > 0)
                buffer = buffer.substring(start);
        },
        "end": function() {
            if (buffer !== "")
                line(buffer);
            buffer = "";
            dispatch();
        }
    };
}

// --- <think> blocks ------------------------------------------------------------

// Splits a text stream into answer and <think>…</think> reasoning, even when a
// tag is cut across chunks. emit(kind, text) with kind "text" or "reasoning".
function createThinkSplitter(emit) {
    var OPEN = "<think>", CLOSE = "</think>";
    var inside = false;
    var pending = "";

    function partialTagAt(text, tag) {
        // Length of the longest suffix of `text` that is a prefix of `tag`.
        for (var n = Math.min(tag.length - 1, text.length); n > 0; n--) {
            if (text.substring(text.length - n) === tag.substring(0, n))
                return n;
        }
        return 0;
    }

    return {
        "push": function(chunk) {
            var text = pending + chunk;
            pending = "";
            while (text.length > 0) {
                var tag = inside ? CLOSE : OPEN;
                var at = text.indexOf(tag);
                if (at < 0) {
                    var keep = partialTagAt(text, tag);
                    var out = text.substring(0, text.length - keep);
                    if (out) emit(inside ? "reasoning" : "text", out);
                    pending = text.substring(text.length - keep);
                    return;
                }
                if (at > 0) emit(inside ? "reasoning" : "text", text.substring(0, at));
                text = text.substring(at + tag.length);
                inside = !inside;
            }
        },
        "end": function() {
            if (pending) emit(inside ? "reasoning" : "text", pending);
            pending = "";
        }
    };
}

// --- Requests -----------------------------------------------------------------

function _trimSlash(url) {
    return String(url || "").replace(/\/+$/, "");
}

// Builds {url, headers, body} for one request.
// options: {type, baseUrl, apiKey, model, headers, system, messages, maxTokens, stream,
//           streamUsage}  (streamUsage: false leaves out stream_options.include_usage)
function buildRequest(options) {
    var headers = {"Content-Type": "application/json"};
    var extra = options.headers || {};
    var maxTokens = options.maxTokens > 0 ? options.maxTokens : DEFAULT_MAX_TOKENS;
    var body, url;
    if (options.type === "anthropic") {
        url = _trimSlash(options.baseUrl || "https://api.anthropic.com/v1");
        if (!/\/messages$/.test(url))
            url += "/messages";
        headers["x-api-key"] = options.apiKey || "";
        headers["anthropic-version"] = "2023-06-01";
        body = {"model": options.model, "max_tokens": maxTokens, "messages": options.messages, "stream": options.stream !== false};
        if (options.system)
            body.system = options.system;
    } else {
        url = _trimSlash(options.baseUrl) + "/chat/completions";
        if (options.apiKey)
            headers["Authorization"] = "Bearer " + options.apiKey;
        var messages = options.messages.slice();
        if (options.system)
            messages.unshift({"role": "system", "content": options.system});
        body = {"model": options.model, "messages": messages, "max_tokens": maxTokens, "stream": options.stream !== false};
        if (body.stream && options.streamUsage !== false && !_rejectsStreamOptions[_trimSlash(options.baseUrl)])
            body.stream_options = {"include_usage": true};
        // OpenRouter reports the real cost of the request in its usage block.
        if (/^https?:\/\/([^/]*\.)?openrouter\.ai(\/|$)/i.test(String(options.baseUrl || "")))
            body.usage = {"include": true};
    }
    for (var name in extra) {
        if (Object.prototype.hasOwnProperty.call(extra, name) && extra[name])
            headers[name] = String(extra[name]);
    }
    return {"url": url, "headers": headers, "body": body};
}

// A readable error from an HTTP failure response.
function errorMessage(status, responseText, url) {
    var detail = "";
    try {
        var obj = JSON.parse(responseText);
        var err = obj.error !== undefined ? obj.error : obj;
        if (typeof err === "string") detail = err;
        else if (err && err.message) detail = String(err.message);
        else if (obj.message) detail = String(obj.message);
        else if (obj.detail) detail = typeof obj.detail === "string" ? obj.detail : JSON.stringify(obj.detail);
    } catch (e) {
        detail = String(responseText || "").substring(0, 300).trim();
    }
    if (status === 401 || status === 403)
        return "The provider rejected the API key (HTTP " + status + "). Check the key in Settings." + (detail ? " " + detail : "");
    if (status === 0)
        return "Could not reach " + url + ". Check the server URL and your network.";
    return "Request to " + url + " failed (HTTP " + status + ")" + (detail ? ": " + detail : "");
}

// `cost` only when the provider reports one (OpenRouter's usage.cost, USD).
function _openAiUsage(usage) {
    var event = {"type": "usage", "input": usage.prompt_tokens || usage.input_tokens || 0,
                 "output": usage.completion_tokens || usage.output_tokens || 0};
    if (usage.cost !== undefined && usage.cost !== null && isFinite(Number(usage.cost)) && Number(usage.cost) >= 0)
        event.cost = Number(usage.cost);
    return event;
}

// Anthropic reports cached prompt tokens next to input_tokens; the prompt the
// model read is all of them. Fields a message doesn't carry stay out of the event.
function _anthropicUsage(usage) {
    var event = {"type": "usage"};
    if (usage.input_tokens !== undefined)
        event.input = usage.input_tokens + (usage.cache_read_input_tokens || 0) + (usage.cache_creation_input_tokens || 0);
    if (usage.output_tokens !== undefined) event.output = usage.output_tokens;
    return event;
}

// Turns one parsed streaming JSON message into events. Returns false if the
// message signals the end of the stream.
function _handleStreamMessage(type, sse, think, emit) {
    if (sse.data === "[DONE]")
        return false;
    var obj;
    try {
        obj = JSON.parse(sse.data);
    } catch (e) {
        return true;
    }
    if (obj.error) {
        emit({"type": "error", "message": typeof obj.error === "string" ? obj.error : String(obj.error.message || JSON.stringify(obj.error)), "status": 200});
        return false;
    }
    if (type === "anthropic") {
        if (obj.type === "message_start" && obj.message && obj.message.usage)
            emit(_anthropicUsage(obj.message.usage));
        else if (obj.type === "content_block_delta" && obj.delta) {
            if (obj.delta.type === "text_delta" && obj.delta.text) think.push(obj.delta.text);
            else if (obj.delta.type === "thinking_delta" && obj.delta.thinking) emit({"type": "reasoning_delta", "delta": obj.delta.thinking});
        } else if (obj.type === "message_delta" && obj.usage)
            emit(_anthropicUsage(obj.usage));
        else if (obj.type === "message_stop")
            return false;
        return true;
    }
    var choice = obj.choices && obj.choices[0];
    var delta = choice && (choice.delta || choice.message);
    if (delta) {
        var reasoning = delta.reasoning || delta.reasoning_content || delta.thinking || "";
        if (reasoning) emit({"type": "reasoning_delta", "delta": String(reasoning)});
        if (delta.content) think.push(typeof delta.content === "string" ? delta.content : JSON.stringify(delta.content));
    }
    if (obj.usage)
        emit(_openAiUsage(obj.usage));
    return true;
}

// Events for a complete (non-streaming) JSON response.
function _handleFullResponse(type, obj, think, emit) {
    if (type === "anthropic") {
        var blocks = obj.content || [];
        for (var i = 0; i < blocks.length; i++) {
            if (blocks[i].type === "text") think.push(String(blocks[i].text || ""));
            else if (blocks[i].type === "thinking") emit({"type": "reasoning_delta", "delta": String(blocks[i].thinking || "")});
        }
        if (obj.usage) emit(_anthropicUsage(obj.usage));
        return;
    }
    var message = (obj.choices && obj.choices[0] && obj.choices[0].message) || {};
    var reasoning = message.reasoning || message.reasoning_content || "";
    if (reasoning) emit({"type": "reasoning_delta", "delta": String(reasoning)});
    if (message.content) think.push(typeof message.content === "string" ? message.content : JSON.stringify(message.content));
    if (obj.usage) emit(_openAiUsage(obj.usage));
}


// Sends one request. options as for buildRequest, plus:
//   xhrFactory()  returns a new XMLHttpRequest
//   timeoutMs     0 = no timeout
//   onEvent(event)
// Returns {abort()}.
function send(options) {
    var request = buildRequest(options);
    var stream = request.body.stream;
    var xhr;
    var finished = false, offset = 0, retried = false;
    // OpenAI-style servers may repeat usage in several chunks (cumulative, or
    // only the last one counts): keep the latest and report it once, at the end.
    var usage = null;

    function emit(event) {
        if (!finished)
            options.onEvent(event);
    }
    function finish(reason, message, status) {
        if (finished) return;
        think.end();
        if (reason === "complete" && usage)
            emit(usage);
        if (reason === "error")
            emit({"type": "error", "message": message, "status": status || 0});
        emit({"type": "done", "reason": reason});
        finished = true;
    }

    var think = createThinkSplitter(function(kind, text) {
        emit({"type": kind === "text" ? "text_delta" : "reasoning_delta", "delta": text});
    });
    var sseEnded = false;
    var sse;

    function newSse() {
        sseEnded = false;
        sse = createSseParser(function(message) {
            if (sseEnded) return;
            var more = _handleStreamMessage(options.type, message, think, function(event) {
                if (event.type === "error") finish("error", event.message, event.status);
                else if (event.type === "usage" && options.type !== "anthropic")
                    usage = Object.assign(usage || {}, event);
                else emit(event);
            });
            if (!more) sseEnded = true;
        });
    }

    function consume() {
        var text = xhr.responseText || "";
        if (text.length > MAX_RESPONSE_BYTES) {
            try { xhr.abort(); } catch (e) {}
            finish("error", "The provider's response was too large.", 200);
            return;
        }
        sse.push(text.substring(offset));
        offset = text.length;
    }

    function open(isRetry) {
        xhr = options.xhrFactory();
        newSse();
        xhr.onreadystatechange = function() {
            if (finished || (xhr.readyState !== 3 && xhr.readyState !== 4))
                return;
            if (xhr.status < 200 || xhr.status >= 300) {
                if (xhr.readyState !== 4)
                    return;
                if (!retried && request.body.stream_options && (xhr.status === 400 || xhr.status === 422)
                        && /stream_options|include_usage/i.test(xhr.responseText || "")) {
                    _rejectsStreamOptions[_trimSlash(options.baseUrl)] = true;
                    retried = true;
                    request = buildRequest(options);
                    offset = 0;
                    open(true);
                } else
                    finish("error", errorMessage(xhr.status, xhr.responseText, request.url), xhr.status);
                return;
            }
            if (stream) {
                consume();
                if (xhr.readyState === 4) {
                    sse.end();
                    if (!finished) finish("complete");
                }
                return;
            }
            if (xhr.readyState === 4) {
                try {
                    _handleFullResponse(options.type, JSON.parse(xhr.responseText), think, emit);
                    finish("complete");
                } catch (e) {
                    finish("error", "Could not read the provider's response: " + e, xhr.status);
                }
            }
        };
        xhr.onerror = function() {
            finish("error", errorMessage(0, "", request.url), 0);
        };
        xhr.ontimeout = function() {
            finish("error", "Request to " + request.url + " timed out after " + Math.round(options.timeoutMs / 1000) + " seconds.", 0);
        };

        try {
            xhr.open("POST", request.url, true);
            if (options.timeoutMs > 0)
                xhr.timeout = options.timeoutMs;
            for (var name in request.headers)
                xhr.setRequestHeader(name, request.headers[name]);
            if (!isRetry)
                emit({"type": "start"});
            xhr.send(JSON.stringify(request.body));
        } catch (e) {
            finish("error", "Could not start the request: " + e, 0);
        }
    }

    open(false);

    return {
        "abort": function() {
            if (finished) return;
            try { xhr.abort(); } catch (e) {}
            finish("aborted");
        }
    };
}
