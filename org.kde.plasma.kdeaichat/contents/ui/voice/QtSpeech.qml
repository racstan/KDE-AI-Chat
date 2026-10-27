// Reads aloud in the widget process with QtTextToSpeech (Speech Dispatcher,
// Kokoro, Flite, or Qt's mock engine in tests). One runner of
// voice/ReadAloud.qml; voice/FileSpeech.qml is the other, with the same API:
//   start(chunks, settings), stop(), pause(), resume()
//   chunkStarted(text), finished(), failed(message, code); canPause
//
// Chunks are said one after another: the next one when the engine is Ready
// after speaking the previous. (Enqueuing them all at once made Speech
// Dispatcher announce every chunk at the start and go Ready between them,
// so the reader looked finished while it was still talking.)
import QtQuick
import QtTextToSpeech
import "TtsEngines.js" as Engines

Item {
    id: speech

    property string plugin: "speechd"
    readonly property bool canPause: (tts.engineCapabilities & TextToSpeech.Capabilities.PauseResume) !== 0

    signal chunkStarted(string text)
    signal finished()
    signal failed(string message, string code)

    property bool _active: false
    // The chunk being said has made the engine speak (a Ready before that is
    // left over from the text this replaced).
    property bool _spoke: false
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
            failed(tts.errorString() || "The speech engine could not start.", "failed");
            return;
        }
        apply(settings || {});
        _active = true;
        _queue = chunks.slice();
        _sayNext();
    }

    function _sayNext() {
        if (_queue.length === 0) {
            _active = false;
            finished();
            return;
        }
        var text = _queue[0];
        _queue = _queue.slice(1);
        _spoke = false;
        chunkStarted(text);
        tts.say(text);
    }

    function stop() {
        _active = false;
        _queue = [];
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

        onStateChanged: function(state) {
            if (!speech._active)
                return;
            if (state === TextToSpeech.Speaking || state === TextToSpeech.Paused || state === TextToSpeech.Synthesizing)
                speech._spoke = true;
            else if (state === TextToSpeech.Ready && speech._spoke)
                speech._sayNext();
        }
        onErrorOccurred: function(reason, message) {
            if (!speech._active)
                return;
            speech._active = false;
            speech.failed(message || "The speech engine failed.", "failed");
        }
    }
}
