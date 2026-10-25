.pragma library

// Direct API backend: talks to an OpenAI-compatible or Anthropic endpoint with the user's key and
// reports progress as backend events:
//   {type: "start"} | {type: "text_delta", delta} | {type: "reasoning_delta", delta}
//   {type: "usage", input, output, cost?}   as the provider reported it, never an estimate
//   {type: "images", items}                images the model sent (options.images = chat/ImageExtract.js; items: see it)
//   {type: "tool_calls", calls, thinking}   the model asked for tools (DirectTools.js), before "done"
//   {type: "error", message, status}        the request failed; "done" follows
//   {type: "done", reason}                  "complete" | "aborted" | "error"
// Self-contained on purpose (no QML globals, no .import): tests run it in node with a fake XMLHttpRequest.

var DEFAULT_MAX_TOKENS = 4096;
var MAX_RESPONSE_BYTES = 20000000;

// A server that answers 400/422 naming stream_options (token counts) or tools gets the request again
// without them, and is remembered so that happens once per session.
var _rejectsStreamOptions = {};
var _rejectsToolsFor = {};

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

// --- Requests -----------------------------------------------------------------

function _trimSlash(url) {
    return String(url || "").replace(/\/+$/, "");
}

function _toolsKey(options) {
    return _trimSlash(options.baseUrl) + "|" + options.model;
}

// True once this model answered a request with tools by refusing them.
function rejectsTools(options) {
    return _rejectsToolsFor[_toolsKey(options)] === true;
}

function _retryReason(status, text, body) {
    if (status !== 400 && status !== 422)
        return "";
    if (body.stream_options && /stream_options|include_usage/i.test(text))
        return "stream_options";
    return body.tools && /tool|function/i.test(text) ? "tools" : "";
}

// Builds {url, headers, body} for one request.
// options: {type, baseUrl, apiKey, model, headers, system, messages, maxTokens, stream, streamUsage,
//           variantSend, tools, plainMessages}  (streamUsage: false: no stream_options.include_usage;
//           variantSend: the chosen model variant's request fragment, Variants.sendFor, {} for none;
//           tools: DirectTools.toolDefinitions; plainMessages: the messages without tool calls, for a
//           model that refuses tools)
function buildRequest(options) {
    var tools = options.tools && options.tools.length > 0 && !rejectsTools(options) ? options.tools : null;
    var history = !tools && options.plainMessages ? options.plainMessages : options.messages;
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
        body = {"model": options.model, "max_tokens": maxTokens, "messages": history, "stream": options.stream !== false};
        if (options.system)
            body.system = options.system;
    } else {
        url = _trimSlash(options.baseUrl) + "/chat/completions";
        if (options.apiKey)
            headers["Authorization"] = "Bearer " + options.apiKey;
        var messages = history.slice();
        if (options.system)
            messages.unshift({"role": "system", "content": options.system});
        body = {"model": options.model, "messages": messages, "max_tokens": maxTokens, "stream": options.stream !== false};
        if (body.stream && options.streamUsage !== false && !_rejectsStreamOptions[_trimSlash(options.baseUrl)])
            body.stream_options = {"include_usage": true};
        // OpenRouter reports the real cost of the request in its usage block.
        if (/^https?:\/\/([^/]*\.)?openrouter\.ai(\/|$)/i.test(String(options.baseUrl || "")))
            body.usage = {"include": true};
    }
    if (tools)
        body.tools = tools;
    // The variant's fragment is merged in, but the request's own fields always win over it. Anthropic
    // wants max_tokens above a thinking budget: the room for the answer is added on top of the budget.
    body = Object.assign({}, options.variantSend || {}, body);
    var budget = body.thinking && body.thinking.type === "enabled" ? Number(body.thinking.budget_tokens) : 0;
    if (budget > 0 && body.max_tokens <= budget) body.max_tokens += budget;
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

// A reply's content is text, or a list of parts (text and images). `images` is chat/ImageExtract.js.
function _contentText(content, images) {
    return typeof content === "string" ? content : (images ? images.textOf(content) : JSON.stringify(content));
}

// {type: "images", items} for the images a message or delta carries (message.images, image parts).
function _emitImages(message, images, emit) {
    var items = images ? images.fromMessage(message) : [];
    if (items.length > 0)
        emit({"type": "images", "items": items});
}

// Turns one parsed streaming JSON message into events. Returns false if the
// message signals the end of the stream.
function _handleStreamMessage(type, sse, think, emit, collector, images) {
    if (sse.data === "[DONE]")
        return false;
    var obj;
    try {
        obj = JSON.parse(sse.data);
    } catch (e) {
        return true;
    }
    if (collector)
        collector.stream(obj);
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
        if (delta.content) think.push(_contentText(delta.content, images));
        _emitImages(delta, images, emit);
    }
    if (obj.usage)
        emit(_openAiUsage(obj.usage));
    return true;
}

// Events for a complete (non-streaming) JSON response.
function _handleFullResponse(type, obj, think, emit, collector, images) {
    if (collector) collector.full(obj);
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
    if (message.content) think.push(_contentText(message.content, images));
    _emitImages(message, images, emit);
    if (obj.usage) emit(_openAiUsage(obj.usage));
}


// Sends one request. options as for buildRequest, plus:
//   xhrFactory()  returns a new XMLHttpRequest;  thinkFactory(emit)  DirectStream.createThinkSplitter
//   collector     optional, DirectTools.createCollector: reports the model's tool calls
//   timeoutMs     0 = no timeout
//   onEvent(event)
// Returns {abort()}.
function send(options) {
    var request = buildRequest(options);
    var stream = request.body.stream;
    var xhr;
    var finished = false, offset = 0, retries = 0;
    // OpenAI-style servers may repeat usage in several chunks (cumulative, or
    // only the last one counts): keep the latest and report it once, at the end.
    var usage = null;

    function emit(event) {
        if (!finished)
            options.onEvent(event);
    }
    var think = options.thinkFactory(function(kind, text) {
        emit({"type": kind === "text" ? "text_delta" : "reasoning_delta", "delta": text});
    });
    function finish(reason, message, status) {
        if (finished) return;
        think.end();
        if (reason === "complete" && usage)
            emit(usage);
        if (reason === "complete" && options.collector && options.collector.calls().length > 0)
            emit({"type": "tool_calls", "calls": options.collector.calls(), "thinking": options.collector.thinkingBlocks()});
        if (reason === "error")
            emit({"type": "error", "message": message, "status": status || 0});
        emit({"type": "done", "reason": reason});
        finished = true;
    }
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
            }, options.collector, options.images);
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
                var why = retries < 2 ? _retryReason(xhr.status, xhr.responseText || "", request.body) : "";
                if (why) {
                    if (why === "tools") _rejectsToolsFor[_toolsKey(options)] = true;
                    else _rejectsStreamOptions[_trimSlash(options.baseUrl)] = true;
                    retries++;
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
                    _handleFullResponse(options.type, JSON.parse(xhr.responseText), think, emit, options.collector, options.images);
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
