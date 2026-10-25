.pragma library

// Tool calling for direct mode: the tool definitions, collecting a model's
// tool calls from a streamed (or complete) reply, and the messages that carry
// a tool call and its result back to the provider, in OpenAI or Anthropic
// format. Plain JavaScript on plain objects, so tests run it in node.
//
// A chat stores a tool-using reply as one assistant message with
//   toolRounds: [{text, calls: [{id, name, args}]}]   one entry per model turn that called tools
//   tools:      {callId: {name, detail, status, input, output}}   (backends/AgentEvents.js)
// and historyMessages() turns that back into valid provider messages.

var ASK_USER = "ask_user";
var MAX_ROUNDS = 8;
var NO_RESULT = "No result: the request was stopped before the tool finished.";

var ASK_USER_DESCRIPTION = "Ask the user a question and wait for the answer. Use it when you need a decision or a missing detail "
    + "that you can't work out yourself. The answer is returned as the result. Give short options when the answers are few.";

// options: {askUser: bool}. [] when no tool is offered.
function toolDefinitions(type, options) {
    var defs = [];
    if (options && options.askUser) {
        var schema = {
            "type": "object",
            "properties": {
                "question": {"type": "string", "description": "The question to show the user."},
                "options": {"type": "array", "items": {"type": "string"}, "description": "Answers the user can tap. Optional."},
                "allow_typed": {"type": "boolean", "description": "Let the user type their own answer. Default true."}
            },
            "required": ["question"]
        };
        defs.push(type === "anthropic" ? {"name": ASK_USER, "description": ASK_USER_DESCRIPTION, "input_schema": schema}
                                       : {"type": "function", "function": {"name": ASK_USER, "description": ASK_USER_DESCRIPTION, "parameters": schema}});
    }
    return defs;
}

function parseArgs(raw) {
    if (raw && typeof raw === "object")
        return raw;
    try {
        var value = JSON.parse(String(raw || "") || "{}");
        return value && typeof value === "object" && !Array.isArray(value) ? value : {};
    } catch (e) {
        return {};
    }
}

// What ask_user was asked, made safe: {question, options: [string], allowTyped}.
function askUserQuestion(args) {
    args = args || {};
    var options = [];
    var given = Array.isArray(args.options) ? args.options : [];
    for (var i = 0; i < given.length && options.length < 12; i++) {
        var label = String(given[i] && typeof given[i] === "object" ? (given[i].label || given[i].text || "") : given[i]).trim();
        if (label && options.indexOf(label) < 0)
            options.push(label.substring(0, 200));
    }
    var typed = args.allow_typed !== false && args.allow_typed !== "false";
    return {"question": String(args.question || "").trim().substring(0, 2000), "options": options, "allowTyped": typed || options.length === 0};
}

// --- Collecting tool calls from a reply ---------------------------------------

// Fed every parsed streaming message (stream) or the complete response (full).
// calls() are the tool calls, [{id, name, args}]; thinkingBlocks() are the Anthropic
// thinking blocks, which a reply that continues after a tool call must carry back.
function createCollector(type) {
    var anth = type === "anthropic";
    var blocks = {};       // Anthropic: content block index -> block
    var order = [];        // OpenAI: tool calls in order
    var byKey = {};

    function openAiCall(tc, position) {
        var key = tc.index !== undefined && tc.index !== null ? tc.index : (tc.id ? "id:" + tc.id : "pos:" + position);
        if ((tc.index === undefined || tc.index === null) && !tc.id && order.length > 0)
            key = order[order.length - 1].key;   // a bare continuation of the last call
        var call = byKey[key];
        if (!call) {
            call = {"key": key, "id": "", "name": "", "raw": ""};
            byKey[key] = call;
            order.push(call);
        }
        if (tc.id) call.id = String(tc.id);
        var fn = tc["function"] || {};
        if (fn.name && !call.name) call.name = String(fn.name);
        if (fn.arguments !== undefined && fn.arguments !== null)
            call.raw += typeof fn.arguments === "string" ? fn.arguments : JSON.stringify(fn.arguments);
    }

    function stream(obj) {
        if (anth) {
            if (obj.type === "content_block_start" && obj.content_block) {
                var b = Object.assign({}, obj.content_block);
                if (b.type === "tool_use") { b.raw = ""; delete b.input; }
                if (b.type === "thinking") { b.thinking = b.thinking || ""; b.signature = b.signature || ""; }
                blocks[obj.index] = b;
            } else if (obj.type === "content_block_delta" && obj.delta && blocks[obj.index]) {
                var d = obj.delta, cur = blocks[obj.index];
                if (d.type === "input_json_delta") cur.raw = (cur.raw || "") + (d.partial_json || "");
                else if (d.type === "thinking_delta") cur.thinking += d.thinking || "";
                else if (d.type === "signature_delta") cur.signature = d.signature || "";
            }
            return;
        }
        var choice = obj.choices && obj.choices[0];
        var list = choice && choice.delta && choice.delta.tool_calls;
        for (var i = 0; list && i < list.length; i++)
            openAiCall(list[i] || {}, i);
    }

    function full(obj) {
        var i;
        if (anth) {
            var content = obj.content || [];
            for (i = 0; i < content.length; i++) {
                var b = Object.assign({}, content[i]);
                if (b.type === "tool_use") { b.raw = JSON.stringify(b.input || {}); delete b.input; }
                blocks[i] = b;
            }
            return;
        }
        var message = (obj.choices && obj.choices[0] && obj.choices[0].message) || {};
        var list = message.tool_calls || [];
        for (i = 0; i < list.length; i++)
            openAiCall(Object.assign({"index": i}, list[i]), i);
    }

    function sortedBlockKeys() {
        return Object.keys(blocks).map(Number).sort(function(a, b) { return a - b; });
    }

    function calls() {
        var out = [], i;
        if (anth) {
            var keys = sortedBlockKeys();
            for (i = 0; i < keys.length; i++) {
                var b = blocks[keys[i]];
                if (b.type === "tool_use" && b.name)
                    out.push({"id": String(b.id || "toolu_" + keys[i]), "name": String(b.name), "args": parseArgs(b.raw)});
            }
            return out;
        }
        for (i = 0; i < order.length; i++)
            if (order[i].name)
                out.push({"id": order[i].id || "call_" + i, "name": order[i].name, "args": parseArgs(order[i].raw)});
        return out;
    }

    function thinkingBlocks() {
        var out = [];
        var keys = sortedBlockKeys();
        for (var i = 0; i < keys.length; i++) {
            var b = blocks[keys[i]];
            if (b.type === "thinking" && b.signature) out.push({"type": "thinking", "thinking": b.thinking, "signature": b.signature});
            else if (b.type === "redacted_thinking") out.push({"type": "redacted_thinking", "data": b.data});
        }
        return out;
    }

    return {"stream": stream, "full": full, "calls": calls, "thinkingBlocks": thinkingBlocks};
}

