// Settings → Voice, read-aloud part, with Qt's mock speech engine standing in
// for System voices and a fake helper: both switches off by default and
// nothing else shown; the engine list holds only engines that can run; each
// engine's options are its own settings (kept when switching engines); the
// Say Hello test speaks and stops; the remote key never becomes a setting;
// Speech Note is the default; the natural voice shows its install size before Install,
// and until it is installed Say Hello uses the system voice.
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

    property string piperPath: ""
    property var helperCalls: []
    property bool neuralInstalled: false
    property var installPayload: null
    function fakeHelper(command, payload, onDone) {
        helperCalls.push(command);
        if (command === "tts_probe" && onDone)
            onDone(JSON.stringify({"ok": true, "piper": piperPath}), 0, "");
        var size = neuralInstalled ? {"program_mb": 0, "gpu_mb": 0, "model_mb": 0, "total_mb": 0}
                                   : {"program_mb": 52, "gpu_mb": 0, "model_mb": 206, "total_mb": 258};
        if (command === "tts_neural_status" && onDone)
            onDone(JSON.stringify({"type": "tts_neural_status", "ok": true, "installed": neuralInstalled, "packages": neuralInstalled,
                                   "model": neuralInstalled ? "/m/kokoro.onnx" : "", "gpu": true, "gpu_installed": false,
                                   "venv": "/d/tts-venv", "models": "/d/tts-models/kokoro", "size": size,
                                   "size_gpu": {"program_mb": size.program_mb, "gpu_mb": 1554, "model_mb": size.model_mb, "total_mb": size.total_mb + 1554}}), 0, "");
        if (command === "tts_neural_install") {
            installPayload = payload;
            neuralInstalled = true;
            if (onDone) onDone(JSON.stringify({"type": "tts_neural_installed", "ok": true}), 0, "");
        }
        if (command === "tts_synthesize" && onDone)
            onDone(JSON.stringify({"ok": false, "error": "the natural voice is not installed", "code": "not_installed"}), 0, "");
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
                "runHelper": root.fakeHelper, "walletCall": function(member, args, onReply, onError) { onError("no wallet in tests"); }, "pluginOverride": {"system": "mock", "kokoro": "no-such-engine", "flite": "no-such-engine"}}, cfg || {}));
            verify(page !== null);
            return page;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            root.piperPath = "";
            root.helperCalls = [];
            root.neuralInstalled = false;
            root.installPayload = null;
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

        function test_only_available_engines_are_listed() {
            open({"cfg_voiceTtsEnabled": true});
            tryVerify(function() { return named("ttsEngineCombo").count > 0 && !page.children[0].probing; }, 5000);
            tryCompare(named("ttsEngineCombo"), "count", 5, 3000);
            compare(engineValues(), ["speechnote", "neural", "system", "remote", "command"], "no Kokoro or Flite plugin, no piper program");
            compare(named("ttsEngineCombo").currentText, "Speech Note (any language, recommended)", "Speech Note is the default");
            root.piperPath = "/usr/bin/piper";
            var probe = find(page, function(item) { return item.hasOwnProperty("piperPath"); });
            probe.refresh();
            tryCompare(probe, "probing", false, 3000);
            compare(engineValues(), ["speechnote", "neural", "system", "piper", "remote", "command"]);
        }

        function test_options_persist_per_engine() {
            open({"cfg_voiceTtsEnabled": true, "cfg_voiceTtsEngine": "system", "cfg_voiceTtsSystemVoice": ""});
            var probe = find(page, function(item) { return item.hasOwnProperty("piperPath"); });
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

            chooseEngine("command");
            var command = shownOption("voiceTtsCommand").item;
            command.children[0].text = "say 'oops";
            command.children[0].textEdited();
            compare(command.problem, "This command can't be used: check its quotes.");
        }

        function test_say_hello_speaks_and_stops() {
            open({"cfg_voiceTtsEnabled": true, "cfg_voiceTtsEngine": "system", "cfg_voiceTtsSystemVoice": "Bob"});
            var probe = find(page, function(item) { return item.hasOwnProperty("piperPath"); });
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
    
        function test_natural_voice_shows_its_size_and_the_system_voice_reads_until_installed() {
            open({"cfg_voiceTtsEnabled": true, "cfg_voiceTtsEngine": "neural"});
            var probe = find(page, function(item) { return item.hasOwnProperty("piperPath"); });
            tryCompare(probe, "probing", false, 5000);
            compare(page.cfg_voiceTtsEngine, "neural");
            var voice = shownOption("voiceTtsNeuralVoice");
            verify(voice, "the natural voice's voice list");
            compare(voice.item.currentValue, "af_heart");
            verify(voice.item.count > 20);
            verify(shownOption("voiceTtsNeuralSpeed"));
            tryCompare(named("neuralVoiceState"), "text", "Not installed yet: replies are read with the system voice until you install it.", 3000);
            var size = named("neuralVoiceSize");
            verify(size.visible);
            compare(size.text, "Install downloads about 258 MB (the program 52 MB, the voice model 206 MB), into /d.");
            compare(named("neuralVoiceInstall").text, "Install (258 MB)");
            verify(named("neuralVoiceGpu").visible, "an NVIDIA card was found");
            compare(root.helperCalls.indexOf("tts_neural_install"), -1, "nothing installed before the button");
            screenshot(page, "config-voice-neural");

            // Say Hello before the install: the system voice reads, and the page says so.
            named("ttsTestButton").clicked();
            tryCompare(named("ttsTestResult"), "text", "That was the system voice: install the natural voice to hear it.", 15000);
            verify(root.helperCalls.indexOf("tts_synthesize") >= 0);

            named("neuralVoiceGpu").checked = true;
            compare(named("neuralVoiceInstall").text, "Install (1.8 GB)");
            named("neuralVoiceGpu").checked = false;
            named("neuralVoiceInstall").clicked();
            compare(root.installPayload.gpu, false);
            tryCompare(named("neuralVoiceState"), "text", "Installed.", 3000);
            compare(named("ttsTestResult").text, "", "the old test result is gone");
            verify(!named("neuralVoiceSize").visible);
            verify(!named("neuralVoiceInstall").visible);
            verify(named("neuralVoiceRemove").visible);
            screenshot(page, "config-voice-neural-installed");
        }
    }
}
