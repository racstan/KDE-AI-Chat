// Read aloud (voice/ReadAloud.qml) with Qt's mock speech engine standing in
// for System voices, and with a file engine whose helper and player are fakes:
// it stays "playing" until the engine has really finished, stop is final,
// pause/resume, chunks play in order one synthesis ahead, errors reach the
// error signal and played files are removed. The system voice says its
// chunks one after another (no restarts, finished only after the last); the
// natural voice reads a sentence at a time, two sentences ahead, with the
// next file preloaded; while it isn't installed the system voice reads.
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

    Component {
        id: qtSpeechComponent
        Voice.QtSpeech { plugin: "mock" }
    }

    QtObject {
        id: fakePlayer
        property var preloaded: []
        function preload(path) { preloaded.push(path); }
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
            fakePlayer.played = [];
            fakePlayer.preloaded = [];
        }

        function test_system_voice_says_chunks_one_after_another() {
            var speech = qtSpeechComponent.createObject(root);
            var events = [];
            speech.chunkStarted.connect(function(text) { events.push("start " + text); });
            speech.finished.connect(function() { events.push("finished"); });
            speech.start(["One two three.", "Four five six.", "Seven."], {});
            compare(events, ["start One two three."], "only the first chunk is said at first");
            tryVerify(function() { return events.length >= 2; }, 10000);
            compare(events[1], "start Four five six.");
            tryVerify(function() { return events.indexOf("finished") >= 0; }, 15000);
            compare(events, ["start One two three.", "start Four five six.", "start Seven.", "finished"],
                    "each chunk once, in order, finished once after the last");
            speech.destroy();
        }

        function test_system_voice_stop_says_nothing_more() {
            var speech = qtSpeechComponent.createObject(root);
            var events = [];
            speech.chunkStarted.connect(function(text) { events.push(text); });
            speech.finished.connect(function() { events.push("finished"); });
            speech.start(["One two three four five six.", "Never said."], {});
            wait(100);
            speech.stop();
            wait(1500);
            compare(events, ["One two three four five six."]);
            speech.destroy();
        }

        function test_reply_is_one_utterance_for_the_system_voice() {
            reader.speak("First sentence. Second sentence! Third one?");
            tryVerify(function() { return reader.currentChunk !== ""; }, 3000);
            compare(reader.currentChunk, "First sentence. Second sentence! Third one?", "not restarted per sentence or word");
            reader.stop();
        }

        function test_removed_engines_read_with_speech_note() {
            var gone = ["neural", "kokoro", "flite", "piper", "command"];
            for (var i = 0; i < gone.length; i++) {
                root.config = {"voiceTtsEngine": gone[i]};
                verify(reader.speak("Hello there, this is read anyway."), gone[i]);
                compare(reader.engineId, "speechnote", gone[i]);
                reader.stop();
            }
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
            root.config = {"voiceTtsEngine": "remote", "voiceTtsRemoteUrl": "http://localhost:8880/v1", "voiceTtsRemoteSpeed": 1.2};
            var long = [];
            for (var i = 0; i < 40; i++)
                long.push("Sentence number " + i + " is here.");
            reader.speak(long.join(" "));
            tryVerify(function() { return !!reader.children.length && root.pendingCallbacks.length === 1; }, 3000);
            compare(reader.statusText, "Generating speech...");
            var payload = root.pendingCallbacks[0].payload;
            compare(payload.engine, "remote");
            compare(payload.options.voiceTtsRemoteUrl, "http://localhost:8880/v1");
            compare(payload.options.voiceTtsRemoteSpeed, 1.2);
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
            root.config = {"voiceTtsEngine": "remote"};
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
