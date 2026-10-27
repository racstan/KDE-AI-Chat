.pragma library

// Words-free logic for "Find local servers" (config/LocalServers.qml): reads
// the helper's local_servers_scan answer and decides which servers are
// already in the provider list. Plain JavaScript (tested with node).

// The helper's answer -> [server] ({id, kind, name, port, baseUrl, models, count, needsKey, provider}),
// or null when it failed or printed something else.
function parse(stdout, exitCode) {
    if (exitCode !== 0)
        return null;
    var data;
    try {
        data = JSON.parse(String(stdout || "").trim());
    } catch (e) {
        return null;
    }
    if (!data || !Array.isArray(data.servers))
        return null;
    return data.servers.filter(function(s) {
        return s && typeof s.id === "string" && typeof s.baseUrl === "string" && Array.isArray(s.models);
    });
}

// "127.0.0.1:11434" for http://localhost:11434/v1, http://[::1]:11434 ... ("" when not a loopback address).
function loopbackPort(url) {
    var m = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(?::(\d+))?(?:[/?#]|$)/i.exec(String(url || "").trim());
    return m ? (m[2] || "80") : "";
}

// Is there already a provider (not a picture service) that talks to this server's port?
function isAdded(server, providers) {
    return (providers || []).some(function(p) {
        return p && p.type !== "image" && loopbackPort(p.baseUrl) === String(server.port);
    });
}

// The model a new provider starts with: the first that isn't an embedding model.
function defaultModel(models) {
    var list = models || [];
    for (var i = 0; i < list.length; i++) {
        if (!/embed/i.test(list[i]))
            return list[i];
    }
    return list.length > 0 ? list[0] : "";
}

// What a new provider is made from: {presetId, overrides}. A server that is not one of the
// presets' programs becomes the generic "Other OpenAI-compatible" provider with the server's name.
function providerFor(server) {
    var overrides = {"baseUrl": server.baseUrl, "model": defaultModel(server.models)};
    if (server.provider === "custom")
        overrides.name = server.name + " (local)";
    // needsKey: the editor opens asking for the key; models are listed only once it is saved.
    return {"presetId": server.provider, "overrides": overrides, "needsKey": server.needsKey === true};
}