// --- Messages carrying tool calls and results ---------------------------------

// The model's turn that called tools. thinking: Anthropic thinking blocks of that turn, or [].
function assistantMessage(type, text, calls, thinking) {
    var i;
    if (type === "anthropic") {
        var content = (thinking || []).slice();
        if (String(text || "").trim() !== "")
            content.push({"type": "text", "text": String(text)});
        for (i = 0; i < calls.length; i++)
            content.push({"type": "tool_use", "id": calls[i].id, "name": calls[i].name, "input": calls[i].args || {}});
        return {"role": "assistant", "content": content};
    }
    var wire = [];
    for (i = 0; i < calls.length; i++)
        wire.push({"id": calls[i].id, "type": "function", "function": {"name": calls[i].name, "arguments": JSON.stringify(calls[i].args || {})}});
    return {"role": "assistant", "content": String(text || ""), "tool_calls": wire};
}

// results: [{id, output, isError}] -> the messages that answer the calls.
function resultMessages(type, results) {
    var i;
    if (type === "anthropic") {
        var content = [];
        for (i = 0; i < results.length; i++) {
            var block = {"type": "tool_result", "tool_use_id": results[i].id, "content": String(results[i].output)};
            if (results[i].isError) block.is_error = true;
            content.push(block);
        }
        return [{"role": "user", "content": content}];
    }
    var messages = [];
    for (i = 0; i < results.length; i++)
        messages.push({"role": "tool", "tool_call_id": results[i].id, "content": String(results[i].output)});
    return messages;
}

function _resultsFor(msg, calls) {
    var tools = msg.tools || {};
    return calls.map(function(call) {
        var tool = tools[call.id] || {};
        var output = tool.output !== undefined && tool.output !== "" ? String(tool.output) : NO_RESULT;
        return {"id": call.id, "output": output, "isError": tool.status === "error"};
    });
}

// One line per tool call, for a provider that can't take tool messages.
function toolSummary(msg) {
    var lines = [];
    var rounds = msg.toolRounds || [];
    for (var r = 0; r < rounds.length; r++) {
        for (var c = 0; c < rounds[r].calls.length; c++) {
            var call = rounds[r].calls[c];
            var tool = (msg.tools || {})[call.id] || {};
            var what = call.name === ASK_USER ? "asked \"" + String((call.args || {}).question || "") + "\"" : "used the " + call.name + " tool";
            lines.push("[" + what + (tool.output ? ": " + String(tool.output).substring(0, 500) : "") + "]");
        }
    }
    return lines.join("\n");
}

// The text of a stored reply after the text of its tool rounds, or null when the
// stored text doesn't start with theirs (it was edited): then it can't be rebuilt.
function _textAfterRounds(msg) {
    var texts = [];
    var rounds = msg.toolRounds || [];
    for (var i = 0; i < rounds.length; i++)
        if (String(rounds[i].text || "") !== "") texts.push(String(rounds[i].text));
    var prefix = texts.join("\n\n");
    var content = String(msg.content || "");
    if (content.indexOf(prefix) !== 0)
        return null;
    return content.substring(prefix.length).replace(/^\n+/, "");
}

// A stored assistant message as provider messages. withTools false (the model
// takes no tools), or a message that can't be rebuilt, gives plain text.
function historyMessages(type, msg, withTools) {
    var rounds = msg.toolRounds || [];
    var text = String(msg.content || "");
    var rest = rounds.length > 0 && withTools ? _textAfterRounds(msg) : null;
    if (rounds.length === 0 || rest === null) {
        if (rounds.length > 0) {
            var summary = toolSummary(msg);
            text = (summary ? summary + "\n\n" : "") + text;
        }
        return text.trim() === "" ? [] : [{"role": "assistant", "content": text}];
    }
    var out = [];
    for (var i = 0; i < rounds.length; i++) {
        out.push(assistantMessage(type, rounds[i].text, rounds[i].calls, []));
        out = out.concat(resultMessages(type, _resultsFor(msg, rounds[i].calls)));
    }
    if (rest.trim() !== "")
        out.push({"role": "assistant", "content": rest});
    return out;
}

function hasToolRounds(messages) {
    for (var i = 0; i < messages.length; i++)
        if (messages[i].toolRounds && messages[i].toolRounds.length > 0)
            return true;
    return false;
}
