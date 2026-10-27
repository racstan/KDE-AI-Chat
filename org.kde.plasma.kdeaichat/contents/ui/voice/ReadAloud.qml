// Read aloud with the engine chosen in Settings → Voice (voice/TtsEngines.js).
// Used by VoiceManager.qml for the chat and by the settings page's test
// button (engines: voice/TtsEngines.js; Speech Note, the default, speaks through
// voice/SpeechNoteSpeech.qml). The engine is loaded on the first speak() and unloaded after two
// idle minutes, so nothing runs while read aloud isn't used. While the chosen
// engine isn't installed (Speech Note),
// System voices read instead, without an error.
//
// `configuration` is read when speak() is called: plasmoid.configuration,
// or the settings page's unsaved values.
import QtQuick
import "TtsEngines.js" as Engines

Item {
    id: reader

    property var configuration: null
    property var runHelper: null
    // Speech Note: the runner for the call that waits for the end of the speech (empty: its own).
    property var waitHelper: null
    // Qt engine to use instead of a registry one, e.g. {"system": "mock"} in tests.
    property var pluginOverride: ({})
    property int idleUnloadMs: 120000

    // "" | "synthesizing" | "playing" | "paused"
    property string phase: ""
    readonly property bool isPlaying: phase !== ""
    readonly property bool paused: phase === "paused"
    // The loaded runner (QtSpeech.qml or FileSpeech.qml).
    readonly property var runner: loader.item
    readonly property bool canPause: !!runner && runner.canPause === true
    property string currentChunk: ""
    property string text: ""
    property string engineId: ""
    // The status line under the chat (ComposerStatus.qml compares these strings).
    readonly property string statusText: phase === "synthesizing" ? (engineId === "speechnote" ? "Starting Speech Note..." : "Generating speech...")
        : phase === "playing" ? "Reading aloud..." : phase === "paused" ? "Paused" : ""

    // The default engine isn't installed yet, so the fallback engine read
    // the last text (the chat and the settings page can say so).
    property bool usedFallback: false

    signal error(string message)

    property var _pending: null
    property string _lastText: ""

    function pluginFor(spec) {
        return (pluginOverride && pluginOverride[spec.id]) || spec.plugin;
    }

    // Settings for the runner: Qt engines take {language, voice, rate, pitch},
    // file engines their main.xml keys as they are.
    function settingsFor(spec, config) {
        if (spec.kind !== "qt")
            return Engines.settingsFor(spec.id, config);
        return {"language": Engines.valueOfType(spec.id, config, "language", ""),
                "voice": Engines.valueOfType(spec.id, config, "voice", ""),
                "rate": Engines.valueOfType(spec.id, config, "rate", 0),
                "pitch": Engines.valueOfType(spec.id, config, "pitch", 0)};
    }

    // Starts reading `text`, replacing what is being read (isPlaying stays
    // true across the switch). False when there is nothing to read.
    function speak(text, engineOverride) {
        var config = configuration || {};
        var spec = Engines.engine(engineOverride || String(config.voiceTtsEngine || "")) || Engines.engine(Engines.defaultEngine);
        var chunks = Engines.chunksFor(spec, text);
        if (chunks.length === 0) {
            stop();
            return false;
        }
        _pending = null;
        if (runner && phase !== "")
            runner.stop();
        currentChunk = "";
        reader.text = text;
        _lastText = text;
        usedFallback = !!engineOverride;
        engineId = spec.id;
        phase = spec.kind === "qt" ? "playing" : "synthesizing";
        _pending = {"chunks": chunks, "settings": settingsFor(spec, config)};
        idle.stop();
        var source = spec.kind === "qt" ? "QtSpeech.qml" : spec.kind === "speechnote" ? "SpeechNoteSpeech.qml" : "FileSpeech.qml";
        var props = spec.kind === "qt" ? {"plugin": pluginFor(spec)}
            : spec.kind === "speechnote" ? {"runHelper": runHelper, "waitHelper": waitHelper}
            : {"engine": spec.id, "runHelper": runHelper, "ahead": spec.ahead || 1};
        var key = spec.id + ":" + pluginFor(spec);
        if (loader.item && loader.engineKey === key) {
            _begin();
        } else {
            loader.engineKey = key;
            loader.source = "";
            loader.setSource(source, props);   // _begin() from onLoaded
        }
        return true;
    }

    function _begin() {
        var pending = _pending;
        _pending = null;
        if (pending && runner)
            runner.start(pending.chunks, pending.settings);
    }

    function stop() {
        _pending = null;
        if (runner && phase !== "")
            runner.stop();
        _done();
    }

    function pause() {
        if (phase === "playing" && canPause) {
            runner.pause();
            phase = "paused";
        }
    }

    function resume() {
        if (phase === "paused") {
            runner.resume();
            phase = "playing";
        }
    }

    function _done() {
        phase = "";
        currentChunk = "";
        reader.text = "";
        if (runner)
            idle.restart();
    }

    function unload() {
        stop();
        idle.stop();
        loader.engineKey = "";
        loader.source = "";
    }

    Loader {
        id: loader
        property string engineKey: ""
        onLoaded: reader._begin()
    }

    Connections {
        target: loader.item
        ignoreUnknownSignals: true
        function onChunkStarted(text) {
            reader.currentChunk = text;
            if (reader.phase === "synthesizing")
                reader.phase = "playing";
        }
        function onFinished() { reader._done(); }
        function onFailed(message, code) {
            // Not installed yet: the system voice reads instead, with no error.
            // (Later: this runner is replaced, so not from inside its signal.)
            var fallback = Engines.fallbackEngine;
            if (code === "not_installed" && reader.engineId !== fallback && reader.phase !== "") {
                let text = reader._lastText;
                Qt.callLater(function() {
                    if (reader.phase !== "" && reader._lastText === text)
                        reader.speak(text, fallback);
                });
                return;
            }
            reader._done();
            reader.error(message);
        }
    }

    Timer {
        id: idle
        interval: reader.idleUnloadMs
        onTriggered: if (reader.phase === "") reader.unload()
    }
}
