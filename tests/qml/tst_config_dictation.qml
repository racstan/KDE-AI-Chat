// Settings → Voice, dictation part, with a fake helper: the engine list holds
// Speech Note (the default) and the speech server only; an engine of an earlier
// build (faster-whisper, Parakeet, whisper.cpp, custom command) shows as Speech
// Note; Test sends the bundled recording with the page's choices to the speech
// server; nothing is installed, downloaded or started through the helper; the
// speech server's key is never a setting. Also the screenshots of the page,
// wide and at 480 px.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

Item {
    id: root
    width: 1100
    height: 1400

    property QtObject plasmoid: QtObject {
        property string id: ""
        property QtObject configuration: QtObject {}
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property var calls: []
    function commands() { return calls.map(function(c) { return c.command; }); }
    function last(command) {
        for (var i = calls.length - 1; i >= 0; i--)
            if (calls[i].command === command)
                return calls[i].payload;
        return null;
    }
    function reply(command, payload) {
        switch (command) {
        case "speechnote_status":
            return {"type": "speechnote_status", "installed": true, "kind": "flatpak", "running": false, "state": 0,
                    "ready": true, "models_known": true, "default_stt_model": "", "default_tts_lang": "en",
                    "stt_models": [{"id": "stt.whisper_base_en", "name": "English Whisper Base / English", "lang": "en"}],
                    "tts_models": [{"id": "tts.piper_amy", "name": "English Piper Amy / English", "lang": "en"}]};
        case "stt_test":
            return {"type": "stt_result", "text": "Hello, this is a speech test.", "seconds": 1.2};
        }
        return {"type": command};
    }
    function fakeHelper(command, payload, onDone) {
        calls.push({"command": command, "payload": JSON.parse(JSON.stringify(payload || {}))});
        var data = reply(command, payload || {});
        if (onDone)
            Qt.callLater(function() { onDone(JSON.stringify(data), 0, ""); });
    }

    Rectangle { anchors.fill: parent; color: "white" }

    HarnessTestCase {
        id: testCase
        name: "ConfigDictation"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open(cfg, width) {
            var component = Qt.createComponent(uiDir + "ConfigVoice.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": width || root.width, "height": root.height,
                "runHelper": root.fakeHelper, "walletCall": function(member, args, onReply, onError) { onError("no wallet in tests"); },
                "pluginOverride": {"system": "mock"}, "cfg_sttEnabled": true}, cfg || {}));
            verify(page !== null);
            tryVerify(function() { return engineCombo().count > 0; }, 3000);
            wait(50);
            return page;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            root.calls = [];
            wait(100);
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
        function engineCombo() { return named("sttEngineCombo"); }
        function values(combo) {
            var out = [];
            for (var i = 0; i < combo.count; i++)
                out.push(combo.model[i].value);
            return out;
        }
        function chooseEngine(id) {
            var combo = engineCombo();
            combo.currentIndex = combo.indexOfValue(id);
            combo.activated(combo.currentIndex);
            wait(50);
        }

        function test_1_only_speech_note_and_the_speech_server() {
            open({});
            compare(values(engineCombo()), ["speechnote", "remote"]);
            compare(engineCombo().currentValue, "speechnote", "Speech Note is the default");
            verify(named("speechNoteDictation").visible, "Speech Note's panel");
            verify(!named("sttTestButton").visible && !named("sttLanguageCombo").visible, "the server's rows are hidden");
            verify(!named("ttsOption-sttRemoteUrl") || !named("ttsOption-sttRemoteUrl").visible);
            tryVerify(function() { return root.commands().indexOf("speechnote_status") >= 0; }, 3000);
            wait(200);
            // Nothing is installed, downloaded, probed or started for dictation.
            var allowed = ["speechnote_status"];
            for (var i = 0; i < root.commands().length; i++)
                verify(allowed.indexOf(root.commands()[i]) >= 0, "unexpected helper command " + root.commands()[i]);
            screenshot(page, "config-dictation-speechnote");
        }

        function test_2_engines_of_earlier_builds_show_as_speech_note() {
            var gone = ["faster-whisper", "parakeet", "whisper-cpp", "command"];
            for (var i = 0; i < gone.length; i++) {
                open({"cfg_sttEngine": gone[i]});
                compare(engineCombo().currentValue, "speechnote", gone[i]);
                verify(named("speechNoteDictation").visible, gone[i]);
                page.destroy();
                page = null;
            }
        }

        function test_3_speech_server_options_and_test() {
            open({"cfg_sttEngine": "remote"});
            verify(!named("speechNoteDictation").visible);
            var button = named("sttTestButton");
            verify(button.visible);
            verify(!button.enabled, "no address yet");
            var url = named("ttsOption-sttRemoteUrl");
            verify(url.visible && named("ttsOption-sttRemoteModel").visible);
            verify(named("ttsSecretField") !== null, "the key field is shown");
            var field = url.item.children[0];
            field.text = "http://localhost:8000/v1";
            field.textEdited();
            compare(page.cfg_sttRemoteUrl, "http://localhost:8000/v1");
            tryVerify(function() { return button.enabled; }, 2000);
            button.clicked();
            tryVerify(function() { return named("sttTestResult").text.indexOf("Hello, this is a speech test.") >= 0; }, 2000);
            var payload = root.last("stt_test");
            compare(payload.sttEngine, "remote");
            compare(payload.sttRemoteUrl, "http://localhost:8000/v1");
            compare(payload.sttLanguage, "auto");
            verify(JSON.stringify(payload).toLowerCase().indexOf("key") < 0, "no key in the payload");
            var combo = named("sttLanguageCombo");
            combo.currentIndex = combo.indexOfValue("de");
            combo.activated(combo.currentIndex);
            compare(page.cfg_sttLanguage, "de");
            screenshot(page, "config-dictation-server");
        }

        function test_4_no_key_or_removed_engine_setting_on_the_page() {
            open({"cfg_sttEngine": "remote"});
            for (var name in page) {
                if (name.indexOf("cfg_") !== 0)
                    continue;
                verify(!/apikey|key$|token|password|secret/i.test(name), name + " would be saved by the settings dialog");
                verify(!/Parakeet|Whisper|Neural|Kokoro|Flite|Piper|Command|Device|IdleMinutes|sttModel/.test(name), name + " belongs to a removed engine");
            }
            root.calls = [];
            if (page.saveConfig)
                page.saveConfig();
            compare(root.commands(), [], "saving starts and installs nothing");
        }

        function test_5_screenshots_wide_and_narrow() {
            open({"cfg_voiceTtsEnabled": true, "cfg_voiceTtsEngine": "system"});
            wait(400);
            screenshot(page, "config-voice-both-on");
            page.cfg_sttEngine = "remote";
            wait(300);
            screenshot(page, "config-voice-both-on-server");
            page.destroy();
            page = null;
            open({"cfg_voiceTtsEnabled": true, "cfg_voiceTtsEngine": "remote", "cfg_sttEngine": "remote"}, 480);
            wait(400);
            screenshot(page, "config-voice-narrow");
            verify(page.width <= 480);
        }
    }
}
