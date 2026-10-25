.pragma library

// Chat names. instantTitle() makes a short name from the first message the
// moment it is sent; request() asks the chat's model for a better one after
// the first reply and parses it defensively (reasoning/empty output is ignored).
//
// Plain JavaScript on purpose (tested with node): no QML globals, no .import.
// request() takes an XMLHttpRequest factory so tests can fake the network.

var DEFAULT_TITLE = "New Chat";
var MAX_WORDS = 6;
var MAX_CHARS = 40;

function isDefaultTitle(title) {
    var t = String(title || "").trim().toLowerCase();
    return t === "" || t === "new chat";
}

// Text with Markdown, code fences, URLs and extra whitespace removed.
function _plain(text) {
    return String(text || "")
        .replace(/```[\s\S]*?(```|$)/g, " ")
        .replace(/`([^`]*)`/g, "$1")
        .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
        .replace(/<[^>\s][^>]*>/g, " ")
        .replace(/(https?|ftp):\/\/\S+|www\.\S+/gi, " ")
        .replace(/^\s{0,3}(#{1,6}|>+|[-*+]|\d+[.)])\s+/gm, "")
        .replace(/[*_~#>|]+/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

// First ~6 words / ~40 characters of a message, "…" when cut; "" if nothing usable.
function instantTitle(text) {
    var plain = _plain(text);
    if (!plain)
        return "";
    var words = plain.split(" ");
    var out = [];
    var length = 0;
    var cut = false;
    for (var i = 0; i < words.length; i++) {
        var next = length + (out.length ? 1 : 0) + words[i].length;
        if (out.length >= MAX_WORDS || (out.length > 0 && next > MAX_CHARS)) {
            cut = true;
            break;
        }
        out.push(words[i]);
        length = next;
    }
    var title = out.join(" ");
    if (title.length > MAX_CHARS) {
        title = title.substring(0, MAX_CHARS - 1);
        cut = true;
    }
    title = title.replace(/[\s.,;:!?\-–—]+$/, "");
    if (!title)
        return "";
    if (title.length > 0)
        title = title.charAt(0).toUpperCase() + title.substring(1);
    return cut ? title + "…" : title;
}

// A model's answer cleaned into a title, or "" when it can't be used
// (empty, or an unfinished <think> block).
function cleanGenerated(value) {
    var title = String(value || "");
    title = title.replace(/<(think|thinking|reasoning)>[\s\S]*?<\/\1>/gi, "");
    if (/<(think|thinking|reasoning)>/i.test(title))
        return "";
    title = title.replace(/```[\s\S]*?```/g, "").trim();
    title = title.replace(/^\s*(title\s*:\s*)/i, "").split("\n")[0];
    title = title.replace(/^['"`*#\s]+|['"`*\s]+$/g, "").replace(/\s+/g, " ").replace(/[.!?]+$/, "").trim();
    if (title.length > 80)
        title = title.substring(0, 77).replace(/\s+\S*$/, "") + "…";
    return title;
}

function _textOf(content) {
    if (typeof content === "string")
        return content;
    if (!Array.isArray(content))
        return "";
    var parts = [];
    for (var i = 0; i < content.length; i++)
        if (content[i] && content[i].type === "text" && typeof content[i].text === "string")
            parts.push(content[i].text);
    return parts.join("");
}

// The title in a response body (JSON text) of the chat/completions or messages API.
function parseResponse(isAnthropic, responseText) {
    var response = JSON.parse(responseText);
    var raw = isAnthropic ? _textOf(response.content) : _textOf((((response.choices || [])[0] || {}).message || {}).content);
    return cleanGenerated(raw);
}

// The request to name a chat: {url, headers, body}.
function buildRequest(cfg, firstUserText) {
    var isAnthropic = cfg.type === "anthropic";
    var url = String(cfg.baseUrl).replace(/\/$/, "");
    if (isAnthropic) {
        if (!/\/messages$/.test(url)) url += "/messages";
    } else {
        url += "/chat/completions";
    }
    var headers = {"Content-Type": "application/json"};
    if (isAnthropic) {
        headers["x-api-key"] = cfg.apiKey;
        headers["anthropic-version"] = "2023-06-01";
    } else if (cfg.apiKey) {
        headers["Authorization"] = "Bearer " + cfg.apiKey;
    }
    for (var name in (cfg.headers || {}))
        if (Object.prototype.hasOwnProperty.call(cfg.headers, name) && cfg.headers[name])
            headers[name] = cfg.headers[name];
    var prompt = "Create a concise 3-6 word title for this conversation. Return only the title, no quotes or punctuation.\n\nUser message:\n"
        + String(firstUserText).substring(0, 1200);
    var body = isAnthropic
        ? {"model": cfg.model, "max_tokens": 32, "messages": [{"role": "user", "content": prompt}]}
        : {"model": cfg.model, "stream": false, "max_tokens": 40,
           "messages": [{"role": "system", "content": "You name chats concisely."}, {"role": "user", "content": prompt}]};
    return {"url": url, "headers": headers, "body": body, "isAnthropic": isAnthropic};
}

// Asks the model for a title. done(title, error): title "" and a short error
// text (never the key) when it failed or the answer was unusable.
function request(cfg, firstUserText, xhrFactory, done) {
    var finished = false;
    function finish(title, error) {
        if (finished) return;
        finished = true;
        done(title, error);
    }
    try {
        var req = buildRequest(cfg, firstUserText);
        var xhr = xhrFactory();
        xhr.timeout = 20000;
        xhr.ontimeout = function() { finish("", "timed out"); };
        xhr.onerror = function() { finish("", "network error"); };
        xhr.open("POST", req.url, true);
        for (var name in req.headers)
            xhr.setRequestHeader(name, req.headers[name]);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4) return;
            if (xhr.status < 200 || xhr.status >= 300)
                return finish("", "HTTP " + xhr.status);
            try {
                if (String(xhr.responseText).length > 1000000)
                    return finish("", "response too large");
                var title = parseResponse(req.isAnthropic, xhr.responseText);
                finish(title, title ? "" : "no usable title in the answer");
            } catch (e) {
                finish("", "unreadable answer");
            }
        };
        xhr.send(JSON.stringify(req.body));
    } catch (e) {
        finish("", "request failed: " + e);
    }
}
