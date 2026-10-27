.pragma library

// Settings → Storage: plain-text helpers (sizes and file:// addresses).

// 0 → "0 B", 1536 → "1.5 KB", 1.7e9 → "1.7 GB" (1000-based, like most file managers).
function size(bytes) {
    var n = Number(bytes);
    if (!isFinite(n) || n <= 0)
        return "0 B";
    var units = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    while (n >= 1000 && i < units.length - 1) {
        n /= 1000;
        i++;
    }
    var text = (i === 0 || n >= 100) ? String(Math.round(n)) : n.toFixed(1).replace(/\.0$/, "");
    return text + " " + units[i];
}

// A folder path as a file:// address, with spaces and the like escaped.
function fileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
}

// The helper's storage_usage reply (a JSON string) as an object, or null.
function parse(stdout) {
    try {
        var data = JSON.parse(String(stdout).trim().split("\n").pop());
        return data && data.type === "storage_usage" ? data : null;
    } catch (e) {
        return null;
    }
}

// The item with this id in a usage reply, or null.
function find(usage, id) {
    var items = usage && usage.items ? usage.items : [];
    for (var i = 0; i < items.length; i++)
        if (items[i].id === id)
            return items[i];
    return null;
}
