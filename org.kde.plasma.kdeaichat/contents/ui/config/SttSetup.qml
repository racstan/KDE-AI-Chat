// Settings → Voice, dictation: what the page asks the helper
// (kdeaichat/stt_*.py, voice_data.py), with the page's unsaved choices as
// the payload. Nothing here installs or downloads on its own: install() and
// download() run only from buttons, after estimate() showed the size.
//
// runHelper(command, payload, callback(stdout, exitCode, stderr)) is
// store/HelperRunner.qml's run(); tests pass a fake.
import QtQuick

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QtObject {
    id: setup

    property var runHelper: null
    // The stt* settings as they are on the page (voice/SttConfig.js payload()).
    property var payload: ({})

    property var engines: []         // stt_engines rows
    property bool enginesLoaded: false
    property var gpu: false
    property var catalogue: []       // faster-whisper models: {name, mb, downloaded, recommended, note}
    property var found: []           // models on disk: {engine, model, path, name, source, mb}
    property var size: null          // stt_setup_size reply
    property var data: null          // voice_data reply's faster_whisper part

    property bool installing: false
    property bool downloading: false
    property bool testing: false
    property bool removing: false
    readonly property bool busy: installing || downloading || removing

    property string status: ""
    property string testResult: ""

    signal installed(bool ok)

    function _reply(stdout) {
        var lines = String(stdout || "").trim().split("\n");
        for (var i = lines.length - 1; i >= 0; i--) {
            try {
                var data = JSON.parse(lines[i]);
                if (data && typeof data === "object")
                    return data;
            } catch (e) {}
        }
        return null;
    }

    function _run(command, extra, done) {
        if (!runHelper) {
            if (done) done(null, i18n("The helper is not available."));
            return;
        }
        runHelper(command, Object.assign({}, payload, extra || {}), function(stdout, exitCode, stderr) {
            var reply = setup._reply(stdout);
            if (done) done(reply, reply ? "" : (String(stderr || "").trim().split("\n").pop() || i18n("No answer.")));
        });
    }

    function engineRow(id) {
        for (var i = 0; i < engines.length; i++)
            if (engines[i].id === id)
                return engines[i];
        return null;
    }
    readonly property bool fasterWhisperInstalled: !!(engineRow("faster-whisper") || {}).installed

    // Everything the page shows; cheap (no download, nothing started).
    function refresh() {
        refreshEngines();
        _run("stt_models", {}, function(r) {
            if (r && r.type === "stt_models") {
                setup.catalogue = r.faster_whisper || [];
                setup.found = r.found || [];
                setup.gpu = !!r.gpu;
            }
        });
        estimate();
        loadData();
    }

    function refreshEngines() {
        _run("stt_engines", {}, function(r, error) {
            if (r && r.type === "stt_engines") {
                setup.engines = r.engines || [];
                setup.gpu = !!r.gpu;
            } else if (r && r.error) {
                setup.status = r.error;
            } else if (error) {
                setup.status = error;
            }
            setup.enginesLoaded = true;
        });
    }

    // What installing faster-whisper (and the chosen model) would download.
    function estimate() {
        _run("stt_setup_size", {"gpu": payload.sttDevice === "cpu" ? false : payload.sttDevice === "cuda" ? true : "auto"},
             function(r) { if (r && r.type === "stt_setup_size") setup.size = r; });
    }

    function loadData() {
        _run("voice_data", {}, function(r) { if (r && r.type === "voice_data") setup.data = r.faster_whisper || null; });
    }

    // Shows the dictation service for the page's choices (or removes it).
    function syncUnits(enabled) {
        _run("stt_sync_units", {"sttEnabled": enabled === undefined ? payload.sttEnabled === true : enabled}, null);
    }

    // faster-whisper runs as the on-demand service, so its units must exist
    // before a download or a test (the next widget start removes them again
    // if dictation stays off).
    function _withService(work) {
        if (payload.sttEngine !== "faster-whisper")
            work();
        else
            _run("stt_sync_units", {"sttEnabled": true}, function() { work(); });
    }

    function install() {
        if (busy)
            return;
        installing = true;
        status = i18n("Installing faster-whisper. This takes a few minutes…");
        var mode = payload.sttDevice === "cpu" ? "cpu" : payload.sttDevice === "cuda" ? "gpu" : "auto";
        _run("stt_install", {"gpu": mode}, function(r, error) {
            setup.installing = false;
            var ok = !!(r && r.ok);
            setup.status = ok ? i18n("faster-whisper is installed.") : i18n("Installing failed: %1", (r && r.error) || error);
            if (ok)
                setup.syncUnits(true);
            setup.refresh();
            setup.installed(ok);
        });
    }

    function download() {
        if (busy)
            return;
        downloading = true;
        status = i18n("Downloading the model…");
        _withService(function() {
            setup._run("stt_download_model", {}, function(r, error) {
                setup.downloading = false;
                var ok = !!(r && r.type === "stt_downloaded");
                setup.status = ok ? i18n("The model is downloaded.") : i18n("Downloading failed: %1", (r && r.error) || error);
                setup.refresh();
            });
        });
    }

    // Transcribes the bundled sample with the page's choices (no microphone).
    function test() {
        if (testing)
            return;
        testing = true;
        testResult = i18n("Transcribing a sample recording…");
        _withService(function() {
            setup._run("stt_test", {}, function(r, error) {
                setup.testing = false;
                if (r && r.type === "stt_result")
                    setup.testResult = r.text ? i18n("Heard: “%1” (%2 s)", r.text, r.seconds) : i18n("No speech heard.");
                else if (r && r.code === "model_missing")
                    setup.testResult = i18n("The model is not downloaded yet.");
                else
                    setup.testResult = i18n("The test failed: %1", (r && r.error) || error);
            });
        });
    }

    // keepModels: true to rebuild the engine smaller, keeping downloaded models.
    function removeData(keepModels, done) {
        if (busy)
            return;
        removing = true;
        status = keepModels ? i18n("Removing the old engine…") : i18n("Removing faster-whisper's data…");
        _run("voice_data_remove", {"engine": "faster-whisper", "confirm": true, "keepModels": keepModels === true},
             function(r, error) {
            setup.removing = false;
            var ok = !!(r && r.type === "voice_data_removed");
            setup.status = ok ? i18n("Freed %1.", Math.round(r.freed_mb) + " MB") : i18n("Removing failed: %1", (r && r.error) || error);
            setup.refresh();
            if (done) done(ok);
        });
    }

    function rebuild() {
        removeData(true, function(ok) { if (ok) setup.install(); });
    }
}
