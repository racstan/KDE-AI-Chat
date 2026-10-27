// Settings → Voice, read-aloud part, with Qt's mock speech engine standing in
// for System voices and a fake helper: both switches off by default and
// nothing else shown; the engine list holds Speech Note, the system voice and
// the speech server only (never Kokoro, Flite, Piper, the natural voice or a
// custom command); each engine's options are its own settings (kept when
// switching engines); the Say Hello test speaks and stops; the remote key never
// becomes a setting; Speech Note is the default, and a saved engine of an
// earlier build shows as Speech Note.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

Item {
    id: root
    width: 820
    height: 900

    property QtObject plasmoid: QtObject {
        property string id: ""
        property QtObject configuration: QtObject {
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property var helperCalls: []
    function fakeHelper(command, payload, onDone) {
        helperCalls.push(command);
        if (onDone)
            onDone(JSON.stringify({"ok": true}), 0, "");
    }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    HarnessTestCase {
        id: testCase
        name: "ConfigVoice"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open(cfg) {
            var component = Qt.createComponent(uiDir + "ConfigVoice.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": root.width, "height": root.height,
                "runHelper": root.fakeHelper, "walletCall": function(member, args, onReply, onError) { onError("no wallet in tests"); }, "pluginOverride": {"system": "mock"}}, cfg || {}));
            verify(page !== null);
            return page;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            root.helperCalls = [];
            wait(200);
        }
        function find(item, test) {
            if (!item)
                return null;
            if (test(item))
                return item;
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++) {
                var found = find(kids[i], test);
                if (found) return found;
            }
            return null;
        }
        function named(name) { return find(page, function(item) { return item.objectName === name; }); }
        function voiceProbe() { return find(page, function(item) { return item.hasOwnProperty("probing") && item.hasOwnProperty("available"); }); }
        function engineValues() {
            var combo = named("ttsEngineCombo");
            var out = [];
            for (var i = 0; i < combo.count; i++)
                out.push(combo.model[i].value);
            return out;
        }
        function chooseEngine(id) {
            var combo = named("ttsEngineCombo");
            combo.currentIndex = combo.indexOfValue(id);
            combo.activated(combo.currentIndex);
            wait(50);
        }
        function shownOption(key) {
            var row = named("ttsOption-" + key);
            return row && row.visible ? row : null;
        }

        function test_switches_are_off_and_nothing_runs() {
            open({});
            var read = named("readAloudSwitch");
            var dictation = named("dictationSwitch");
            compare(read.checked, false);
            compare(dictation.checked, false);
            verify(!named("ttsEngineCombo").visible, "no engine choice while read aloud is off");
            wait(600);
            compare(root.helperCalls.length, 0, "no probe while off");
            for (var name in page)
                if (name.indexOf("cfg_") === 0)
                    verify(!/apikey|key$|token|password|secret/i.test(name), name + " would be saved by the settings dialog");
            screenshot(page, "config-voice-switches");
        }

        function test_only_speech_note_the_system_voice_and_a_speech_server_are_listed() {
            open({"cfg_voiceTtsEnabled": true});
            tryVerify(function() { return named("ttsEngineCombo").count > 0 && !voiceProbe().probing; }, 5000);
            tryCompare(named("ttsEngineCombo"), "count", 3, 3000);
            compare(engineValues(), ["speechnote", "system", "remote"], "no Kokoro, Flite, Piper, natural voice or custom command");
            compare(named("ttsEngineCombo").currentText, "Speech Note (any language, recommended)", "Speech Note is the default");
            for (var i = 0; i < root.helperCalls.length; i++)
                compare(root.helperCalls[i], "speechnote_status", "only Speech Note's state is asked, nothing is installed or started");
            wait(100);
            screenshot(page, "config-voice-engines");
        }

        function test_a_saved_engine_of_an_earlier_build_shows_as_speech_note() {
            var gone = ["neural", "kokoro", "flite", "piper", "command"];
            for (var i = 0; i < gone.length; i++) {
                open({"cfg_voiceTtsEnabled": true, "cfg_voiceTtsEngine": gone[i]});
                tryVerify(function() { return named("ttsEngineCombo").count > 0 && !voiceProbe().probing; }, 5000);
                compare(page.engine.id, "speechnote", gone[i]);
                compare(named("ttsEngineCombo").currentText, "Speech Note (any language, recommended)", gone[i]);
                verify(named("speechNoteReadAloud").visible, gone[i]);
                page.destroy();
                page = null;
            }
        }

        function test_options_persist_per_engine() {
            open({"cfg_voiceTtsEnabled": true, "cfg_voiceTtsEngine": "system", "cfg_voiceTtsSystemVoice": ""});
            var probe = voiceProbe();
            tryCompare(probe, "probing", false, 5000);
            verify(shownOption("voiceTtsSystemLanguage"));
            verify(shownOption("voiceTtsSystemRate"));
            var voiceRow = shownOption("voiceTtsSystemVoice");
            verify(voiceRow);
            var voiceCombo = voiceRow.item;
            var names = [];
            for (var i = 0; i < voiceCombo.count; i++) names.push(voiceCombo.model[i].value);
            compare(names, ["", "Bob", "Anne"], "the mock engine's voices");
            voiceCombo.currentIndex = 2;
            voiceCombo.activated(2);
            compare(page.cfg_voiceTtsSystemVoice, "Anne");
            screenshot(page, "config-voice-tts");

            chooseEngine("remote");
            compare(page.cfg_voiceTtsEngine, "remote");
            verify(!shownOption("voiceTtsSystemVoice"));
            var url = shownOption("voiceTtsRemoteUrl").item.children[0];
            compare(url.text, "http://localhost:8880/v1");
            url.text = "http://127.0.0.1:9000/v1";
            url.textEdited();
            compare(page.cfg_voiceTtsRemoteUrl, "http://127.0.0.1:9000/v1");
            verify(named("ttsSecretField"), "the key field is shown");
            screenshot(page, "config-voice-tts-remote");

            chooseEngine("system");
            compare(page.cfg_voiceTtsSystemVoice, "Anne", "kept while another engine was picked");
            compare(shownOption("voiceTtsSystemVoice").item.currentText, "Anne");
        }

        function test_say_hello_speaks_and_stops() {
            open({"cfg_voiceTtsEnabled": true, "cfg_voiceTtsEngine": "system", "cfg_voiceTtsSystemVoice": "Bob"});
            var probe = voiceProbe();
            tryCompare(probe, "probing", false, 5000);
            var button = named("ttsTestButton");
            verify(button.enabled);
            compare(button.text, "Say Hello");
            button.clicked();
            compare(button.text, "Stop");
            tryCompare(named("ttsTestResult"), "text", "Finished.", 15000);
            compare(button.text, "Say Hello");
            button.clicked();
            compare(button.text, "Stop");
            button.clicked();
            compare(button.text, "Say Hello");
        }
    }
}
