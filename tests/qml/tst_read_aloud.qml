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

        function test_natural_voice_pipelines_sentences() {
            root.config = {"voiceTtsEngine": "neural", "voiceTtsNeuralVoice": "bf_emma", "voiceTtsNeuralSpeed": 1.1};
            reader.speak("The first sentence is here. The second one follows. A third one ends it. And a fourth.");
            tryVerify(function() { return root.pendingCallbacks.length === 1; }, 3000);
            var speech = findSpeech();
            compare(speech.ahead, 2);
            speech.player = fakePlayer;
            var payload = root.pendingCallbacks[0].payload;
            compare(payload.engine, "neural");
            compare(payload.text, "The first sentence is here.", "the first sentence alone, so sound starts soon");
            compare(payload.options.voiceTtsNeuralVoice, "bf_emma");
            fileReply(0, {"ok": true, "path": "/run/1.wav"});
            compare(fakePlayer.played, ["/run/1.wav"]);
            compare(reader.currentChunk, "The first sentence is here.");
            compare(root.pendingCallbacks.length, 2);
            compare(root.pendingCallbacks[1].payload.text, "The second one follows.");
            fileReply(1, {"ok": true, "path": "/run/2.wav"});
            compare(fakePlayer.preloaded, ["/run/2.wav"], "the next sentence is loaded while one plays");
            compare(root.pendingCallbacks.length, 3, "two sentences ahead");
            fileReply(2, {"ok": true, "path": "/run/3.wav"});
            compare(root.pendingCallbacks.length, 3, "not more than two ahead");
            reader.pause();
            compare(fakePlayer.state, "paused");
            compare(reader.statusText, "Paused");
            reader.resume();
            fakePlayer.ended();
            compare(fakePlayer.played, ["/run/1.wav", "/run/2.wav"]);
            compare(fakePlayer.preloaded, ["/run/2.wav", "/run/3.wav"]);
            compare(root.pendingCallbacks.length, 4);
            fileReply(3, {"ok": true, "path": "/run/4.wav"});
            fakePlayer.ended();
            fakePlayer.ended();
            verify(reader.isPlaying, "still playing the last sentence");
            fakePlayer.ended();
            verify(!reader.isPlaying);
            compare(fakePlayer.played, ["/run/1.wav", "/run/2.wav", "/run/3.wav", "/run/4.wav"]);
            compare(root.errors.length, 0);
        }

        function test_natural_voice_stop_is_final() {
            root.config = {"voiceTtsEngine": "neural"};
            reader.speak("One sentence here. Another sentence here.");
            tryVerify(function() { return root.pendingCallbacks.length === 1; }, 3000);
            findSpeech().player = fakePlayer;
            fileReply(0, {"ok": true, "path": "/run/a.wav"});
            reader.stop();
            compare(fakePlayer.state, "stopped");
            fileReply(1, {"ok": true, "path": "/run/b.wav"});
            compare(fakePlayer.played, ["/run/a.wav"]);
            verify(!reader.isPlaying);
        }

        function test_without_the_natural_voice_the_system_voice_reads() {
            root.config = {"voiceTtsEngine": "neural"};
            reader.speak("Hello there, this is read anyway.");
            tryVerify(function() { return root.pendingCallbacks.length === 1; }, 3000);
            fileReply(0, {"ok": false, "error": "the natural voice is not installed", "code": "not_installed"});
            tryCompare(reader, "engineId", "system", 3000);
            verify(reader.usedFallback);
            verify(reader.isPlaying);
            tryVerify(function() { return !reader.isPlaying; }, 15000);
            compare(root.errors.length, 0, "no error: the system voice read it");
            reader.speak("Again.");
            compare(reader.engineId, "neural", "the natural voice is tried again next time");
            reader.stop();
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
