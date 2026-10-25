// The settings pages (contents/config/config.qml), loaded offscreen the way
// Plasma loads them: saved values passed as cfg_ initial properties, and
// `plasmoid` / i18n() from the surrounding context. Each page is shot to
// build/qml-screens/config-<page>.png. Nothing here runs a real command:
// helpers and shell runners are replaced by fakes.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

// A TestCase is never visible, so the pages live in this Item.
Item {
    id: root
    width: 820
    height: 760

    // Plasma provides these to settings pages; names on the root item are in
    // scope for components created from this file.
    property QtObject plasmoid: QtObject {
        property string id: ""
        property QtObject configuration: QtObject {
            property string chatSessionsJson: "[]"
            property string voiceEspeakPath: ""
            property bool voiceEnabled: false
            property bool voiceTtsEnabled: false
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(singular, plural, count) {
        var text = count === 1 ? singular : plural;
        for (var i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), arguments[i]);
        return text;
    }

    HarnessTestCase {
        id: testCase
        name: "ConfigPages"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null
        property var shellLog: []

        function open(file, cfg) {
            var component = Qt.createComponent(uiDir + file);
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": root.width, "height": root.height}, cfg));
            verify(page !== null, file + " could not be created");
            return page;
        }

        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            // Let the style's animations end before the next page (or exit).
            wait(250);
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
        function byText(type, text) {
            return find(page, function(item) { return item instanceof type && item.text === text; });
        }
        function click(button) {
            verify(button !== null, "control not found");
            if (button.checkable !== undefined && button.checkable)
                button.toggle();
            button.toggled();
        }

        // Waits for the style's check/radio animations, then saves the page.
        function shot(fileName) {
            wait(300);
            screenshot(page, fileName);
        }

        function noSecretSettings() {
            for (var name in page)
                if (name.indexOf("cfg_") === 0)
                    verify(!/apikey|token|password|sessions|messages/i.test(name), name + " would be saved by the settings dialog");
        }

        // ── Harness ──────────────────────────────────────────────────────────
        function test_harness_modes_are_exclusive() {
            open("ConfigHarness.qml", {"cfg_useOpenCode": false, "cfg_usePi": false, "cfg_openCodeUrl": "http://127.0.0.1:9/v1",
                                        "cfg_openCodeProvider": "", "cfg_openCodeModel": "", "cfg_piProvider": "ollama", "cfg_piModel": "qwen3:8b"});
            noSecretSettings();
            shot("config-harness");
            click(byText(QQC2.RadioButton, "Through OpenCode"));
            verify(page.cfg_useOpenCode && !page.cfg_usePi);
            verify(!byText(QQC2.RadioButton, "Directly to a provider").checked);
            compare(page.cfg_openCodeUrl, "http://127.0.0.1:9/v1");
            shot("config-harness-opencode");

            var pi = find(page, function(item) { return item.hasOwnProperty("modelsByProvider") && !item.hasOwnProperty("url"); });
            verify(pi !== null, "PiSettings not found");
            pi.helper = {"run": function(command, payload, done) {
                testCase.shellLog.push(command);
                done(JSON.stringify({"providers": [{"id": "ollama", "models": ["llama3.2", "qwen3:8b"]}, {"id": "opencode", "models": ["big-pickle"]}]}), 0, "");
            }};
            click(byText(QQC2.RadioButton, "Through Pi"));
            verify(page.cfg_usePi && !page.cfg_useOpenCode);
            compare(shellLog[shellLog.length - 1], "get_pi_models");
            compare(page.cfg_piProvider, "ollama");
            compare(page.cfg_piModel, "qwen3:8b");
            pi.choose("opencode", "");
            compare(page.cfg_piModel, "big-pickle");
            shot("config-harness-pi");

            click(byText(QQC2.RadioButton, "Directly to a provider"));
            verify(!page.cfg_usePi && !page.cfg_useOpenCode);
        }

        // ── Chat ─────────────────────────────────────────────────────────────
        function test_chat_page_per_chat_model_settings_are_opt_in() {
            open("ConfigChat.qml", {"cfg_enableSystemPrompt": true, "cfg_systemPrompt": "", "cfg_contextMessageLimit": -1,
                                    "cfg_autoNameChats": true, "cfg_promptTemplates": "[]",
                                    "cfg_perChatModelSettings": false, "cfg_perChatPriority": "chat"});
            noSecretSettings();
            var named = function(name) { return find(page, function(item) { return item.objectName === name; }); };
            var sw = named("perChatSwitch");
            verify(sw !== null, "the switch exists");
            compare(sw.text, "Let chats have their own model settings");
            compare(sw.checked, false);
            verify(!named("chatWinsRadio").visible, "the priority choice is hidden while off");
            verify(!named("mainWinsRadio").visible);
            mouseClick(sw);
            wait(50);
            compare(page.cfg_perChatModelSettings, true);
            verify(named("chatWinsRadio").visible);
            verify(named("mainWinsRadio").visible);
            compare(named("chatWinsRadio").text, "This chat's settings win");
            compare(named("mainWinsRadio").text, "Main settings win");
            compare(named("chatWinsRadio").checked, true, "chat wins by default");
            mouseClick(named("mainWinsRadio"));
            compare(page.cfg_perChatPriority, "main");
            compare(named("chatWinsRadio").checked, false);
            mouseClick(named("chatWinsRadio"));
            compare(page.cfg_perChatPriority, "chat");
            shot("config-chat-per-chat");
        }

        function test_chat_page_edits_templates() {
            open("ConfigChat.qml", {"cfg_enableSystemPrompt": true, "cfg_systemPrompt": "You are a helpful assistant.",
                                    "cfg_contextMessageLimit": -1, "cfg_autoNameChats": true,
                                    "cfg_promptTemplates": JSON.stringify([{"name": "review", "prompt": "Review this code for bugs."}])});
            noSecretSettings();
            var editor = find(page, function(item) { return item.hasOwnProperty("templates") && item.hasOwnProperty("json"); });
            verify(editor !== null, "TemplatesEditor not found");
            compare(editor.templates.length, 1);
            editor.save(-2, " /summary  ", "Summarise this in three bullet points.");
            compare(JSON.parse(page.cfg_promptTemplates).length, 2);
            compare(JSON.parse(page.cfg_promptTemplates)[1].name, "summary");
            shot("config-chat");
            editor.remove(0);
            compare(JSON.parse(page.cfg_promptTemplates)[0].name, "summary");
            var spin = find(page, function(item) { return item instanceof QQC2.SpinBox; });
            compare(spin.displayText, "All (up to 100)");
        }

        // ── Schedules ────────────────────────────────────────────────────────
        function test_schedules_page_runs_no_real_command() {
            shellLog = [];
            open("ConfigSchedules.qml", {"cfg_schedulerEnabled": true, "cfg_schedulerAutoStart": false, "cfg_executeMissedSchedules": false,
                                         "runShell": function(script, tag) { testCase.shellLog.push(tag); }});
            noSecretSettings();
            verify(shellLog.indexOf("sched-setup") >= 0, "setup not requested: " + shellLog);
            verify(shellLog.indexOf("sched-load") >= 0);
            var service = find(page, function(item) { return item.hasOwnProperty("schedulerList") && item.hasOwnProperty("runShell"); });
            service.handle("sched-load", JSON.stringify({"schedules": [{"id": "a", "name": "Morning news", "enabled": true},
                                                                      {"id": "b", "name": "Old", "archived": true}], "history": []}), "");
            compare(service.schedulerList.length, 1);
            compare(service.schedulerArchivedList.length, 1);
            service.handle("sched-poll", "SCHED_RUNNING", "");
            verify(service.running);
            service.handle("sched-setup", "AUTO_ENABLED", "");
            compare(page.cfg_schedulerAutoStart, true);
            shot("config-schedules");
        }

        // ── Voice ────────────────────────────────────────────────────────────
        function test_voice_page_shows_the_engine_check() {
            open("ConfigVoice.qml", {"cfg_voiceEnabled": false, "cfg_voiceGpuEnabled": false, "cfg_voiceTtsEnabled": false,
                                     "cfg_voiceTtsAuto": false, "cfg_voiceAutoSend": true, "cfg_voiceSttModelPath": "",
                                     "cfg_voiceTtsModelPath": "", "cfg_voiceTtsVoice": "", "cfg_voiceLanguage": "en",
                                     "cfg_voiceVenvPath": "~/.local/share/kdeaichat/venv"});
            noSecretSettings();
            shot("config-voice-off");
            // Set like a saved value, not a click, so no service is touched.
            page.cfg_voiceEnabled = true;
            page.cfg_voiceTtsEnabled = true;
            var engine = find(page, function(item) { return item.hasOwnProperty("repairNeeded"); });
            verify(engine !== null, "VoiceEngine not found");
            engine.handle({"type": "env_check", "stt_ready": true, "tts_ready": false, "stt_model_path_ok": true, "faster_whisper_ok": true,
                           "sounddevice_ok": true, "numpy_ok": true, "venv_exists": true, "venv_ready": true, "tts_model_path_ok": true,
                           "mic_available": true, "paplay_available": true, "espeak_available": false, "tts_model_type": "kokoro-82m"});
            verify(engine.espeakMissing);
            verify(!engine.ready);
            verify(!engine.repairNeeded, "Repair can't install espeak-ng");
            compare(engine.status, "This voice model needs the espeak-ng package. Install it with your package manager.");
            var combo = find(page, function(item) { return item instanceof QQC2.ComboBox; });
            compare(combo.currentText, "English");
            shot("config-voice");
        }

        // ── Appearance ───────────────────────────────────────────────────────
        function test_appearance_page() {
            open("ConfigAppearance.qml", {"cfg_customIcon": "dialog-messages", "cfg_appDisplayName": "KDE AI Chat", "cfg_playNotificationSound": true});
            noSecretSettings();
            verify(!page.isCustomIconImage("bot-symbolic"));
            verify(page.isCustomIconImage("/home/me/robot.GIF"));
            compare(page.customIconImageSource("/home/me/robot.gif"), "file:///home/me/robot.gif");
            shot("config-appearance");
        }
    }
}
