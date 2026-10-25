// Making pictures from a prompt with an image service (AI Horde, Pollinations).
//
// The chat's request path for an image provider and for /image. A job shows as a reply
// with a progress card (queue place and wait time for AI Horde, the 45 s countdown for the
// older free Pollinations service) until its pictures arrive; Stop cancels it (AI Horde's
// job is cancelled with DELETE). The pictures are saved as files by chat/ImageStore.qml.
//
// The job reports through the same events a model's streamed reply does
// (chat.applyBackendEvent), so the reply, Stop, the queue of messages and notifications
// work as they do for text: {type: "image_job", job}, {type: "images", items, meta},
// {type: "error", message} and {type: "done"}. Network and timers can be replaced in tests.
// `chat` is the widget root (main.qml).
import QtQuick
import "../ProviderService.js" as ProviderService
import "../backends/HordeBackend.js" as Horde
import "../backends/ImageHttp.js" as ImageHttp
import "../backends/PollinationsBackend.js" as Pollinations
import "ImageExtract.js" as ImageExtract

QtObject {
    id: jobs

    property var chat: null
    property var imageStore: null    // chat/ImageStore.qml
    // Replaces XMLHttpRequest in tests.
    property var xhrFactory: null
    // The widget's version and website (metadata.json), for AI Horde's Client-Agent.
    property string version: chat && chat.plasmoid && chat.plasmoid.metaData ? String(chat.plasmoid.metaData.version) : "dev"
    property string website: chat && chat.plasmoid && chat.plasmoid.metaData ? String(chat.plasmoid.metaData.website || "") : ""
    readonly property var configuration: chat && chat.plasmoid ? chat.plasmoid.configuration : ({})
    // How often to look at whether the saving of a finished job is done.
    property int settleInterval: 100

    property Component timerComponent: Component { Timer { repeat: false } }
    property var setTimer: function(fn, ms) {
        var timer = jobs.timerComponent.createObject(jobs);
        timer.interval = ms;
        timer.triggered.connect(function() { fn(); timer.destroy(); });
        timer.start();
        return timer;
    }
    property var clearTimer: function(timer) {
        if (timer) {
            timer.stop();
            timer.destroy();
        }
    }

    // When the older free Pollinations service may be asked next (kept in the settings, not secret).
    property var _pacer: null
    function pacer() {
        if (!_pacer) {
            var state = {};
            try { state = JSON.parse(String(configuration.pollinationsFreeState || "{}")); } catch (e) { state = {}; }
            _pacer = Pollinations.createPacer(state);
        }
        return _pacer;
    }

    function serviceName(cfg) {
        return (ProviderService.IMAGE_SERVICES[cfg.service] || {"name": "Image service"}).name;
    }

    // "" when this provider can make pictures now, else what is missing, in plain words.
    function validate(providerId, cfg) {
        var name = serviceName(cfg);
        if (cfg.found === false)
            return "The image service \"" + chat.providerDisplayName(providerId) + "\" isn't set up any more. Add it in Settings → Connection.";
        if (!cfg.accepted)
            return name + " is switched off. Open Settings → Connection, edit it, read what it sends where, and switch it on.";
        if (cfg.service === "horde" && cfg.model && !Horde.isSafeModel({"name": cfg.model}))
            return "AI Horde's model \"" + cfg.model + "\" is made for adult content, so the widget does not use it. Pick another model in Settings → Connection.";
        if (cfg.service === "pollinations" && !cfg.apiKey)
            return "Pollinations needs your key for this. Add it in Settings → Connection.";
        return "";
    }

    // Starts the service's job; onEvent gets the backend's events. Returns {cancel()}.
    function start(cfg, prompt, onEvent) {
        var o = cfg.options || {};
        var base = {"http": ImageHttp, "xhrFactory": jobs.xhrFactory || function() { return new XMLHttpRequest(); },
                    "setTimer": jobs.setTimer, "clearTimer": jobs.clearTimer, "toBase64": ImageExtract.bytesToBase64,
                    "version": jobs.version, "contact": jobs.website, "prompt": prompt, "onEvent": onEvent, "width": o.width, "height": o.height, "seed": o.seed};
        if (cfg.service === "horde")
            return Horde.generate(Object.assign(base, {"model": cfg.model, "apiKey": cfg.apiKey, "steps": o.steps, "n": o.n}));
        if (cfg.service === "pollinations-legacy")
            return Pollinations.generate(Object.assign(base, {"service": "legacy", "pacer": jobs.pacer()}));
        return Pollinations.generate(Object.assign(base, {"service": "key", "model": cfg.model, "apiKey": cfg.apiKey}));
    }

    function _savePacer() {
        try { configuration.pollinationsFreeState = JSON.stringify(jobs.pacer().state()); } catch (e) {}
    }

    // Makes the pictures for `prompt` as the reply of the open chat's current request.
    function send(sessionId, generation, cfg, providerId, prompt) {
        var name = serviceName(cfg);
        var label = cfg.model ? name + " · " + cfg.model : name;
        var current = function() { return chat.requestIsCurrent(sessionId, generation); };
        var meta = {"source": "generated", "prompt": prompt, "service": name, "provider": providerId};
        var handle = null;
        var finished = false;
        chat.loading = true;
        chat.applyBackendEvent({"type": "image_job", "job": {"service": cfg.service, "name": name, "phase": "starting", "prompt": prompt}}, label);

        function waitForSaves(done, tries) {
            var id = chat.currentStreamKey;
            if (!jobs.imageStore.hasPending(id) || tries > 600) {
                done();
                return;
            }
            jobs.setTimer(function() { waitForSaves(done, tries + 1); }, jobs.settleInterval);
        }
        function end(reason, message) {
            if (finished || !current())
                return;
            finished = true;
            if (reason === "error")
                chat.applyBackendEvent({"type": "error", "message": message}, label);
            // Pictures that are still being saved finish first, so the reply keeps them.
            waitForSaves(function() {
                if (!current())
                    return;
                var made = chat.messages[chat.currentStreamIndex];
                var ok = reason === "complete" && made && (made.images || []).length > 0;
                chat.applyBackendEvent({"type": "done", "reason": ok ? "complete" : "error"}, label);
            }, 0);
        }
        // Stop: the service is told to drop the job, and the reply (with no pictures yet) goes away.
        chat.activeXhr = {"abort": function() { finished = true; if (handle) handle.cancel(); }};
        handle = jobs.start(cfg, prompt, function(event) {
            if (finished || !current())
                return;
            // The free service's gap is kept across restarts: saved when a request goes out or is refused.
            if (cfg.service === "pollinations-legacy" && (event.phase === "working" || event.type === "error"))
                jobs._savePacer();
            if (event.type === "progress" || event.type === "submitted") {
                if (event.type === "progress")
                    chat.applyBackendEvent({"type": "image_job", "job": Object.assign({"service": cfg.service, "name": name, "prompt": prompt}, event)}, label);
            } else if (event.type === "images") {
                chat.applyBackendEvent({"type": "images", "items": event.items, "meta": meta}, label);
            } else if (event.type === "error") {
                end("error", event.message);
            } else if (event.type === "done") {
                end("complete", "");
            }
        });
    }

    // Another picture from the same prompt (a new seed) as image `index` of a message.
    function regenerate(messageId, index) {
        var list = chat.messages;
        var image = null;
        for (var i = 0; i < list.length && !image; i++) {
            if (list[i] && list[i].id === messageId && (list[i].images || []).length > index)
                image = list[i].images[index];
        }
        if (!image || !image.prompt || chat.loading)
            return;
        var providerId = image.provider && ProviderService.getProviderConfig(image.provider, configuration).found !== false
            ? image.provider : ProviderService.defaultImageProvider(configuration);
        var cfg = providerId ? chat.getProviderConfig(providerId, chat.currentSessionId) : ({"found": false});
        var problem = cfg.type === "image" ? jobs.validate(providerId, cfg) : "Add an image service in Settings → Connection first.";
        if (problem !== "") {
            chat.pushErrorMessage(problem);
            return;
        }
        // A new seed: the same prompt and settings would otherwise give the same picture.
        cfg = Object.assign({}, cfg, {"options": Object.assign({}, cfg.options, {"seed": -1})});
        jobs.send(chat.currentSessionId, chat.beginRequest(chat.currentSessionId), cfg, providerId, image.prompt);
    }
}
