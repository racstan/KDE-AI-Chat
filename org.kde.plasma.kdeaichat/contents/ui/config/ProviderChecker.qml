// The provider-editor's network side: lists a provider's models and checks a
// key (and model) before it is saved. See ../ProviderCheck.js for the logic;
// this adds the settings-session cache, "give up on stale answers" and the
// texts shown to the user. Nothing here touches KWallet or the config.
import QtQuick
import "../ProviderCheck.js" as ProviderCheck

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QtObject {
    id: checker

    // Replaces XMLHttpRequest in tests: a function returning an XHR-like object.
    property var xhrFactory: null

    property bool listing: false
    property bool checking: false

    // Model lists fetched in this settings session, by provider id and URL.
    property var cache: ({})
    // Providers whose model has been tried this session (id|model), so opening
    // the editor again does not send the request again.
    property var probed: ({})
    // Bumped when a model is found dead or alive, for bindings on deadReason().
    property int deadRevision: 0

    property int _listGeneration: 0
    property int _checkGeneration: 0

    function _opts() {
        return {"xhrFactory": xhrFactory};
    }

    function cacheKey(entry) {
        return entry.id + "|" + entry.baseUrl;
    }

    function deadReason(providerId, model) {
        // Reading deadRevision makes bindings on this call update.
        return deadRevision < 0 ? "" : ProviderCheck.deadReason(providerId, model);
    }

    // Drops answers still on their way (the editor was closed or reopened).
    function cancel() {
        _listGeneration += 1;
        _checkGeneration += 1;
        listing = false;
        checking = false;
    }

    // Fetches the model list. cb({ok, chat, all, hidden, error, status}).
    // Uses the session cache unless `force`.
    function loadModels(entry, key, force, cb) {
        var cached = cache[cacheKey(entry)];
        if (cached && !force) {
            cb(cached);
            return;
        }
        var generation = ++_listGeneration;
        listing = true;
        ProviderCheck.listModels(entry, key, function(result) {
            if (generation !== _listGeneration)
                return;
            listing = false;
            if (result.ok) {
                let next = Object.assign({}, cache);
                next[cacheKey(entry)] = result;
                cache = next;
            }
            cb(result);
        }, _opts());
    }

    // Checks the key and model with the provider. cb(result), see
    // ProviderCheck.checkProvider. Records a dead (or recovered) model.
    function verify(entry, key, local, cb) {
        var known = cache[cacheKey(entry)];
        var generation = ++_checkGeneration;
        checking = true;
        ProviderCheck.checkProvider({"cfg": entry, "apiKey": key, "model": entry.model, "local": local,
                                     "knownList": known, "xhrFactory": xhrFactory}, function(result) {
            if (generation !== _checkGeneration)
                return;
            checking = false;
            if (result.modelChecked) {
                if (result.state === "model_unavailable")
                    ProviderCheck.markDead(entry.id, entry.model, result.reason || i18n("not available"));
                else
                    ProviderCheck.clearDead(entry.id, entry.model);
                deadRevision += 1;
            }
            if (result.state !== "skipped") {
                let next = Object.assign({}, probed);
                next[entry.id + "|" + entry.model] = true;
                probed = next;
            }
            cb(result);
        });
    }

    // Notes a model the provider's list does not contain (local servers).
    function markMissing(entry, listed) {
        var model = String(entry.model || "");
        if (model === "")
            return;
        if (listed.indexOf(model) < 0)
            ProviderCheck.markDead(entry.id, model, i18n("not on this server"));
        else
            ProviderCheck.clearDead(entry.id, model);
        deadRevision += 1;
    }

    function hostOf(url) {
        var m = /^[a-z]+:\/\/([^/]+)/i.exec(String(url || ""));
        return m ? m[1] : "";
    }

    // {text, kind} for the editor; kind is "ok", "warn" or "error".
    function describe(entry, result) {
        var name = entry.name || entry.id;
        switch (result.state) {
        case "key_rejected":
            return {"text": i18n("%1 rejected this key (%2). Check you copied the whole key.", name, result.status), "kind": "error"};
        case "model_unavailable":
            return {"text": i18n("The key works, but the model %1 is not available from %2 (HTTP %3). %4Pick another model, or use it anyway.",
                                 entry.model, name, result.status, result.reason ? result.reason.replace(/[.\s]+$/, "") + ". " : ""), "kind": "warn"};
        case "unverified":
            if (result.error === "timeout" || result.error === "network" || result.error === "send" || result.error === "url")
                return {"text": result.error === "timeout"
                        ? i18n("Could not check the key: %1 did not answer in time. Check your connection, or save without checking.", hostOf(entry.baseUrl))
                        : i18n("Could not check the key: %1 could not be reached. Check your connection, or save without checking.", hostOf(entry.baseUrl)),
                        "kind": "warn"};
            return {"text": i18n("Could not check the key: %1 answered unexpectedly (HTTP %2). You can save without checking.", name, result.status), "kind": "warn"};
        case "ok":
            if (result.warning === "limit")
                return {"text": i18n("Key accepted. %1 is limiting requests or out of credit right now (HTTP %2).", name, result.status), "kind": "ok"};
            return {"text": i18n("Key accepted by %1.", name), "kind": "ok"};
        }
        return {"text": "", "kind": "ok"};
    }
}
