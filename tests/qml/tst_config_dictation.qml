// Settings → Voice, dictation part, with a fake helper: the engine list holds
// only engines that work or can be finished here (the rest with a reason);
// the install size is shown before Install can run; Download and Remove ask
// first; Test transcribes with the page's choices; OK/Apply syncs the units;
// the speech server's key is never a setting. Parakeet is the default engine
// and reuses a copy of its model found on disk (Handy's), or downloads it after
// asking. Also Piper voices found on disk and the screenshots of the page.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

Item {
    id: root
    width: 1100
    height: 2400

    property QtObject plasmoid: QtObject {
        property string id: ""
        property QtObject configuration: QtObject {}
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property bool installed: false
    property bool hasTorch: false
    property bool parakeetInstalled: false
    property bool parakeetOnDisk: true
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
        case "stt_engines":
            return {"type": "stt_engines", "gpu": false, "engines": [
                {"id": "parakeet", "available": parakeetInstalled && parakeetOnDisk, "selectable": true,
                 "installed": parakeetInstalled, "model_found": parakeetOnDisk,
                 "reason": parakeetInstalled ? "" : "not installed (one-click install, size shown first)"},
                {"id": "faster-whisper", "available": installed, "selectable": true, "installed": installed,
                 "reason": installed ? "" : "not installed (one-click install, size shown first)"},
                {"id": "whisper-cpp", "available": false, "selectable": false, "reason": "whisper-cli not found"},
                {"id": "remote", "available": !!payload.sttRemoteUrl, "selectable": true, "reason": payload.sttRemoteUrl ? "" : "needs a server URL"},
                {"id": "command", "available": false, "selectable": true, "reason": "no command is set"}]};
        case "stt_models":
            return {"type": "stt_models", "gpu": false, "faster_whisper": [
                {"name": "tiny", "mb": 75, "downloaded": true, "recommended": false, "note": "fastest, least accurate"},
                {"name": "small", "mb": 484, "downloaded": false, "recommended": true, "note": "good balance on a CPU"}],
                "parakeet": [{"name": "parakeet-unified-en-0.6b", "label": "Parakeet Unified EN 0.6B", "mb": 731,
                              "recommended": true, "downloaded": parakeetOnDisk, "source": parakeetOnDisk ? "Handy, HuggingFace cache" : "",
                              "path": parakeetOnDisk ? "/home/u/.cache/huggingface/hub/models--handy-computer--parakeet-unified-en-0.6b-gguf/snapshots/7e9/parakeet-unified-en-0.6b-Q8_0.gguf" : "",
                              "note": "fast, accurate English transcription; English only"}],
                "found": [{"engine": "faster-whisper", "model": "/sn/en_fasterwhisper_base", "path": "/sn/en_fasterwhisper_base",
                           "name": "en_fasterwhisper_base", "source": "Speech Note", "mb": 145},
                          {"engine": "parakeet", "model": "/hf/parakeet-unified-en-0.6b-Q4_K_M.gguf", "path": "/hf/parakeet-unified-en-0.6b-Q4_K_M.gguf",
                           "name": "parakeet-unified-en-0.6b-Q4_K_M", "source": "HuggingFace", "mb": 477},
                          {"engine": "whisper-cpp", "model": "/handy/ggml-small.bin", "path": "/handy/ggml-small.bin",
                           "name": "ggml-small", "source": "Handy", "mb": 488}]};
        case "stt_setup_size":
            if (payload.sttEngine === "parakeet")
                return {"type": "stt_setup_size", "engine": "parakeet", "gpu": false, "packages_mb": 24,
                        "model_mb": parakeetOnDisk ? 0 : 731, "total_mb": parakeetOnDisk ? 24 : 755,
                        "items": parakeetOnDisk ? [] : [{"name": "model Parakeet Unified EN 0.6B", "mb": 731, "kind": "model",
                                                         "to": "/home/u/.local/share/kdeaichat/models/parakeet"}]};
            return {"type": "stt_setup_size", "gpu": false, "packages_mb": 135, "model_mb": 484, "total_mb": 619,
                    "items": [{"name": "model small", "mb": 484, "kind": "model", "to": "/home/u/.cache/huggingface/hub"}]};
        case "voice_data":
            return {"type": "voice_data", "faster_whisper": {"venv": "/home/u/.local/share/kdeaichat/venv",
                    "venv_exists": installed, "venv_mb": hasTorch ? 5200 : 300, "has_torch": hasTorch,
                    "rebuild_frees_mb": hasTorch ? 4900 : 0, "models": [], "models_mb": 0, "total_mb": hasTorch ? 5200 : 300}};
        case "stt_install":
            if (payload.sttEngine === "parakeet")
                parakeetInstalled = true;
            else
                installed = true;
            return {"type": "stt_installed", "ok": true, "mode": "cpu"};
        case "stt_download_model":
            return {"type": "stt_downloaded", "path": "/x"};
        case "stt_test":
            return {"type": "stt_result", "text": "Hello, this is a speech test.", "seconds": 1.2};
        case "voice_data_remove":
            installed = false;
            return {"type": "voice_data_removed", "freed_mb": 5200, "removed": []};
        case "tts_probe":
            return {"ok": true, "piper": "/usr/bin/piper"};
        case "tts_piper_voices":
            return {"type": "tts_piper_voices", "voices": [
                {"path": "/sn/en_piper_lessac/en_US-lessac-medium.onnx", "name": "en_US-lessac-medium", "language": "en_US",
                 "quality": "medium", "source": "Speech Note (Flatpak)", "mb": 63}]};
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

        function open(cfg) {
            var component = Qt.createComponent(uiDir + "ConfigVoice.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": root.width, "height": root.height,
                "runHelper": root.fakeHelper, "walletCall": function(member, args, onReply, onError) { onError("no wallet in tests"); }, "pluginOverride": {"system": "mock", "kokoro": "no-such-engine", "flite": "no-such-engine"},
                "cfg_sttEnabled": true}, cfg || {}));
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
            root.installed = false;
            root.hasTorch = false;
            root.parakeetInstalled = false;
            root.parakeetOnDisk = true;
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
        function dialog() { return find(page, function(item) { return item.hasOwnProperty("confirmDialog"); }).confirmDialog; }

        function test_1_engine_list_only_usable_engines_with_reasons() {
            open({"cfg_sttEngine": "faster-whisper"});
            compare(values(engineCombo()), ["parakeet", "faster-whisper", "remote", "command"]);
            verify(named("sttUnavailable").visible);
            verify(named("sttUnavailable").text.indexOf("whisper-cli not found") >= 0);
            var combo = named("sttModelCombo");
            var all = values(combo);
            verify(all.indexOf("small") >= 0 && all.indexOf("/sn/en_fasterwhisper_base") >= 0, "catalogue and Speech Note models");
            verify(combo.currentText.indexOf("484 MB") >= 0 && combo.currentText.indexOf("recommended") >= 0, combo.currentText);
            combo.currentIndex = all.indexOf("/sn/en_fasterwhisper_base");
            combo.activated(combo.currentIndex);
            compare(page.cfg_sttModel, "/sn/en_fasterwhisper_base");
        }

        function test_2_install_shows_the_size_first() {
            open({"cfg_sttEngine": "faster-whisper"});
            tryVerify(function() { return named("sttSetupSize").text.indexOf("135 MB") >= 0; }, 2000);
            verify(named("sttSetupSize").text.indexOf("484 MB") >= 0, "the model size too");
            verify(root.commands().indexOf("stt_install") < 0, "nothing installed on opening");
            verify(root.commands().indexOf("stt_download_model") < 0);
            var install = named("sttInstallButton");
            verify(install.visible && install.enabled);
            install.clicked();
            tryVerify(function() { return root.commands().indexOf("stt_install") >= 0; }, 2000);
            verify(root.commands().indexOf("stt_setup_size") < root.commands().indexOf("stt_install"));
            tryVerify(function() { return root.last("stt_sync_units") !== null; }, 2000);
            compare(root.last("stt_sync_units").sttEnabled, true);
            tryVerify(function() { return named("sttDownloadButton").visible; }, 2000);
            screenshot(page, "config-dictation-installed");
        }

        function test_3_download_asks_first() {
            root.installed = true;
            open({"cfg_sttEngine": "faster-whisper"});
            var button = named("sttDownloadButton");
            tryVerify(function() { return button.visible; }, 2000);
            button.clicked();
            var d = dialog();
            tryCompare(d, "opened", true, 2000);
            verify(d.subtitle.indexOf("484 MB") >= 0, d.subtitle);
            verify(root.commands().indexOf("stt_download_model") < 0, "not before the answer");
            d.reject();
            wait(100);
            verify(root.commands().indexOf("stt_download_model") < 0, "Cancel downloads nothing");
            button.clicked();
            tryCompare(d, "opened", true, 2000);
            d.accept();
            tryVerify(function() { return root.commands().indexOf("stt_download_model") >= 0; }, 2000);
            compare(root.last("stt_download_model").sttModel, "small");
        }

        function test_4_test_button_uses_the_page_choices() {
            open({"cfg_sttEngine": "remote", "cfg_sttRemoteUrl": "http://localhost:8000/v1"});
            var button = named("sttTestButton");
            tryVerify(function() { return button.enabled; }, 2000);
            button.clicked();
            tryVerify(function() { return named("sttTestResult").text.indexOf("Hello, this is a speech test.") >= 0; }, 2000);
            var payload = root.last("stt_test");
            compare(payload.sttEngine, "remote");
            compare(payload.sttRemoteUrl, "http://localhost:8000/v1");
            verify(root.commands().indexOf("stt_sync_units") < 0, "no service for a remote engine");
            verify(named("ttsSecretField") !== null, "the key field is shown");
        }

        function test_5_save_syncs_the_units_and_no_key_is_a_setting() {
            open({"cfg_sttEngine": "remote"});
            for (var name in page)
                if (name.indexOf("cfg_") === 0)
                    verify(!/apikey|key$|token|password|secret/i.test(name), name + " would be saved by the settings dialog");
            root.calls = [];
            page.saveConfig();
            compare(root.commands(), ["stt_sync_units"]);
            compare(root.last("stt_sync_units").sttEnabled, true);
            compare(root.last("stt_sync_units").sttEngine, "remote");
            verify(JSON.stringify(root.last("stt_sync_units")).toLowerCase().indexOf("key") < 0);
            page.cfg_sttEnabled = false;
            page.saveConfig();
            compare(root.last("stt_sync_units").sttEnabled, false, "turning dictation off removes the service");
        }

        function test_6_remove_and_rebuild_ask_with_sizes() {
            root.installed = true;
            root.hasTorch = true;
            open({"cfg_sttEngine": "faster-whisper"});
            var remove = named("sttRemoveButton");
            tryVerify(function() { return remove.visible; }, 2000);
            verify(named("sttDataSize").text.indexOf("5.2 GB") >= 0, named("sttDataSize").text);
            verify(named("sttRebuildButton").visible, "an old venv with torch can be rebuilt smaller");
            remove.clicked();
            var d = dialog();
            tryCompare(d, "opened", true, 2000);
            verify(d.subtitle.indexOf("5.2 GB") >= 0 && d.subtitle.indexOf("Handy") >= 0, d.subtitle);
            d.reject();
            wait(100);
            verify(root.commands().indexOf("voice_data_remove") < 0);
            named("sttRebuildButton").clicked();
            tryCompare(d, "opened", true, 2000);
            verify(d.subtitle.indexOf("4.9 GB") >= 0, d.subtitle);
            d.accept();
            tryVerify(function() { return root.commands().indexOf("stt_install") >= 0; }, 2000);
            var removal = root.last("voice_data_remove");
            compare(removal.confirm, true);
            compare(removal.keepModels, true, "rebuilding keeps the models");
        }

        function test_7_piper_voices_found_on_disk_and_screenshots() {
            open({"cfg_voiceTtsEnabled": true, "cfg_voiceTtsEngine": "piper"});
            tryVerify(function() { return root.commands().indexOf("tts_piper_voices") >= 0; }, 5000);
            var found = named("piperFoundCombo");
            tryVerify(function() { return found && found.visible; }, 3000);
            compare(found.count, 2);
            found.currentIndex = 1;
            found.activated(1);
            compare(page.cfg_voiceTtsPiperModel, "/sn/en_piper_lessac/en_US-lessac-medium.onnx");
            page.cfg_voiceTtsEngine = "system";
            wait(300);
            screenshot(page, "config-voice-both-on");
            page.cfg_sttEngine = "whisper-cpp";
            wait(200);
            verify(named("sttGgmlFound").visible, "ggml models from Handy are offered");
            compare(engineCombo().currentText, "whisper.cpp (not available)");
            screenshot(page, "config-voice-whisper-cpp");
        }

        function test_8_parakeet_is_the_default_and_reuses_the_model_on_disk() {
            open({"cfg_sttDevice": "cuda"});
            compare(page.cfg_sttEngine, "parakeet");
            compare(engineCombo().currentValue, "parakeet");
            var model = named("sttModelCombo");
            verify(model.currentText.indexOf("Parakeet Unified EN 0.6B · 731 MB · on disk (from Handy, HuggingFace cache) · recommended") === 0,
                   model.currentText);
            verify(values(model).indexOf("/hf/parakeet-unified-en-0.6b-Q4_K_M.gguf") >= 0, "other Parakeet files are offered");
            verify(named("sttEnglishOnly").visible && !named("sttLanguageCombo").visible, "English only");
            var device = named("sttDeviceCombo");
            compare(device.currentValue, "gpu", "a CUDA choice means the graphics card");
            verify(device.currentText.indexOf("Vulkan") >= 0, device.currentText);
            tryVerify(function() { return named("sttSetupSize").text.indexOf("24 MB") >= 0; }, 2000);
            verify(named("sttSetupSize").text.indexOf("already on this computer") >= 0, named("sttSetupSize").text);
            screenshot(page, "config-dictation-parakeet");
            named("sttInstallButton").clicked();
            tryVerify(function() { return root.commands().indexOf("stt_install") >= 0; }, 2000);
            compare(root.last("stt_install").sttEngine, "parakeet");
            tryVerify(function() { return !named("sttInstallButton").visible; }, 2000);
            verify(!named("sttDownloadButton").visible, "nothing to download: the model is on disk");
            verify(root.commands().indexOf("stt_download_model") < 0);
            named("sttTestButton").clicked();
            tryVerify(function() { return root.last("stt_test") !== null; }, 2000);
            compare(root.last("stt_test").sttEngine, "parakeet");
            compare(root.last("stt_sync_units").sttEnabled, true, "the local service is set up for the test");
            screenshot(page, "config-dictation-parakeet-installed");
        }

        function test_9_parakeet_downloads_only_after_asking() {
            root.parakeetInstalled = true;
            root.parakeetOnDisk = false;
            open();
            var button = named("sttDownloadButton");
            tryVerify(function() { return button.visible; }, 2000);
            button.clicked();
            var d = dialog();
            tryCompare(d, "opened", true, 2000);
            verify(d.subtitle.indexOf("731 MB") >= 0 && d.subtitle.indexOf("/home/u/.local/share/kdeaichat/models/parakeet") >= 0,
                   d.subtitle);
            screenshot(page, "config-dictation-parakeet-download");
            d.accept();
            tryVerify(function() { return root.commands().indexOf("stt_download_model") >= 0; }, 2000);
            compare(root.last("stt_download_model").sttEngine, "parakeet");
            compare(root.last("stt_download_model").sttParakeetModel, "parakeet-unified-en-0.6b");
        }
    }
}
