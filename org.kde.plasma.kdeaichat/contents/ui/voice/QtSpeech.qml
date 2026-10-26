// Reads aloud in the widget process with QtTextToSpeech (Speech Dispatcher,
// Kokoro, Flite, or Qt's mock engine in tests). One runner of
// voice/ReadAloud.qml; voice/FileSpeech.qml is the other, with the same API:
//   start(chunks, settings), stop(), pause(), resume()
//   chunkStarted(text), finished(), failed(message); canPause
import QtQuick
import QtTextToSpeech
import "TtsEngines.js" as Engines

Item {
    id: speech

    property string plugin: "speechd"
    readonly property bool canPause: (tts.engineCapabilities & TextToSpeech.Capabilities.PauseResume) !== 0

    signal chunkStarted(string text)
    signal finished()
    signal failed(string message)

    property bool _active: false
    property bool _spoke: false
    // Chunks not started yet. aboutToSynthesize comes once per chunk, in
    // order (its id isn't reliable, and the first one fires inside enqueue()).
    property var _queue: []

    // Applies {language, voice, rate, pitch} (as stored; "" = engine default).
    function apply(settings) {
        var language = String(settings.language || "");
        if (language)
            tts.locale = Qt.locale(language);
        var name = String(settings.voice || "");
        if (name) {
            var voices = tts.availableVoices();
            for (var i = 0; i < voices.length; i++) {
                if (voices[i].name === name) {
                    tts.voice = voices[i];
                    break;
                }
            }
        }
        tts.rate = Engines.clampUnit(settings.rate);
        tts.pitch = Engines.clampUnit(settings.pitch);
    }

    function start(chunks, settings) {
        if (tts.state === TextToSpeech.Error) {
            failed(tts.errorString() || "The speech engine could not start.");
            return;
        }
        apply(settings || {});
        _active = true;
        _spoke = false;
        _queue = chunks.slice();
        for (var i = 0; i < chunks.length; i++)
            tts.enqueue(chunks[i]);
    }

    function _finish() {
        settle.stop();
        _active = false;
        finished();
    }

    function stop() {
        settle.stop();
        _active = false;
        tts.stop(TextToSpeech.Immediate);
    }

    function pause() {
        if (canPause)
            tts.pause(TextToSpeech.Immediate);
    }

    function resume() {
        tts.resume();
    }

    TextToSpeech {
        id: tts
        engine: speech.plugin

        onAboutToSynthesize: function(id) {
            if (speech._active && speech._queue.length > 0) {
                var text = speech._queue[0];
                speech._queue = speech._queue.slice(1);
                speech.chunkStarted(text);
            }
        }
        onStateChanged: function(state) {
            if (!speech._active)
                return;
            if (state === TextToSpeech.Speaking || state === TextToSpeech.Paused) {
                speech._spoke = true;
                settle.stop();
            } else if (state === TextToSpeech.Ready && speech._spoke) {
                // Chunks still to come: Ready may be a gap between them (or a
                // late Ready from the text this replaced), so wait to be sure.
                if (speech._queue.length === 0)
                    speech._finish();
                else
                    settle.restart();
            }
        }
        onErrorOccurred: function(reason, message) {
            if (!speech._active)
                return;
            speech._active = false;
            speech.failed(message || "The speech engine failed.");
        }
    }

    Timer {
        id: settle
        interval: 1500
        onTriggered: if (speech._active && tts.state === TextToSpeech.Ready) speech._finish()
    }
}
