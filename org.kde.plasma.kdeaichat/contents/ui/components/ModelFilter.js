.pragma library

// Filtering for components/ModelPicker.qml. Kept as plain JavaScript so it
// can be tested with node.

// Turns a list of model ids (strings) or {id, name} objects into entries
// `{id, name, key}`. `key` is the lower-cased text the filter searches, built
// once per list so each keystroke only runs indexOf over it.
function normalize(list) {
    var entries = [];
    var seen = {};
    var source = list || [];
    for (var i = 0; i < source.length; i++) {
        var item = source[i];
        var id = typeof item === "string" ? item : (item && item.id !== undefined ? String(item.id) : "");
        if (!id || seen[id])
            continue;
        seen[id] = true;
        var name = item && typeof item === "object" && item.name && item.name !== id ? String(item.name) : "";
        entries.push({"id": id, "name": name, "key": (id + " " + name).toLowerCase()});
    }
    return entries;
}

// The entries whose id or name contains every word of `query`, anywhere in
// the text and ignoring case. An empty query returns all entries.
function filter(entries, query) {
    var words = String(query || "").toLowerCase().split(/\s+/).filter(function(word) { return word !== ""; });
    if (words.length === 0)
        return entries;
    var found = [];
    for (var i = 0; i < entries.length; i++) {
        var key = entries[i].key;
        var all = true;
        for (var w = 0; w < words.length; w++) {
            if (key.indexOf(words[w]) < 0) {
                all = false;
                break;
            }
        }
        if (all)
            found.push(entries[i]);
    }
    return found;
}

function indexOfId(entries, id) {
    for (var i = 0; i < entries.length; i++)
        if (entries[i].id === id)
            return i;
    return -1;
}
