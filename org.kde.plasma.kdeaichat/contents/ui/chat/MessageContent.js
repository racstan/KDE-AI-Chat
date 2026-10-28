.pragma library
// A user message as request content: quoted messages and text files are put in
// front of the text; images become image parts in the API's format
// ("anthropic" or OpenAI-style). Without images the result is a string, and
// without attachments and quotes it is the text itself.
//
// Quotes (Discord-style "quote this message"): a message keeps them as
// structured data, quotes = [{id, role, text}] (id: the quoted message's id,
// role: "user" or "assistant", text: what was quoted, at most MAX_QUOTE_CHARS
// characters, cut with "…"). Every mode builds its user message through
// build(), so the AI gets the same context everywhere:
//
//   > Quoted (assistant):
//   > first line
//   > second line
//
//   (the new message)

var MAX_QUOTE_CHARS = 4000;
var MAX_QUOTES = 10;

// "assistant" for a reply, "user" for your own messages (also queued ones).
function quoteRole(role) {
    return role === "assistant" || role === "opencode_assistant" ? "assistant" : "user";
}

// Whether a message can be quoted: yours or an answer, with some text.
function canQuote(message) {
    var role = String((message || {}).role || "");
    return (role === "user" || role === "queued" || role === "assistant" || role === "opencode_assistant")
        && String(message.content || "").trim() !== "";
}

function capQuote(text) {
    var t = String(text === undefined || text === null ? "" : text).replace(/\r\n?/g, "\n").trim();
    return t.length > MAX_QUOTE_CHARS ? t.substring(0, MAX_QUOTE_CHARS) + "…" : t;
}

// The quote for a message, or null when there is nothing to quote.
function makeQuote(message) {
    if (!canQuote(message))
        return null;
    return {"id": String(message.id === undefined || message.id === null ? "" : message.id),
            "role": quoteRole(message.role), "text": capQuote(message.content)};
}

// The first non-empty line, for a chip.
function quoteFirstLine(text) {
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/\s+/g, " ").trim();
        if (line !== "")
            return line;
    }
    return "";
}

// The quotes as the text that goes in front of the message ("" without quotes).
function quoteContext(quotes) {
    var blocks = [];
    var list = quotes || [];
    for (var i = 0; i < list.length && blocks.length < MAX_QUOTES; i++) {
        var q = list[i] || {};
        var text = capQuote(q.text);
        if (text === "")
            continue;
        blocks.push("> Quoted (" + quoteRole(q.role) + "):\n"
                    + text.split("\n").map(function(l) { return l === "" ? ">" : "> " + l; }).join("\n"));
    }
    return blocks.length > 0 ? blocks.join("\n\n") + "\n\n" : "";
}

// Agent modes (Pi, OpenCode) have file tools: a document is not pasted into
// the message, it is named by its path ("Attached file: <path>") and the agent
// reads what it needs. Images are still sent inline. Direct mode has no file
// tools, so it pastes the extracted text.
function isAgentMode(mode) {
    return mode === "pi" || mode === "opencode";
}

// Extracted text above this many characters gets a warning in direct mode.
var LARGE_FILE_CHARS = 100000;

function isLargeFile(att) {
    return !!att && att.type === "text" && String(att.content || "").length > LARGE_FILE_CHARS;
}

// The line that tells an agent where an attached file is ("" without a path).
// Line breaks in the path are dropped so a name can't add instructions.
function pathLine(att) {
    var path = String((att || {}).path || "").replace(/[\r\n\u2028\u2029]+/g, " ").trim();
    return path === "" ? "" : "Attached file: " + path + "\n";
}

// `quotes` is optional; `agent` (true in Pi and OpenCode chats) sends paths, not text.
function build(text, attachments, apiType, quotes, agent) {
    attachments = attachments || [];
    var docs = [];
    var imgs = [];
    var skippedImageCount = 0;
    var imageChars = 0;
    var paths = "";
    for (var i = 0; i < attachments.length; i++) {
        var att = attachments[i] || {};
        if (att.type === "image") {
            var imageSize = String(att.content || "").length;
            if (imageChars + imageSize <= 20000000) {
                imgs.push(att);
                imageChars += imageSize;
            } else {
                skippedImageCount++;
            }
        } else if (agent) {
            paths += pathLine(att);
        } else if (att.type === "text")
            docs.push(att);
    }
    var compiledPrompt = skippedImageCount > 0
        ? "[" + skippedImageCount + " image attachment(s) omitted because the request image limit was reached.]\n"
        : "";
    for (var d = 0; d < docs.length; d++) {
        if (compiledPrompt.length > 5000000)
            break;
        compiledPrompt += "[Attached File: " + String(docs[d].name || "file") + " (" + Math.round((docs[d].size || 0) / 1024) + " KB)]\n";
        compiledPrompt += "--- START OF FILE CONTENT ---\n";
        var remainingDocChars = Math.max(0, 5000000 - compiledPrompt.length - 40);
        var docContent = String(docs[d].content || "");
        if (docContent.length > remainingDocChars)
            docContent = docContent.substring(0, remainingDocChars) + "\n[file content truncated]";
        compiledPrompt += docContent + "\n";
        compiledPrompt += "--- END OF FILE CONTENT ---\n\n";
    }
    if (paths !== "")
        compiledPrompt += paths + "\n";
    compiledPrompt += quoteContext(quotes) + text;
    if (imgs.length === 0)
        return compiledPrompt;

    var contentList = [];
    if (compiledPrompt.trim() !== "")
        contentList.push({
            "type": "text",
            "text": compiledPrompt
        });

    for (var imgIdx = 0; imgIdx < imgs.length; imgIdx++) {
        var image = imgs[imgIdx];
        if (apiType === "anthropic")
            contentList.push({
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": image.mimeType || "image/jpeg",
                    "data": image.content
                }
            });
        else
            contentList.push({
                "type": "image_url",
                "image_url": {
                    "url": "data:" + (image.mimeType || "image/jpeg") + ";base64," + image.content
                }
            });
    }
    return contentList;
}
