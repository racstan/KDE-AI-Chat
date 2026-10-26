.pragma library

// The panel icon (chat/PanelIcon.qml, Settings → Appearance): a theme icon
// or image file (customIcon), or an animation (panelIconMode "animated":
// GIF, APNG or WebP; "video": a short muted looping video) from
// panelIconFile. Plain JavaScript: tests/test_panel_icon.py runs it in node.

var MODES = ["icon", "animated", "video"];
var ANIMATED_EXTENSIONS = ["gif", "apng", "png", "webp"];
var VIDEO_EXTENSIONS = ["mp4", "webm", "mkv", "mov", "m4v", "ogv"];
// Files above MAX_BYTES are refused; above WARN_BYTES the page warns.
var MAX_BYTES = 20 * 1024 * 1024;
var WARN_BYTES = 5 * 1024 * 1024;
var DEFAULT_ICON = "dialog-messages";

function extension(path) {
    var match = /\.([a-z0-9]+)$/i.exec(String(path || "").trim());
    return match ? match[1].toLowerCase() : "";
}

// True when the customIcon value is an image file, not a theme icon name.
function isImageFile(value) {
    var v = String(value || "").trim().toLowerCase();
    if (v === "")
        return false;
    if (v.indexOf("file://") === 0 || v.charAt(0) === "/")
        return true;
    return /\.(png|jpe?g|gif|webp|svgz?|bmp)$/.test(v);
}

// A path or file:// URL as a source URL ("" stays "").
function fileUrl(value) {
    var v = String(value || "").trim();
    if (v === "" || v.indexOf("file://") === 0)
        return v;
    return "file://" + v.split("/").map(encodeURIComponent).join("/");
}

// "animated", "video" or "" (not a file this mode can show).
function fileKind(path) {
    var ext = extension(path);
    if (ANIMATED_EXTENSIONS.indexOf(ext) >= 0)
        return "animated";
    if (VIDEO_EXTENSIONS.indexOf(ext) >= 0)
        return "video";
    return "";
}

// The mode actually shown: an animation only with a file of its kind,
// otherwise the normal icon.
function effectiveMode(mode, file) {
    var m = MODES.indexOf(mode) >= 0 ? mode : "icon";
    if (m === "icon" || String(file || "").trim() === "")
        return "icon";
    return fileKind(file) === m ? m : "icon";
}

// What the settings page says about a checked file: {ok, warn, message}.
// info is the helper's panel_icon_check reply: {exists, size, kind}.
function verdict(info, mode) {
    if (!info || info.error)
        return {"ok": false, "warn": false, "reason": "unreadable"};
    if (!info.exists)
        return {"ok": false, "warn": false, "reason": "missing"};
    if (info.kind !== mode)
        return {"ok": false, "warn": false, "reason": "kind"};
    if (Number(info.size) > MAX_BYTES)
        return {"ok": false, "warn": false, "reason": "too-large"};
    return {"ok": true, "warn": Number(info.size) > WARN_BYTES, "reason": ""};
}

function megabytes(bytes) {
    return (Math.round(Number(bytes || 0) / 104857.6) / 10).toFixed(1);
}

// Whether the animation should run now.
function shouldPlay(state) {
    if (!state || state.mode === "icon" || state.failed)
        return false;
    if (!state.visible || state.locked)
        return false;
    return !state.hoverOnly || state.hovered === true;
}
