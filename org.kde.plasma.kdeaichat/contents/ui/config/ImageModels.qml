// The live model list of an image service, for the editor in ImageProvidersPanel.qml:
//   AI Horde      GET /status/models?type=image (models with workers, adult-content models left out)
//   Pollinations  GET /image/models (image models; the free ones first)
// The older free Pollinations service has one model ("sana"). Lists are kept for the settings
// session. See backends/HordeBackend.js and backends/PollinationsBackend.js for what is filtered.
import QtQuick
import "../backends/HordeBackend.js" as Horde
import "../backends/ImageHttp.js" as ImageHttp
import "../backends/PollinationsBackend.js" as Pollinations

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QtObject {
    id: models

    // Replaces XMLHttpRequest in tests.
    property var xhrFactory: null
    property string version: "dev"
    property string website: ""

    property bool listing: false
    // [{id, name}] for the model picker (name: a short note shown next to the id).
    property var list: []
    // "" | "unreachable" | "failed"
    property string error: ""
    property var _cache: ({})
    property int _generation: 0

    // The model that suits a service best when the user has not chosen one yet.
    function defaultModel(service) {
        if (service === "horde")
            return Horde.defaultModel(list.map(function(m) { return {"id": m.id}; }));
        return service === "pollinations-legacy" ? "sana" : Pollinations.DEFAULT_MODEL;
    }

    function cancel() {
        _generation++;
        listing = false;
    }

    // Lists the models of `service`; `force` asks the service again.
    function load(service, force) {
        error = "";
        if (service === "pollinations-legacy") {
            list = [{"id": "sana", "name": ""}];
            return;
        }
        if (!force && _cache[service]) {
            list = _cache[service];
            return;
        }
        var generation = ++_generation;
        var request = service === "horde" ? Horde.modelsRequest(version, website) : {"url": Pollinations.MODELS_URL, "headers": {"Accept": "application/json"}};
        list = [];
        listing = true;
        ImageHttp.request({"xhrFactory": xhrFactory || function() { return new XMLHttpRequest(); }, "url": request.url, "headers": request.headers, "timeoutMs": 20000}, function(res) {
            if (generation !== _generation)
                return;
            listing = false;
            var data = null;
            try { data = JSON.parse(res.text); } catch (e) { data = null; }
            if (res.status !== 200 || data === null) {
                error = res.status === 0 ? "unreachable" : "failed";
                return;
            }
            var found = service === "horde"
                ? Horde.parseModels(data).map(function(m) { return {"id": m.id, "name": i18np("%1 worker", "%1 workers", m.workers)}; })
                : Pollinations.parseModels(data).map(function(m) { return {"id": m.id, "name": m.paid ? i18n("needs credit") : ""}; });
            var next = Object.assign({}, _cache);
            next[service] = found;
            _cache = next;
            list = found;
            if (found.length === 0)
                error = "failed";
        });
    }
}
