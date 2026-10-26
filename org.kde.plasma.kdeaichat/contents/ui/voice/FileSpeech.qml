// Reads aloud with an engine that writes sound files (Piper, a speech
// server, a custom command): the helper (kdeaichat/tts.py) makes one WAV per
// chunk, one chunk ahead of the one playing, and voice/WavPlayer.qml plays
// them. Same API as voice/QtSpeech.qml.
//
// `runHelper(command, payload, callback(stdout, exitCode, stderr))` is
// store/HelperRunner.qml's run(); tests pass a fake, and may replace `player`.
import QtQuick

Item {
    id: speech

    property string engine: ""
    property var runHelper: null
    property var player: wavPlayer
    readonly property bool canPause: true

    signal chunkStarted(string text)
    signal finished()
    signal failed(string message)

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
        if (_playing) {
            player.stop();
            _remove(_playing.path);
        }
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
        if (_synthesizing || _next >= _chunks.length || _ready.length > 0)
            return;
        var generation = _generation;
        var text = _chunks[_next++];
        _synthesizing = true;
        if (!runHelper) {
            failed("The helper is not available.");
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
                speech.failed(reply && reply.error ? reply.error : (String(stderr).trim() || "The speech engine gave no answer."));
                return;
            }
            speech._ready = speech._ready.concat([{"path": reply.path, "text": text}]);
            if (!speech._playing)
                speech._playNext();
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
            speech.failed(message);
        }
    }

    WavPlayer { id: wavPlayer }
}
