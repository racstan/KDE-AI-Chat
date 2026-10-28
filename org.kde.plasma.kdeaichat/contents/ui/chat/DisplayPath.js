.pragma library

// How a folder is shown to the user: a path under the home folder reads "~/...".
// Display only; "Open folder" and everything that touches the disk keeps the full path.

// A StandardPaths location (a file:// url or a path, maybe percent-encoded) as a plain path without a trailing slash.
function plainPath(location) {
    var s = String(location || "").replace(/^file:\/\//, "");
    try { s = decodeURIComponent(s); } catch (e) { /* keep as is */ }
    return s.length > 1 ? s.replace(/\/+$/, "") : s;
}

// path -> "~", "~/rest" when it is the home folder or inside it; any other path is returned unchanged.
function tilde(path, home) {
    var p = String(path || "");
    var h = plainPath(home);
    if (!p || !h || h === "/")
        return p;
    if (p === h)
        return "~";
    return p.indexOf(h + "/") === 0 ? "~" + p.substring(h.length) : p;
}

// What a user typed in a folder field ("~" or "~/rest" or a full path) -> the full path.
function expand(text, home) {
    var t = String(text || "").trim();
    var h = plainPath(home);
    if (t === "~")
        return h || t;
    return t.indexOf("~/") === 0 && h && h !== "/" ? h + t.substring(1) : t;
}
