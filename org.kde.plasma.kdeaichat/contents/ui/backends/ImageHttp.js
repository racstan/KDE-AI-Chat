.pragma library

// The HTTP side shared by the image services (HordeBackend.js, PollinationsBackend.js).
// Self-contained (no QML globals, no imports): tests run it in node with a fake XMLHttpRequest.

var MAX_IMAGE_BYTES = 12 * 1024 * 1024;

// The first characters of a binary response read as text (an error message), or "".
function asciiOf(buffer) {
    var bytes = buffer ? new Uint8Array(buffer) : null;
    var out = "";
    for (var i = 0; bytes && i < Math.min(bytes.length, 1000); i++)
        out += bytes[i] < 128 ? String.fromCharCode(bytes[i]) : "?";
    return out;
}

// Sends one request. options: {xhrFactory, method, url, headers, body, binary, timeoutMs}.
// cb({status, text, buffer, header(name)}) once: status 0 means the server could not be reached
// (or the time ran out). `binary` reads the body as bytes (buffer), otherwise as text.
// Returns {abort()}; after abort the callback is not called.
function request(options, cb) {
    var xhr = options.xhrFactory();
    var finished = false;
    function finish(status) {
        if (finished)
            return;
        finished = true;
        var text = "";
        var buffer = null;
        try {
            if (!options.binary)
                text = String(xhr.responseText || "");
            else if (status >= 200 && status < 300)
                buffer = xhr.response;
            else
                text = asciiOf(xhr.response);   // an error body, read as text
        } catch (e) {
            text = "";
        }
        cb({"status": status, "text": text, "buffer": buffer, "header": function(name) {
            try { return xhr.getResponseHeader(name) || ""; } catch (e) { return ""; }
        }});
    }
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4)
            finish(Number(xhr.status) || 0);
    };
    xhr.onerror = function() { finish(0); };
    xhr.ontimeout = function() { finish(0); };
    try {
        xhr.open(options.method || "GET", options.url, true);
        if (options.binary)
            xhr.responseType = "arraybuffer";
        if (options.timeoutMs > 0)
            xhr.timeout = options.timeoutMs;
        var headers = options.headers || {};
        for (var name in headers) {
            if (Object.prototype.hasOwnProperty.call(headers, name) && headers[name] !== "")
                xhr.setRequestHeader(name, String(headers[name]));
        }
        xhr.send(options.body === undefined || options.body === null ? null : options.body);
    } catch (e) {
        finish(0);
    }
    return {"abort": function() {
        if (finished)
            return;
        finished = true;
        try { xhr.abort(); } catch (e) {}
    }};
}

// The bytes of a response as a Uint8Array-like (an ArrayBuffer from an XHR), or null.
function bytesOf(buffer) {
    if (!buffer)
        return null;
    try {
        return new Uint8Array(buffer);
    } catch (e) {
        return null;
    }
}

// Seconds from a Retry-After header: a number of seconds, or an HTTP date. 0 when absent or unusable.
function retryAfterSeconds(value, now) {
    var text = String(value || "").trim();
    if (text === "")
        return 0;
    if (/^\d+(\.\d+)?$/.test(text))
        return Math.min(3600, Math.ceil(Number(text)));
    var at = Date.parse(text);
    if (isNaN(at))
        return 0;
    return Math.max(0, Math.min(3600, Math.ceil((at - (now === undefined ? Date.now() : now)) / 1000)));
}

// Whether the first bytes are a PNG, JPEG, WebP or GIF (the formats the widget keeps).
function looksLikeImage(bytes) {
    if (!bytes || bytes.length < 12)
        return false;
    var b = bytes;
    return (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47)
        || (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff)
        || (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38)
        || (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50);
}

// A random seed as the services take it (an integer below 2^31).
function randomSeed(random) {
    return Math.floor((random === undefined ? Math.random() : random) * 2147483647);
}

// A whole number inside [min, max] (a multiple of `step` when given), or `fallback` when it is not a number.
function clampInt(value, min, max, fallback, step) {
    var n = Math.round(Number(value));
    if (!isFinite(n))
        return fallback;
    n = Math.max(min, Math.min(max, n));
    return step > 1 ? Math.max(min, Math.min(max, Math.round(n / step) * step)) : n;
}
