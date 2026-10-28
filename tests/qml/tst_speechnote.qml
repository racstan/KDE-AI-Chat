// Dictation and read aloud through Speech Note, the real VoiceManager with a
// fake helper (no Speech Note, microphone or sound is ever touched): the mic
// button starts listening, the keepalive runs while listening, stop puts the
// text in the message box, Esc cancels; Speech Note's error codes become short
// plain messages; read aloud sends the whole reply as one request, then Stop,
// Pause and Resume work and reading ends when the wait returns; when Speech
// Note is not installed the system voice (Qt's mock engine) reads instead.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui
import "../../org.kde.plasma.kdeaichat/contents/ui/voice" as Voice

Item {
    id: root
    width: 200
    height: 100

    property QtObject plasmoid: QtObject {
        property QtObject configuration: QtObject {
            property bool sttEnabled: true
            property bool voiceTtsEnabled: true
            property bool voiceTtsAuto: false
            property bool voiceAutoSend: true
            property string sttEngine: "speechnote"
            property string sttSpeechNoteModel: ""
            property string voiceTtsEngine: "speechnote"
            property string voiceTtsSpeechNoteModel: ""
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    // What the fake Speech Note answers: command -> reply object, or "hold" to answer later with release().
    property var script: ({})
    property var calls: []
    property var held: []
    function fakeHelper(command, payload, done) {
        calls.push({"command": command, "payload": payload});
        var reply = script[command];
        if (reply === "hold") {
            held.push({"command": command, "done": done});
            return;
        }
        if (done)
            done(JSON.stringify(reply === undefined ? {"type": "ok"} : reply), 0, "");
    }
    function release(command, reply) {
        for (var i = 0; i < held.length; i++) {
            if (held[i].command === command) {
                var item = held.splice(i, 1)[0];
                item.done(JSON.stringify(reply), 0, "");
                return true;
            }
        }
        return false;
    }
    function names() { return calls.map(function(c) { return c.command; }); }
    function last(command) {
        for (var i = calls.length - 1; i >= 0; i--)
            if (calls[i].command === command)
                return calls[i].payload;
        return null;
    }
    function error(code) { return {"type": "speechnote_error", "error": "x", "code": code}; }

    Ui.VoiceManager {
        id: voice
        runHelper: root.fakeHelper
        waitHelper: root.fakeHelper
        ttsPluginOverride: ({"system": "mock"})
    }

    Component {
        id: dictationComponent
        Voice.SpeechNoteDictation {
            runHelper: root.fakeHelper
            keepAliveMs: 40
            configuration: root.plasmoid.configuration
        }
    }

    Component {
        id: warmComponent
        Voice.SpeechNoteWarm {
            runHelper: root.fakeHelper
        }
    }

    SignalSpy { id: recognized; target: voice; signalName: "textRecognized" }
    SignalSpy { id: errors; target: voice; signalName: "errorOccurred" }

    TestCase {
        name: "SpeechNote"
        when: windowShown

        function init() {
            root.calls = [];
            root.held = [];
            root.script = {"speechnote_listen_start": {"type": "speechnote_listening", "task": 7},
                           "speechnote_listen_stop": {"type": "speechnote_text", "text": "hello world", "lang": "en", "task": 7},
                           "speechnote_keepalive": {"type": "speechnote_keepalive", "task": 7, "alive": true},
                           "speechnote_speak": {"type": "speechnote_speaking", "task": 11},
                           "speechnote_wait_spoken": "hold"};
            recognized.clear();
            errors.clear();
            voice.stopTTS();
            voice.isRecording = false;
            voice.sttStatusText = "";
            plasmoid.configuration.sttSpeechNoteModel = "";
            plasmoid.configuration.voiceTtsSpeechNoteModel = "";
            plasmoid.configuration.voiceTtsEngine = "speechnote";
        }

        // --- dictation ---

        function test_mic_starts_listening_and_stop_gives_the_text() {
            plasmoid.configuration.sttSpeechNoteModel = "whisper-en";
            voice.startRecording();
            verify(voice.isRecording);
            compare(root.last("speechnote_listen_start").model, "whisper-en", "the chosen model");
            compare(voice.statusText, "Listening — speak now");
            voice.stopRecording();
            compare(voice.statusText, "", "stopped and answered at once by the fake");
            compare(root.last("speechnote_listen_stop").task, 7);
            compare(recognized.count, 1);
            compare(recognized.signalArguments[0][0], "hello world");
            verify(!voice.isRecording);
            compare(errors.count, 0);
            compare(root.names().indexOf("stt_dictate"), -1, "the widget's own recorder is not used");
        }

        function test_status_says_starting_until_speech_note_answers() {
            root.script["speechnote_listen_start"] = "hold";
            voice.startRecording();
            compare(voice.statusText, "Starting Speech Note… please wait");
            root.release("speechnote_listen_start", {"type": "speechnote_listening", "task": 7});
            compare(voice.statusText, "Listening — speak now");
            voice.cancelRecording();
        }

        function test_stop_pressed_while_starting_stops_once_it_has_started() {
            root.script["speechnote_listen_start"] = "hold";
            voice.startRecording();
            voice.stopRecording();
            compare(root.names().indexOf("speechnote_listen_stop"), -1);
            root.release("speechnote_listen_start", {"type": "speechnote_listening", "task": 7});
            compare(root.last("speechnote_listen_stop").task, 7);
            compare(recognized.count, 1);
        }

        function test_escape_cancels_and_gives_no_text() {
            voice.startRecording();
            voice.cancelRecording();
            compare(root.last("speechnote_listen_cancel").task, 7);
            compare(root.names().indexOf("speechnote_listen_stop"), -1);
            verify(!voice.isRecording);
            compare(voice.statusText, "");
            compare(recognized.count, 0);
        }

        function test_cancel_while_starting_gives_the_microphone_back() {
            root.script["speechnote_listen_start"] = "hold";
            voice.startRecording();
            voice.cancelRecording();
            verify(!voice.isRecording);
            root.release("speechnote_listen_start", {"type": "speechnote_listening", "task": 9});
            compare(root.last("speechnote_listen_cancel").task, 9);
        }

        function test_silence_gives_no_text_and_no_error() {
            root.script["speechnote_listen_stop"] = {"type": "speechnote_text", "text": "", "lang": "", "task": 7};
            voice.startRecording();
            voice.stopRecording();
            compare(recognized.count, 0);
            compare(errors.count, 0);
            verify(!voice.isRecording);
        }

        function test_the_keepalive_runs_while_listening_and_stops_after() {
            var dictation = createTemporaryObject(dictationComponent, root);
            var replies = [];
            dictation.reply.connect(function(data) { replies.push(data); });
            root.script["speechnote_listen_start"] = {"type": "speechnote_listening", "task": 5};
            dictation.start();
            compare(dictation.phase, "listening");
            tryVerify(function() { return root.names().filter(function(n) { return n === "speechnote_keepalive"; }).length >= 2; }, 3000);
            compare(root.last("speechnote_keepalive").task, 5);
            dictation.stop(false);
            var seen = root.names().length;
            wait(150);
            compare(root.names().length, seen, "no keepalive once stopped");
            compare(replies.length, 1);
            compare(replies[0].type, "stt_result");
        }

        function test_a_task_speech_note_ended_is_reported() {
            var dictation = createTemporaryObject(dictationComponent, root);
            var replies = [];
            dictation.reply.connect(function(data) { replies.push(data); });
            dictation.start();
            root.script["speechnote_keepalive"] = {"type": "speechnote_keepalive", "task": 7, "alive": false};
            tryVerify(function() { return replies.length === 1; }, 3000);
            compare(replies[0].type, "stt_error");
            verify(!dictation.busy);
        }

        function test_error_codes_become_plain_messages() {
            var cases = {"not_installed": "Speech Note is not installed — see Settings → Voice",
                         "mic_error": "Speech Note could not use the microphone",
                         "not_configured": "Speech Note has no speech model yet — add one in Speech Note",
                         "service_failed_to_start": "Speech Note could not start"};
            for (var code in cases) {
                errors.clear();
                root.script["speechnote_listen_start"] = root.error(code);
                voice.startRecording();
                compare(errors.count, 1, code);
                compare(errors.signalArguments[0][0], cases[code]);
                verify(!voice.isRecording, code);
                compare(voice.statusText, "");
            }
            // An error after the stop (the engine failing) too.
            errors.clear();
            root.script["speechnote_listen_start"] = {"type": "speechnote_listening", "task": 7};
            root.script["speechnote_listen_stop"] = root.error("mic_error");
            voice.startRecording();
            voice.stopRecording();
            compare(errors.signalArguments[0][0], "Speech Note could not use the microphone");
            verify(!voice.isRecording);
        }

        // --- warm-up and keeping it ready ---

        function warm(config, open) {
            return createTemporaryObject(warmComponent, root, {"configuration": config, "popupOpen": open === true});
        }
        function count(command) { return root.names().filter(function(n) { return n === command; }).length; }

        function test_opening_the_popup_starts_speech_note_once_in_the_background() {
            var w = warm({"sttEnabled": true, "sttEngine": "speechnote", "speechNoteKeepReadyMinutes": 0});
            compare(count("speechnote_start"), 0, "closed: nothing");
            w.popupOpen = true;
            compare(count("speechnote_start"), 1);
            wait(120);
            compare(count("speechnote_start"), 1, "once per opening");
            compare(count("speechnote_keepalive_service"), 0, "0 minutes: only when used");
            w.popupOpen = false;
            w.popupOpen = true;
            compare(count("speechnote_start"), 2, "again on the next opening");
        }

        function test_it_is_not_started_when_the_feature_or_engine_is_off() {
            warm({"sttEnabled": false, "voiceTtsEnabled": false, "sttEngine": "speechnote"}, true);
            warm({"sttEnabled": true, "sttEngine": "remote", "voiceTtsEnabled": true, "voiceTtsEngine": "system"}, true);
            wait(120);
            compare(root.calls.length, 0);
        }

        function test_read_aloud_alone_also_warms_it_up() {
            warm({"sttEnabled": false, "voiceTtsEnabled": true, "voiceTtsEngine": "speechnote"}, true);
            compare(count("speechnote_start"), 1);
        }

        function test_the_service_is_kept_alive_while_open_and_for_the_set_minutes_after() {
            var w = warm({"sttEnabled": true, "sttEngine": "speechnote", "speechNoteKeepReadyMinutes": 3}, true);
            w.tickMs = 30;
            w.minuteMs = 50;   // 3 "minutes" = 150 ms
            w.popupOpen = false;
            w.popupOpen = true;
            tryVerify(function() { return count("speechnote_keepalive_service") >= 3; }, 3000);
            verify(w.keeping);
            w.popupOpen = false;
            verify(w.keeping, "still ready after closing");
            tryVerify(function() { return !w.keeping; }, 3000, "stops when the time is up");
            var seen = count("speechnote_keepalive_service");
            wait(150);
            compare(count("speechnote_keepalive_service"), seen, "no more calls");
            compare(count("speechnote_start"), 2, "keeping alive never starts it itself");
        }

        // --- read aloud ---

        function test_the_whole_reply_is_one_request_then_the_end_stops_reading() {
            plasmoid.configuration.voiceTtsSpeechNoteModel = "piper-en";
            voice.playTTS("First sentence. Second one!\n\nA third with `code`.");
            verify(voice.isPlaying);
            var speak = root.last("speechnote_speak");
            verify(speak.text.indexOf("First sentence.") === 0 && speak.text.indexOf("Second one!") > 0, speak.text);
            compare(speak.model, "piper-en");
            compare(root.names().filter(function(n) { return n === "speechnote_speak"; }).length, 1, "one request, not one per sentence");
            compare(root.last("speechnote_wait_spoken").task, 11);
            compare(voice.statusText, "Reading aloud...");
            verify(voice.ttsCanPause);
            verify(root.release("speechnote_wait_spoken", {"type": "speechnote_spoken", "task": 11}));
            verify(!voice.isPlaying, "reading ends when the wait returns");
            compare(voice.playingText, "");
            compare(errors.count, 0);
        }

        function test_each_sentence_speech_note_starts_is_the_current_chunk() {
            voice.playTTS("First sentence. Second one!");
            verify(root.last("speechnote_wait_spoken").sentences, "asks to hear about sentences");
            verify(root.release("speechnote_wait_spoken", {"type": "speechnote_sentence", "task": 11, "text": "First sentence."}));
            compare(voice.currentPlayingChunk, "First sentence.");
            verify(voice.isPlaying, "still reading: it waits again");
            verify(root.release("speechnote_wait_spoken", {"type": "speechnote_sentence", "task": 11, "text": "Second one!"}));
            compare(voice.currentPlayingChunk, "Second one!");
            verify(root.release("speechnote_wait_spoken", {"type": "speechnote_spoken", "task": 11}));
            verify(!voice.isPlaying);
            compare(errors.count, 0);
        }

        function test_stop_pause_and_resume() {
            voice.playTTS("Something to read. More of it.");
            voice.pauseTTS();
            compare(root.last("speechnote_pause").task, 11);
            verify(voice.ttsPaused);
            compare(voice.statusText, "Paused");
            voice.resumeTTS();
            compare(root.last("speechnote_resume").task, 11);
            verify(!voice.ttsPaused);
            voice.stopTTS();
            compare(root.last("speechnote_stop").task, 11);
            verify(!voice.isPlaying);
            // The wait that is still out answers late: it changes nothing.
            root.release("speechnote_wait_spoken", {"type": "speechnote_spoken", "task": 11});
            verify(!voice.isPlaying);
            compare(errors.count, 0);
        }

        function test_reading_a_new_text_replaces_the_old_one() {
            voice.playTTS("One text here.");
            root.script["speechnote_speak"] = {"type": "speechnote_speaking", "task": 12};
            voice.playTTS("Another text here.");
            compare(root.last("speechnote_stop").task, 11, "the first is stopped");
            compare(root.last("speechnote_speak").text, "Another text here.");
            verify(voice.isPlaying);
            root.release("speechnote_wait_spoken", {"type": "speechnote_spoken", "task": 11});
            verify(voice.isPlaying, "the old wait ending does not end the new reading");
            voice.stopTTS();
        }

        function test_starting_status_until_the_speech_begins() {
            root.script["speechnote_speak"] = "hold";
            voice.playTTS("Wait for it.");
            compare(voice.statusText, "Starting Speech Note...");
            root.release("speechnote_speak", {"type": "speechnote_speaking", "task": 11});
            compare(voice.statusText, "Reading aloud...");
            voice.stopTTS();
        }

        function test_without_speech_note_the_system_voice_reads() {
            root.script["speechnote_speak"] = root.error("not_installed");
            voice.playTTS("Hello there, this is read anyway.");
            tryVerify(function() { return voice.isPlaying && voice.currentPlayingChunk !== ""; }, 3000);
            compare(errors.count, 0, "no error: the system voice reads");
            tryVerify(function() { return !voice.isPlaying; }, 15000);
            compare(errors.count, 0);
        }

        function test_no_voice_in_speech_note_is_an_error_not_a_fallback() {
            root.script["speechnote_speak"] = root.error("not_configured");
            voice.playTTS("Hello there.");
            tryCompare(errors, "count", 1, 3000);
            compare(errors.signalArguments[0][0], "Speech Note has no speech model yet — add one in Speech Note");
            verify(!voice.isPlaying);
        }
    }
}
