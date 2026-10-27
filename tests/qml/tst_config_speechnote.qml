// Settings → Voice with the Speech Note engine (the default for dictation and
// read aloud), with a fake helper: installed with models (the pickers list
// "Speech Note's default" and each model, a choice is a setting), not
// installed (links to Flathub and GitHub, one line on how to set up, Say Hello
// reads with the system voice and says so), installed but no model, and a
// service that fails to start. Every state has the credit line. Screenshots
// wide and 480 px narrow.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

Item {
    id: root
    width: 820
    height: 1100

    property QtObject plasmoid: QtObject {
        property string id: ""
        property QtObject configuration: QtObject {}
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    // The fake Speech Note: "installed" | "missing" | "nomodels" | "failing"
    property string scenario: "installed"
    property var calls: []
    function names() { return calls.map(function(c) { return c.command; }); }
    function status() {
        if (scenario === "missing")
            return {"type": "speechnote_error", "error": "Speech Note is not installed", "code": "not_installed"};
        if (scenario === "failing")
            return {"type": "speechnote_error", "error": "Speech Note did not start in time", "code": "service_failed_to_start"};
        var stt = scenario === "nomodels" ? [] : [{"id": "stt.whisper_base_en", "name": "English Whisper Base / English", "lang": "en"},
                                                   {"id": "stt.whisper_small_de", "name": "German Whisper Small", "lang": "de"}];
        var tts = scenario === "nomodels" ? [] : [{"id": "tts.piper_amy", "name": "English Piper Amy / English", "lang": "en"},
                                                   {"id": "tts.piper_thorsten", "name": "German Piper Thorsten", "lang": "de"}];
        return {"type": "speechnote_status", "installed": true, "kind": "flatpak", "running": true, "state": 3, "ready": true,
                "models_known": true, "stt_models": stt, "tts_models": tts, "default_stt_model": "", "default_tts_model": "",
                "default_stt_lang": "", "default_tts_lang": ""};
    }
    function fakeHelper(command, payload, onDone) {
        calls.push({"command": command, "payload": payload});
        var reply = {"type": "ok"};
        if (command === "speechnote_status")
            reply = status();
        else if (command === "speechnote_speak")
            reply = scenario === "missing" ? {"type": "speechnote_error", "error": "x", "code": "not_installed"}
                                           : {"type": "speechnote_speaking", "task": 4};
        else if (command === "speechnote_wait_spoken")
            return;   // reading goes on until stopped
        if (onDone)
            onDone(JSON.stringify(reply), 0, "");
    }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    HarnessTestCase {
        id: testCase
        name: "ConfigSpeechNote"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open(scenario, width, cfg) {
            root.scenario = scenario;
            root.width = width || 820;
            var component = Qt.createComponent(uiDir + "ConfigVoice.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": root.width, "height": root.height,
                "runHelper": root.fakeHelper, "waitHelper": root.fakeHelper, "walletCall": function(member, args, onReply, onError) { onError("no wallet in tests"); },
                "pluginOverride": {"system": "mock"},
                "cfg_voiceTtsEnabled": true, "cfg_sttEnabled": true}, cfg || {}));
            verify(page !== null);
            return page;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            root.calls = [];
            wait(200);
        }
        // The voice engines have been looked up (the Say Hello button is usable).
        function settled() { tryVerify(function() { return findChild(page, "ttsTestButton").enabled; }, 5000); }
        function panel(name) { return findChild(page, name); }
        function field(panelName, name) { return findChild(panel(panelName), name); }
        function modelValues(combo) {
            var out = [];
            for (var i = 0; i < combo.count; i++)
                out.push(combo.model[i].value);
            return out;
        }

        function test_defaults_are_speech_note_for_both() {
            open("installed");
            compare(page.cfg_voiceTtsEngine, "speechnote");
            compare(page.cfg_sttEngine, "speechnote");
            compare(page.cfg_sttSpeechNoteModel, "");
            compare(page.cfg_voiceTtsSpeechNoteModel, "");
            tryVerify(function() { return findChild(page, "ttsEngineCombo").count > 0; }, 5000);
            compare(findChild(page, "ttsEngineCombo").currentValue, "speechnote");
            tryCompare(findChild(page, "sttEngineCombo"), "currentValue", "speechnote", 5000);
        }

        function test_installed_with_models() {
            open("installed");
            var tts = "speechNoteReadAloud";
            var stt = "speechNoteDictation";
            tryCompare(field(tts, "speechNoteStatus"), "text", "Installed (Flatpak).", 5000);
            compare(field(stt, "speechNoteStatus").text, "Installed (Flatpak).");
            verify(!field(tts, "speechNoteLinks").visible, "no install links when it is installed");
            verify(!field(tts, "speechNoteSetup").visible);
            var sttCombo = field(stt, "speechNoteSttModel");
            var ttsCombo = field(tts, "speechNoteTtsModel");
            verify(sttCombo.visible && ttsCombo.visible);
            compare(modelValues(sttCombo), ["", "stt.whisper_base_en", "stt.whisper_small_de"]);
            compare(sttCombo.model[0].text, "Speech Note's default");
            compare(sttCombo.model[1].text, "English Whisper Base / English");
            compare(sttCombo.model[2].text, "German Whisper Small (de)", "a name without its language gets it");
            compare(ttsCombo.model[2].text, "German Piper Thorsten (de)");
            compare(sttCombo.currentIndex, 0);
            sttCombo.currentIndex = 2;
            sttCombo.activated(2);
            compare(page.cfg_sttSpeechNoteModel, "stt.whisper_small_de");
            ttsCombo.currentIndex = 1;
            ttsCombo.activated(1);
            compare(page.cfg_voiceTtsSpeechNoteModel, "tts.piper_amy");
            verify(field(tts, "speechNoteCredit").text.indexOf("© Michał Kosciesza, MPL-2.0") > 0);
            verify(field(tts, "speechNoteCredit").text.indexOf("https://github.com/mkiol/dsnote") > 0);
            verify(!findChild(page, "sttTestButton").visible, "the bundled-recording test is not for this engine");
            verify(!findChild(page, "sttLanguageCombo").visible, "the language comes with the model");
            // The status is asked once per page, with the service started, for both parts.
            compare(root.names().filter(function(n) { return n === "speechnote_status"; }).length, 1);
            compare(root.calls.filter(function(c) { return c.command === "speechnote_status"; })[0].payload.start, true);
            settled();
            screenshot(page, "config-speechnote-installed");
        }

        function test_installed_narrow() {
            open("installed", 480);
            tryCompare(field("speechNoteReadAloud", "speechNoteStatus"), "text", "Installed (Flatpak).", 5000);
            settled();
            screenshot(page, "config-speechnote-installed-narrow");
        }

        function test_a_saved_model_that_is_gone_stays_listed() {
            open("installed", 820, {"cfg_voiceTtsSpeechNoteModel": "tts.removed"});
            tryCompare(field("speechNoteReadAloud", "speechNoteStatus"), "text", "Installed (Flatpak).", 5000);
            var combo = field("speechNoteReadAloud", "speechNoteTtsModel");
            compare(combo.currentValue, "tts.removed");
        }

        function test_not_installed_shows_how_to_get_it() {
            open("missing");
            var stt = "speechNoteDictation";
            tryCompare(field(stt, "speechNoteStatus"), "text", "Not installed.", 5000);
            verify(field(stt, "speechNoteSetup").visible);
            compare(field(stt, "speechNoteSetup").text, "Install Speech Note, then download a speech-to-text model in your language inside Speech Note.");
            var links = field(stt, "speechNoteLinks");
            verify(links.visible);
            verify(links.text.indexOf("https://flathub.org/apps/net.mkiol.SpeechNote") >= 0);
            verify(links.text.indexOf("https://github.com/mkiol/dsnote") >= 0);
            verify(!field(stt, "speechNoteSttModel").visible, "no model list without Speech Note");
            verify(field(stt, "speechNoteCredit").visible);
            verify(field("speechNoteReadAloud", "speechNoteSetup").text.indexOf("Until then the system voice reads.") > 0);
            settled();
            screenshot(page, "config-speechnote-missing");
        }

        function test_not_installed_narrow() {
            open("missing", 480);
            tryCompare(field("speechNoteDictation", "speechNoteStatus"), "text", "Not installed.", 5000);
            settled();
            screenshot(page, "config-speechnote-missing-narrow");
        }

        function test_say_hello_without_speech_note_uses_the_system_voice() {
            open("missing");
            tryCompare(field("speechNoteReadAloud", "speechNoteStatus"), "text", "Not installed.", 5000);
            var button = findChild(page, "ttsTestButton");
            tryVerify(function() { return button.enabled; }, 5000);
            button.clicked();
            tryCompare(findChild(page, "ttsTestResult"), "text",
                       "That was the system voice, because Speech Note is not installed: see the setup steps above.", 15000);
        }

        function test_say_hello_speaks_through_speech_note_and_stops() {
            open("installed", 820, {"cfg_voiceTtsSpeechNoteModel": "tts.piper_amy"});
            tryCompare(field("speechNoteReadAloud", "speechNoteStatus"), "text", "Installed (Flatpak).", 5000);
            var button = findChild(page, "ttsTestButton");
            button.clicked();
            compare(button.text, "Stop");
            var speak = root.calls.filter(function(c) { return c.command === "speechnote_speak"; })[0].payload;
            compare(speak.text, "Hello! This is how replies will sound.");
            compare(speak.model, "tts.piper_amy", "the page's unsaved choice, not the saved one");
            button.clicked();
            compare(button.text, "Say Hello");
            compare(root.calls.filter(function(c) { return c.command === "speechnote_stop"; })[0].payload.task, 4);
        }

        function test_installed_without_models_says_to_add_one() {
            open("nomodels");
            var tts = "speechNoteReadAloud";
            tryCompare(field(tts, "speechNoteStatus"), "text", "Installed (Flatpak).", 5000);
            verify(field(tts, "speechNoteSetup").visible);
            verify(field(tts, "speechNoteSetup").text.indexOf("download a voice") > 0);
            verify(field(tts, "speechNoteTtsModel").visible, "the default entry is still offered");
            compare(modelValues(field(tts, "speechNoteTtsModel")), [""]);
            verify(!field(tts, "speechNoteLinks").visible);
            settled();
            screenshot(page, "config-speechnote-nomodels");
        }

        function test_a_service_that_fails_to_start_is_explained() {
            open("failing");
            var stt = "speechNoteDictation";
            tryCompare(field(stt, "speechNoteStatus"), "text", "Installed. Speech Note could not start.", 5000);
            verify(!field(stt, "speechNoteSttModel").visible);
            verify(!field(stt, "speechNoteLinks").visible);
            verify(field(stt, "speechNoteRecheck").enabled, "Check again is offered");
            settled();
            screenshot(page, "config-speechnote-failing");
            root.scenario = "installed";
            field(stt, "speechNoteRecheck").clicked();
            tryCompare(field(stt, "speechNoteStatus"), "text", "Installed (Flatpak).", 5000);
            verify(field(stt, "speechNoteSttModel").visible);
        }

        function test_keep_ready_is_one_setting_shown_once() {
            open("installed");
            tryCompare(field("speechNoteDictation", "speechNoteStatus"), "text", "Installed (Flatpak).", 5000);
            compare(page.cfg_speechNoteKeepReadyMinutes, 5);
            var shown = testCase.findChildren(page, "speechNoteKeepReady").filter(function(i) { return i.visible; });
            compare(shown.length, 1, "with both on it is next to dictation");
            compare(shown[0].textFromValue(0), "Only when used");
            compare(shown[0].textFromValue(5), "5 min");
            shown[0].value = 15;
            shown[0].valueModified();
            compare(page.cfg_speechNoteKeepReadyMinutes, 15);
            page.cfg_sttEnabled = false;
            wait(50);
            shown = testCase.findChildren(page, "speechNoteKeepReady").filter(function(i) { return i.visible; });
            compare(shown.length, 1, "with dictation off it is next to read aloud");
        }

        function test_the_switches_off_ask_nothing() {
            open("installed", 820, {"cfg_voiceTtsEnabled": false, "cfg_sttEnabled": false});
            wait(500);
            compare(root.names().indexOf("speechnote_status"), -1, "Speech Note is not started while both are off");
        }
    }
}
