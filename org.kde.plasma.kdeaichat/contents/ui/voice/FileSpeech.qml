// Reads aloud with an engine that writes sound files (the natural voice,
// Piper, a speech server, a custom command): the helper (kdeaichat/tts.py)
// makes one WAV per chunk, up to `ahead` chunks ahead of the one playing, and
// voice/WavPlayer.qml plays them, the next one already loaded so sentences
// follow without a gap. Same API as voice/QtSpeech.qml.
//
// `runHelper(command, payload, callback(stdout, exitCode, stderr))` is
// store/HelperRunner.qml's run(); tests pass a fake, and may replace `player`.
import QtQuick

Item {
    id: speech

    property string engine: ""
    property var runHelper: null
    property var player: wavPlayer
    // Chunks made ahead of the one playing (one helper call at a time).
    property int ahead: 1
    readonly property bool canPause: true

    signal chunkStarted(string text)
    signal finished()
    signal failed(string message, string code)

    property int _generation: 0
    property var _chunks: []
    property var _options: ({})
    property int _next: 0          // next chunk to synthesize
    property bool _synthesizing: false
    property var _ready: []        // [{path, text}] made, waiting to play
    property var _playing: null    // {path, text}

    function start(chunks, settings) {
        stop();
        _chunks = chunks.slice();
        _options = settings || {};
        _synthesizeNext();
    }

    function stop() {
        _generation++;
        if (_playing)
            _remove(_playing.path);
        player.stop();
        for (var i = 0; i < _ready.length; i++)
            _remove(_ready[i].path);
        _playing = null;
        _ready = [];
        _chunks = [];
        _next = 0;
        _synthesizing = false;
    }

    function pause() { if (_playing) player.pause(); }
    function resume() { if (_playing) player.resume(); }

    function _remove(path) {
        if (runHelper && path)
            runHelper("tts_cleanup", {"path": path}, null);
    }

    function _synthesizeNext() {
        if (_synthesizing || _next >= _chunks.length || _ready.length >= Math.max(1, ahead))
            return;
        var generation = _generation;
        var text = _chunks[_next++];
        _synthesizing = true;
        if (!runHelper) {
            failed("The helper is not available.", "failed");
            return;
        }
        runHelper("tts_synthesize", {"engine": engine, "text": text, "options": _options}, function(stdout, exitCode, stderr) {
            var reply = null;
            try { reply = JSON.parse(String(stdout).trim().split("\n").pop()); } catch (e) {}
            if (generation !== speech._generation) {   // stopped meanwhile
                if (reply && reply.ok) speech._remove(reply.path);
                return;
            }
            speech._synthesizing = false;
            if (!reply || !reply.ok) {
                speech.stop();
                speech.failed(reply && reply.error ? reply.error : (String(stderr).trim() || "The speech engine gave no answer."),
                              reply && reply.code ? String(reply.code) : "failed");
                return;
            }
            speech._ready = speech._ready.concat([{"path": reply.path, "text": text}]);
            if (!speech._playing)
                speech._playNext();
            else if (speech._ready.length === 1 && speech.player.preload)
                speech.player.preload(reply.path);
            speech._synthesizeNext();
        });
    }

    function _playNext() {
        if (_ready.length === 0) {
            if (_next >= _chunks.length && !_synthesizing) {
                _chunks = [];
                finished();
            }
            return;
        }
        _playing = _ready[0];
        _ready = _ready.slice(1);
        chunkStarted(_playing.text);
        player.play(_playing.path);
        if (_ready.length > 0 && player.preload)
            player.preload(_ready[0].path);
        _synthesizeNext();
    }

    Connections {
        target: speech.player
        function onEnded() {
            if (!speech._playing)
                return;
            speech._remove(speech._playing.path);
            speech._playing = null;
            speech._playNext();
        }
        function onFailed(message) {
            if (!speech._playing)
                return;
            speech.stop();
            speech.failed(message, "failed");
        }
    }

    WavPlayer { id: wavPlayer }
}
