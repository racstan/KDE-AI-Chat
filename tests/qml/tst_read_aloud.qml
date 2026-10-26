// Read aloud (voice/ReadAloud.qml) with Qt's mock speech engine standing in
// for System voices, and with a file engine whose helper and player are fakes:
// it stays "playing" until the engine has really finished, stop is final,
// pause/resume, chunks play in order one synthesis ahead, errors reach the
// error signal and played files are removed.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/voice" as Voice

Item {
    id: root
    width: 200
    height: 100

    property var config: ({"voiceTtsEngine": "system"})
    property var helperCalls: []
    property var pendingCallbacks: []
    property var errors: []

    function fakeHelper(command, payload, callback) {
        helperCalls.push({"command": command, "payload": payload});
        if (command === "tts_synthesize")
            pendingCallbacks.push({"payload": payload, "callback": callback});
    }

    Voice.ReadAloud {
        id: reader
        configuration: root.config
        runHelper: root.fakeHelper
        pluginOverride: ({"system": "mock"})
        onError: function(message) { root.errors.push(message); }
    }

    QtObject {
        id: fakePlayer
        signal ended()
        signal failed(string message)
        property var played: []
        property string state: ""
        function play(path) { played.push(path); state = "playing"; }
        function pause() { state = "paused"; }
        function resume() { state = "playing"; }
        function stop() { state = "stopped"; }
    }

    TestCase {
        name: "ReadAloud"
        when: windowShown

        function init() {
            root.config = {"voiceTtsEngine": "system"};
            root.helperCalls = [];
            root.pendingCallbacks = [];
            root.errors = [];
            reader.pluginOverride = {"system": "mock"};
            reader.unload();
        }

        function test_system_voice_plays_until_the_engine_is_done() {
            verify(reader.speak("**Hello** there. This is a test."));
            compare(reader.engineId, "system");
            verify(reader.isPlaying);
            compare(reader.statusText, "Reading aloud...");
            tryVerify(function() { return reader.currentChunk !== ""; }, 3000, "a chunk started");
            verify(reader.currentChunk.indexOf("**") < 0, "Markdown marks are not spoken");
            wait(150);
            verify(reader.isPlaying, "still playing while the engine speaks");
            tryVerify(function() { return !reader.isPlaying; }, 15000, "finished");
            compare(reader.statusText, "");
            compare(root.errors.length, 0);
        }

        function test_stop_is_final() {
            reader.speak("One two three four five six seven eight nine ten.");
            tryVerify(function() { return reader.currentChunk !== ""; }, 3000);
            reader.stop();
            verify(!reader.isPlaying);
            wait(400);
            verify(!reader.isPlaying);
            compare(root.errors.length, 0);
        }

        function test_pause_and_resume() {
            reader.speak("One two three four five six seven eight nine ten eleven twelve.");
            tryVerify(function() { return reader.currentChunk !== ""; }, 3000);
            verify(reader.canPause, "the mock engine can pause");
            reader.pause();
            compare(reader.statusText, "Paused");
            verify(reader.isPlaying);
            reader.resume();
            compare(reader.statusText, "Reading aloud...");
            reader.stop();
        }

        function test_unknown_engine_reports_an_error() {
            reader.pluginOverride = {"system": "no-such-engine"};
            reader.speak("Hello.");
            tryVerify(function() { return root.errors.length === 1; }, 3000);
            verify(!reader.isPlaying);
        }

        function test_empty_text_is_not_read() {
            verify(!reader.speak("   "));
            verify(!reader.isPlaying);
        }

        function fileReply(index, reply) {
            var pending = root.pendingCallbacks[index];
            pending.callback(JSON.stringify(reply), 0, "");
        }

        function test_file_engine_plays_chunks_in_order() {
            root.config = {"voiceTtsEngine": "piper", "voiceTtsPiperModel": "/v/en.onnx", "voiceTtsPiperSpeed": 1.2};
            var long = [];
            for (var i = 0; i < 40; i++)
                long.push("Sentence number " + i + " is here.");
            reader.speak(long.join(" "));
            tryVerify(function() { return !!reader.children.length && root.pendingCallbacks.length === 1; }, 3000);
            compare(reader.statusText, "Generating speech...");
            var payload = root.pendingCallbacks[0].payload;
            compare(payload.engine, "piper");
            compare(payload.options.voiceTtsPiperModel, "/v/en.onnx");
            compare(payload.options.voiceTtsPiperSpeed, 1.2);
            var speech = findSpeech();
            speech.player = fakePlayer;
            fakePlayer.played = [];
            fileReply(0, {"ok": true, "path": "/run/a.wav"});
            compare(reader.statusText, "Reading aloud...");
            compare(fakePlayer.played, ["/run/a.wav"]);
            compare(root.pendingCallbacks.length, 2, "the next chunk is made while the first plays");
            fileReply(1, {"ok": true, "path": "/run/b.wav"});
            compare(root.pendingCallbacks.length, 2, "only one chunk ahead");
            reader.pause();
            compare(fakePlayer.state, "paused");
            reader.resume();
            fakePlayer.ended();
            compare(fakePlayer.played, ["/run/a.wav", "/run/b.wav"]);
            verify(root.helperCalls.some(function(c) { return c.command === "tts_cleanup" && c.payload.path === "/run/a.wav"; }),
                   "a played file is removed");
            compare(root.pendingCallbacks.length, 3);
            reader.stop();
            verify(!reader.isPlaying);
            // A chunk that arrives after stop is removed and not played.
            fileReply(2, {"ok": true, "path": "/run/c.wav"});
            compare(fakePlayer.played.length, 2);
            verify(root.helperCalls.some(function(c) { return c.command === "tts_cleanup" && c.payload.path === "/run/c.wav"; }));
        }

        function test_file_engine_finishes_after_the_last_chunk() {
            root.config = {"voiceTtsEngine": "command", "voiceTtsCommand": "say"};
            reader.speak("Short one.");
            tryVerify(function() { return root.pendingCallbacks.length === 1; }, 3000);
            findSpeech().player = fakePlayer;
            fileReply(0, {"ok": true, "path": "/run/x.wav"});
            verify(reader.isPlaying);
            fakePlayer.ended();
            verify(!reader.isPlaying);
        }

        function test_file_engine_error() {
            root.config = {"voiceTtsEngine": "remote"};
            reader.speak("Hello.");
            tryVerify(function() { return root.pendingCallbacks.length === 1; }, 3000);
            fileReply(0, {"ok": false, "error": "the server can't be reached"});
            compare(root.errors, ["the server can't be reached"]);
            verify(!reader.isPlaying);
        }

        function findSpeech() {
            for (var i = 0; i < reader.children.length; i++) {
                var loader = reader.children[i];
                if (loader.item && loader.item.engine !== undefined)
                    return loader.item;
            }
            fail("no file engine loaded");
        }
    }
}
