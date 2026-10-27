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

        // The Connection page (modes, providers, model pickers) is tested in tst_config_connection.qml.

        // ── Chat ─────────────────────────────────────────────────────────────
        function test_chat_page_per_chat_model_settings_are_opt_in() {
            open("ConfigChat.qml", {"cfg_contextMessageLimit": -1,
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

        function test_chat_page_default_workspace_is_empty_and_editable() {
            open("ConfigChat.qml", {"cfg_contextMessageLimit": -1,
                                    "cfg_autoNameChats": true, "cfg_promptTemplates": "[]", "cfg_openCodeWorkspaceCwd": ""});
            noSecretSettings();
            var field = find(page, function(item) { return item.objectName === "defaultWorkspaceField"; });
            verify(field !== null, "the field exists");
            compare(field.text, "");
            compare(field.placeholderText, "No workspace");
            field.text = "/home/me/work";
            compare(page.cfg_openCodeWorkspaceCwd, "/home/me/work");
        }

        function test_chat_page_edits_templates() {
            open("ConfigChat.qml", {"cfg_contextMessageLimit": -1, "cfg_autoNameChats": true,
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

        // ── Personality ──────────────────────────────────────────────────────
        function test_personality_page() {
            open("ConfigPersonality.qml", {"cfg_userName": "Rachit", "cfg_userAbout": "I build KDE widgets.", "cfg_userTone": "friendly",
                                            "cfg_userLanguage": "", "cfg_userNotes": "Never use emoji.", "cfg_aiName": "Nova",
                                            "cfg_aiPersonality": "witty", "cfg_aiPersonalityCustom": "", "cfg_aiAvatar": "face-smile",
                                            "cfg_enableSystemPrompt": true, "cfg_systemPrompt": "You are a helpful assistant."});
            noSecretSettings();
            var named = function(name) { return find(page, function(item) { return item.objectName === name; }); };
            compare(named("userNameField").text, "Rachit");
            compare(named("toneCombo").currentText, "Friendly");
            compare(named("personalityCombo").currentText, "Witty");
            compare(named("languageField").placeholderText, "Same as my message");
            compare(named("systemPromptArea").text, "You are a helpful assistant.", "the global prompt moved here");
            compare(named("avatarStatus").text, "face-smile");
            compare(named("userAvatarStatus").text, "None");
            verify(!named("customPersonalityArea").visible, "custom text only for Custom");
            shot("config-personality");

            // Presets write their ids; Custom shows its box.
            var combo = named("personalityCombo");
            combo.currentIndex = combo.indexOfValue("custom");
            combo.activated(combo.currentIndex);
            compare(page.cfg_aiPersonality, "custom");
            verify(named("customPersonalityArea").visible);
            var tone = named("toneCombo");
            tone.currentIndex = 0;
            tone.activated(0);
            compare(page.cfg_userTone, "", "no preference = nothing sent");
            named("userNameField").text = "Ana";
            compare(page.cfg_userName, "Ana");

            // An image file is taken only with an image extension and a safe path.
            page.setAvatarFile("file:///home/me/notes.txt");
            compare(page.cfg_aiAvatar, "face-smile", "not an image: unchanged");
            verify(page.avatarError !== "");
            var picture = String(Qt.resolvedUrl("../fixtures/avatar.png"));
            page.setAvatarFile(picture);
            compare(page.cfg_aiAvatar, decodeURIComponent(picture.replace(/^file:\/\//, "")));
            compare(page.avatarError, "");
            var chosen = page.cfg_aiAvatar;
            page.setAvatarFile("file:///home/me/../a.png");
            compare(page.cfg_aiAvatar, chosen, "unsafe path refused");
            verify(page.avatarError !== "");
            page.setAvatarFile(picture);
            compare(named("avatarStatus").text, "avatar.png");
            compare(page.cfg_userAvatar, "", "the AI's avatar is not yours");
            shot("config-personality-custom");
        }

        // Your own avatar: the same choices and checks as the AI's, saved as cfg_userAvatar.
        function test_personality_user_avatar() {
            open("ConfigPersonality.qml", {"cfg_userName": "Rachit", "cfg_userAbout": "", "cfg_userTone": "", "cfg_userLanguage": "",
                                            "cfg_userNotes": "", "cfg_aiName": "", "cfg_aiPersonality": "", "cfg_aiPersonalityCustom": "",
                                            "cfg_aiAvatar": "", "cfg_userAvatar": "", "cfg_enableSystemPrompt": false, "cfg_systemPrompt": ""});
            noSecretSettings();
            var named = function(name) { return find(page, function(item) { return item.objectName === name; }); };
            var picker = named("userAvatarButton").parent;
            verify(named("userAvatarButton").visible);
            compare(named("userAvatarStatus").text, "None");
            // A theme icon (what the icon dialog does).
            picker.value = "face-glasses";
            compare(page.cfg_userAvatar, "face-glasses");
            compare(named("userAvatarStatus").text, "face-glasses");
            compare(page.cfg_aiAvatar, "", "the AI's avatar is untouched");
            shot("config-personality-user-icon");
            // An image file with a safe path.
            var picture = String(Qt.resolvedUrl("../fixtures/avatar.png"));
            picker.setFile(picture);
            compare(page.cfg_userAvatar, decodeURIComponent(picture.replace(/^file:\/\//, "")));
            compare(named("userAvatarStatus").text, "avatar.png");
            wait(100);
            shot("config-personality-user-image");
            // Bad choices are refused and the old one stays.
            var chosen = page.cfg_userAvatar;
            picker.setFile("file:///home/me/notes.txt");
            compare(page.cfg_userAvatar, chosen, "not an image");
            verify(picker.error !== "");
            compare(named("userAvatarStatus").text, picker.error);
            picker.setFile("file:///home/me/../a.png");
            compare(page.cfg_userAvatar, chosen, "unsafe path refused");
            compare(page.avatarError, "", "the AI's error line is its own");
            // No Avatar.
            picker.value = "";
            compare(named("userAvatarStatus").text, "None" );
        }

        function test_personality_page_empty() {
            open("ConfigPersonality.qml", {"cfg_userName": "", "cfg_userAbout": "", "cfg_userTone": "", "cfg_userLanguage": "",
                                            "cfg_userNotes": "", "cfg_aiName": "", "cfg_aiPersonality": "", "cfg_aiPersonalityCustom": "",
                                            "cfg_aiAvatar": "", "cfg_enableSystemPrompt": false, "cfg_systemPrompt": ""});
            var named = function(name) { return find(page, function(item) { return item.objectName === name; }); };
            compare(named("toneCombo").currentText, "No preference");
            compare(named("personalityCombo").currentText, "None");
            compare(named("avatarStatus").text, "None");
            verify(!named("systemPromptArea").enabled);
            shot("config-personality-empty");
        }

        // ── Schedules ────────────────────────────────────────────────────────
        function test_schedules_page_runs_no_real_command() {
            shellLog = [];
            open("ConfigSchedules.qml", {"runHelper": function(command, payload, onDone) {
                testCase.shellLog.push(command);
                onDone(JSON.stringify({"ok": true, "schedules": [], "settings": {}}), 0, "");
            }});
            noSecretSettings();
            compare(shellLog.join(","), "schedules_list");
            shot("config-schedules");
        }

        // ── Voice ────────────────────────────────────────────────────────────
        // Read aloud: tst_config_voice.qml; dictation: tst_config_dictation.qml.
        function test_voice_page_off_runs_nothing() {
            shellLog = [];
            open("ConfigVoice.qml", {"cfg_sttEnabled": false, "cfg_voiceTtsEnabled": false, "cfg_voiceTtsAuto": false,
                                     "cfg_voiceAutoSend": true,
                                     "runHelper": function(command, payload, onDone) { testCase.shellLog.push(command); if (onDone) onDone("{}", 0, ""); }});
            noSecretSettings();
            compare(shellLog.join(","), "", "with both switches off nothing is asked");
            shot("config-voice-off");
        }

        // ── Appearance ───────────────────────────────────────────────────────
        function test_appearance_page() {
            open("ConfigAppearance.qml", {"cfg_customIcon": "dialog-messages", "cfg_appDisplayName": "KDE AI Chat", "cfg_playNotificationSound": true,
                                           "cfg_notifyOnReply": true, "cfg_notifyOnError": false, "cfg_notifyOnScheduled": true, "cfg_notifyOnInput": true});
            noSecretSettings();
            var named = function(name) { return find(page, function(item) { return item.objectName === name; }); };
            compare(named("notifyReplyCheck").checked, true);
            compare(named("notifyErrorCheck").checked, false);
            compare(named("notifyScheduledCheck").checked, true);
            compare(named("notifyInputCheck").checked, true);
            // The notifications are below the chat look and layout: scroll to them.
            var flick = page.flickable;
            flick.contentY = Math.max(0, named("notifyReplyCheck").mapToItem(flick.contentItem, 0, 0).y - 100);
            wait(50);
            mouseClick(named("notifyInputCheck"));
            compare(page.cfg_notifyOnInput, false);
            compare(named("soundCheck").checked, true);
            mouseClick(named("notifyErrorCheck"));
            compare(page.cfg_notifyOnError, true);
            mouseClick(named("notifyReplyCheck"));
            compare(page.cfg_notifyOnReply, false);
            var rows = [];
            find(page, function(item) { if (item.objectName === "shortcutRow") rows.push(item); return false; });
            compare(rows.length, 19, "every shortcut is listed");
            compare(rows[0].text, "New chat");
            compare(rows[9].text, "Next chat");
            verify(named("shortcutNote") !== null);
            shot("config-appearance");
        }
    }
}
