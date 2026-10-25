.pragma library

// Splits a message into text and fenced-code blocks for the chat view:
//   [{type: "text", text}, {type: "code", language, text}, ...]
// An unclosed fence (a reply still streaming) counts as code to the end.

function split(content) {
    if (!content)
        return [];
    var blocks = [];
    var parts = String(content).split("```");
    for (var i = 0; i < parts.length; i++) {
        var part = parts[i];
        if (i % 2 === 0) {
            if (part.length > 0 || parts.length === 1)
                blocks.push({"type": "text", "text": part});
            continue;
        }
        var language = "code";
        var code = part;
        var newline = part.indexOf("\n");
        if (newline !== -1) {
            var tag = part.substring(0, newline).trim();
            if (/^[a-zA-Z0-9+#-]+$/.test(tag) && tag.length < 15) {
                language = tag;
                code = part.substring(newline + 1);
            } else if (tag === "") {
                code = part.substring(newline + 1);
            }
        }
        if (code.charAt(code.length - 1) === "\n")
            code = code.substring(0, code.length - 1);
        blocks.push({"type": "code", "language": language, "text": code});
    }
    return blocks;
}

// A reply that is still streaming is shown as plain text, so Markdown
// markers would show up as they are. This hides the simple ones (**bold**,
// *italic*, "## " heading marks, a trailing lone "*" that may become "**")
// without trying to be a Markdown parser; the finished reply is rendered
// properly.
function stripEmphasis(text) {
    if (!text)
        return "";
    return String(text)
        .replace(/\*\*/g, "")
        .replace(/(^|[\s(\["'])\*([^\s*][^*\n]*?)\*(?=$|[\s).,;:!?\]"'])/g, "$1$2")
        .replace(/^#{1,6}[ \t]+/gm, "")
        .replace(/([^\s*])\*$/, "$1");
}
