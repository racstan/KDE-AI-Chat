// Plays sound files one after another for voice/FileSpeech.qml (Qt
// Multimedia), with pause and stop. Two players take turns: while one plays,
// the next file is already loaded in the other (preload()), so the next
// sentence starts without a gap. `ended` fires once when a file has played
// to its end.
import QtQuick
import QtMultimedia

Item {
    id: player

    signal ended()
    signal failed(string message)

    property int _current: 0          // index of the player in use
    readonly property var _players: [first, second]
    property string _preloaded: ""     // file loaded in the other player

    function _url(path) { return "file://" + encodeURI(path); }

    function play(path) {
        var next = _players[1 - _current];
        if (path === _preloaded && next.source.toString() === _url(path)) {
            _players[_current].stop();
            _current = 1 - _current;
        } else {
            _players[_current].source = _url(path);
        }
        _preloaded = "";
        _players[_current].play();
    }
    // Loads the file that comes next, so play(path) can start it at once.
    function preload(path) {
        _preloaded = path;
        _players[1 - _current].source = _url(path);
    }
    function pause() { _players[_current].pause(); }
    function resume() { _players[_current].play(); }
    function stop() {
        _preloaded = "";
        for (var i = 0; i < 2; i++) {
            _players[i].stop();
            _players[i].source = "";
        }
    }

    component Track: MediaPlayer {
        required property int index
        required property var host
        audioOutput: AudioOutput {}
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia && index === host._current)
                host.ended();
        }
        onErrorOccurred: function(error, errorString) {
            if (index === host._current)
                host.failed(errorString || "The sound could not be played.");
        }
    }

    Track { id: first; index: 0; host: player }
    Track { id: second; index: 1; host: player }
}
