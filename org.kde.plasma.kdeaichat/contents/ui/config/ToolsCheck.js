.pragma library

// Settings → Tools, "Check servers": what the tool bridge answered, as one row per server.

// names: the servers on the page; tools: [{name, server}]; errors: [{server, message}];
// text: {webName, toolsName, notWorking(message), count(n)} (translated by the page).
// Returns [{name, text, ok}]: each server with its tool count or its error, then the web tools
// (tools of no listed server) and errors that belong to no server.
function rows(names, tools, errors, text) {
    var out = [];
    var counts = {};
    var failed = {};
    var general = [];
    var web = 0;
    var i;
    for (i = 0; i < tools.length; i++) {
        var server = String(tools[i].server || "");
        if (names.indexOf(server) >= 0)
            counts[server] = (counts[server] || 0) + 1;
        else
            web++;
    }
    for (i = 0; i < errors.length; i++) {
        if (names.indexOf(errors[i].server) >= 0)
            failed[errors[i].server] = errors[i].message;
        else
            general.push(errors[i]);
    }
    for (i = 0; i < names.length; i++)
        out.push(failed[names[i]] !== undefined ? {"name": names[i], "text": text.notWorking(failed[names[i]]), "ok": false}
                                                : {"name": names[i], "text": text.count(counts[names[i]] || 0), "ok": true});
    if (web > 0)
        out.push({"name": text.webName, "text": text.count(web), "ok": true});
    for (i = 0; i < general.length; i++)
        out.push({"name": general[i].server || text.toolsName, "text": general[i].message, "ok": false});
    return out;
}
