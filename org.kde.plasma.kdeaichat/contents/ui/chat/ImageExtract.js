.pragma library

// Finding images in a chat model's reply (plain JavaScript, tested in node).
//
// An item is {kind: "data", b64, mime} (base64 text, no "data:" prefix) or
// {kind: "url", url} (an https link the helper fetches when the user asks).
// Nothing here fetches or saves anything: the widget passes items to
// chat/ImageStore.qml, which has the helper check and store them as files.
//
// Shapes understood:
//   OpenRouter   message.images / delta.images = [{type:"image_url", image_url:{url}}]
//   OpenAI-style content parts   {type:"image_url"|"output_image"|"input_image", image_url: "..." | {url}}
//                                {b64_json}, {image_base64}, {type:"image", source:{type:"base64", data, media_type}}
//   Gemini-style   {inlineData:{mimeType, data}}
//   Markdown       ![alt](https://...) or ![alt](data:image/png;base64,...) in the reply's text

var MAX_ITEMS = 8;
var MAX_B64_CHARS = 17000000;     // about 12 MB of image (the helper's cap)
var MAX_ALT_CHARS = 200;

function _mime(text) {
    var m = /^image\/(png|jpeg|jpg|webp|gif)$/i.exec(String(text || ""));
    return m ? "image/" + (m[1].toLowerCase() === "jpg" ? "jpeg" : m[1].toLowerCase()) : "";
}

// {mime, b64} for a data:image/...;base64,... link, or null.
function parseDataUrl(url) {
    var s = String(url || "");
    if (s.substring(0, 11).toLowerCase() !== "data:image/")
        return null;
    var comma = s.indexOf(",");
    if (comma < 0 || comma > 80)
        return null;
    var head = s.substring(5, comma).split(";");
    var mime = _mime(head[0]);
    var b64 = s.substring(comma + 1).replace(/\s+/g, "");
    if (!mime || head.indexOf("base64") < 0 || b64 === "" || b64.length > MAX_B64_CHARS || !/^[A-Za-z0-9+\/]+={0,2}$/.test(b64))
        return null;
    return {"mime": mime, "b64": b64};
}

// An item for one link (data: or https), or null.
function itemFromUrl(url) {
    var data = parseDataUrl(url);
    if (data)
        return {"kind": "data", "b64": data.b64, "mime": data.mime};
    var s = String(url || "").trim();
    return /^https:\/\//i.test(s) && s.length <= 2048 ? {"kind": "url", "url": s} : null;
}

function _itemFromBase64(b64, mime) {
    var s = String(b64 || "").replace(/\s+/g, "");
    if (s === "" || s.length > MAX_B64_CHARS || !/^[A-Za-z0-9+\/]+={0,2}$/.test(s))
        return null;
    return {"kind": "data", "b64": s, "mime": _mime(mime) || "image/png"};
}

// An item for one part of a message ({type:"image_url", ...} and the other shapes), or null.
function itemFromPart(part) {
    if (!part)
        return null;
    if (typeof part === "string")
        return itemFromUrl(part);
    if (typeof part !== "object")
        return null;
    var link = part.image_url !== undefined ? part.image_url : (part.url !== undefined ? part.url : null);
    if (link && typeof link === "object")
        link = link.url;
    if (typeof link === "string" && link !== "")
        return itemFromUrl(link);
    if (part.b64_json || part.image_base64)
        return _itemFromBase64(part.b64_json || part.image_base64, part.media_type || part.mime_type || part.mimeType);
    var inline = part.inlineData || part.inline_data;
    if (inline && inline.data)
        return _itemFromBase64(inline.data, inline.mimeType || inline.mime_type);
    if (part.source && part.source.type === "base64")
        return _itemFromBase64(part.source.data, part.source.media_type);
    return null;
}

// A short key to tell images apart (the same image may arrive twice in a stream).
function itemKey(item) {
    if (item.kind === "url")
        return "u:" + item.url;
    var b = item.b64;
    return "d:" + b.length + ":" + b.substring(0, 48) + b.substring(b.length - 48);
}

// The images of a message or a streamed delta (see the shapes above). Duplicates are dropped.
function fromMessage(message) {
    var items = [];
    var seen = {};
    function add(item) {
        if (item && items.length < MAX_ITEMS && !seen[itemKey(item)]) {
            seen[itemKey(item)] = true;
            items.push(item);
        }
    }
    if (!message || typeof message !== "object")
        return items;
    if (Array.isArray(message.images)) {
        for (var i = 0; i < message.images.length; i++)
            add(itemFromPart(message.images[i]));
    }
    if (Array.isArray(message.content)) {
        for (var j = 0; j < message.content.length; j++) {
            var part = message.content[j];
            if (part && typeof part === "object" && part.type !== "text" && part.type !== "output_text")
                add(itemFromPart(part));
        }
    }
    return items;
}

// The text of a message's content, which is a string or a list of parts.
function textOf(content) {
    if (typeof content === "string")
        return content;
    if (!Array.isArray(content))
        return content === undefined || content === null ? "" : JSON.stringify(content);
    var out = "";
    for (var i = 0; i < content.length; i++) {
        var p = content[i];
        if (typeof p === "string")
            out += p;
        else if (p && (p.type === "text" || p.type === "output_text") && p.text)
            out += String(p.text);
    }
    return out;
}

// Markdown image links in `text`. Returns
//   {text, data: [item], links: [{alt, url}]}
// `text` has every image link replaced by "[image: alt]" so the chat view never loads one by itself;
// data: images are in `data` (to be saved as files); https links are in `links` (the user clicks to load
// them). Links that are neither (http:, file:, ...), or that `accept(url)` refuses, are only dropped from the text.
function extractMarkdown(text, accept) {
    var source = String(text === undefined || text === null ? "" : text);
    var result = {"text": source, "data": [], "links": []};
    if (source.indexOf("![") < 0)
        return result;
    var pattern = /!\[([^\]\n]{0,300})\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/g;
    var seen = {};
    result.text = source.replace(pattern, function(whole, alt, url) {
        var label = String(alt || "").replace(/[\[\]\r\n]/g, " ").trim().substring(0, MAX_ALT_CHARS);
        var item = itemFromUrl(url);
        if (item && item.kind === "data") {
            if (result.data.length < MAX_ITEMS)
                result.data.push(item);
        } else if (item && item.kind === "url" && (!accept || accept(item.url)) && !seen[item.url] && result.links.length < MAX_ITEMS) {
            seen[item.url] = true;
            result.links.push({"alt": label, "url": item.url});
        }
        return label !== "" ? "[image: " + label + "]" : "[image]";
    });
    return result;
}

var _CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Base64 text of bytes (an array-like of numbers, e.g. a Uint8Array from an XHR arraybuffer).
function bytesToBase64(bytes) {
    var out = [];
    var n = bytes.length;
    for (var i = 0; i < n; i += 3) {
        var a = bytes[i], b = i + 1 < n ? bytes[i + 1] : 0, c = i + 2 < n ? bytes[i + 2] : 0;
        var chunk = _CHARS.charAt(a >> 2) + _CHARS.charAt(((a & 3) << 4) | (b >> 4))
            + (i + 1 < n ? _CHARS.charAt(((b & 15) << 2) | (c >> 6)) : "=") + (i + 2 < n ? _CHARS.charAt(c & 63) : "=");
        out.push(chunk);
        if (out.length >= 8192) out = [out.join("")];
    }
    return out.join("");
}
