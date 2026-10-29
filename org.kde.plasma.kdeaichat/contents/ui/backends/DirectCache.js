.pragma library

// Prompt-cache hints for direct requests (see docs/plan/09-prompt-caching.md).
// DirectBackend.buildRequest takes this module as options.cache and calls apply() on the
// finished body. Nothing is added unless the provider is known to accept it:
//   Anthropic API: cache_control breakpoints on the last tool, the system prompt and the
//     last message before the new turn (cache order is tools, system, messages; 3 of the 4 allowed).
//   OpenRouter with an anthropic/ model: the same marks as content parts on the system
//     message and that message.
//   Every other server (OpenAI, Ollama, LM Studio, llama.cpp, vLLM, ...): untouched.
// Plain JavaScript (tested with node): no QML globals, no .import. Never changes its input.

var MARK = {"type": "ephemeral"};

function isOpenRouter(baseUrl) {
    return /^https?:\/\/([^/]*\.)?openrouter\.ai(\/|$)/i.test(String(baseUrl || ""));
}

function _isToolResultTurn(message) {
    return message.role === "user" && Array.isArray(message.content) && message.content.length > 0
        && message.content.every(function(part) { return part && part.type === "tool_result"; });
}

// Index of the message that gets the breakpoint: the one before the new user turn, or, while
// the model is working through tool calls (the last message is the tool results), that last one.
function targetIndex(messages) {
    var last = messages.length - 1;
    if (last < 0)
        return -1;
    var m = messages[last];
    if (m.role === "user")
        return _isToolResultTurn(m) ? last : last - 1;
    return -1;
}

// `content` with the mark on its last block, or null when it can't carry one (empty text,
// thinking blocks). A string becomes a one-block list.
function _marked(content, allowed) {
    if (typeof content === "string")
        return content === "" ? null : [{"type": "text", "text": content, "cache_control": MARK}];
    if (!Array.isArray(content) || content.length === 0)
        return null;
    var at = content.length - 1, part = content[at];
    if (!part || typeof part !== "object" || allowed.indexOf(part.type) < 0)
        return null;
    var copy = content.slice();
    copy[at] = Object.assign({}, part, {"cache_control": MARK});
    return copy;
}

function _markMessage(messages, index, allowed, roles) {
    if (index < 0 || roles.indexOf(messages[index].role) < 0)
        return messages;
    var content = _marked(messages[index].content, allowed);
    if (!content)
        return messages;
    var copy = messages.slice();
    copy[index] = Object.assign({}, messages[index], {"content": content});
    return copy;
}

// Returns body with the marks the provider accepts. options: {type, baseUrl, model}.
function apply(body, options) {
    var anthropic = options.type === "anthropic";
    var routed = !anthropic && isOpenRouter(options.baseUrl) && /^anthropic\//i.test(String(options.model || ""));
    if (!anthropic && !routed)
        return body;
    var out = Object.assign({}, body);
    if (anthropic) {
        var blocks = ["text", "image", "document", "tool_use", "tool_result"];
        if (out.tools && out.tools.length > 0)
            out.tools = out.tools.slice(0, -1).concat([Object.assign({}, out.tools[out.tools.length - 1], {"cache_control": MARK})]);
        if (typeof out.system === "string" && out.system !== "")
            out.system = _marked(out.system, blocks);
        out.messages = _markMessage(out.messages, targetIndex(out.messages), blocks, ["user", "assistant"]);
        return out;
    }
    var all = out.messages;
    var offset = all.length > 0 && all[0].role === "system" ? 1 : 0;
    all = _markMessage(all, offset - 1, ["text"], ["system"]);
    var index = targetIndex(all);
    out.messages = index >= offset ? _markMessage(all, index, ["text"], ["user", "assistant"]) : all;
    return out;
}
