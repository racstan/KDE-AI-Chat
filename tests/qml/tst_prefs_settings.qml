// The look, layout and behaviour options on Settings → Appearance and
// Settings → Chat: they start at their defaults (chat/Prefs.js) with every
// reset button off; changing one turns its reset button on, and the button
// puts it back; "Reset this page" puts the whole page back. Whole pages are
// shot to build/qml-screens/prefs-settings-*.png (wide and narrow).
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat/Prefs.js" as Prefs

Item {
    id: root
    width: 820
    height: 2600

    property QtObject plasmoid: QtObject {
        property string id: ""
        property QtObject configuration: QtObject {
            property string chatSessionsJson: "[]"
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    HarnessTestCase {
        id: testCase
        name: "PrefsSettings"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open(file, props) {
            var component = Qt.createComponent(uiDir + file);
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": root.width, "height": root.height}, props || {}));
            verify(page !== null, file);
            wait(150);
            return page;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            root.width = 820;
            wait(200);
        }
        function named(name) { return findChild(page, name); }
        // The reset button next to a control.
        function resetOf(control) {
            var item = control;
            while (item && item.resetButton === undefined)
                item = item.parent;
            verify(item !== null, "no ResetRow around " + control.objectName);
            return item.resetButton;
        }
        // Picks the next entry of a drop-down with the keyboard, as a user can.
        function pickNext(combo) {
            combo.forceActiveFocus();
            keyClick(Qt.Key_Down);
        }
        function allResets() { return findChildren(page, "resetButton"); }
        function enabledResets() { return allResets().filter(function(b) { return b.enabled; }).length; }
        function appearance(extra) {
            return open("ConfigAppearance.qml", Object.assign({"runHelper": function() {}}, extra || {}));
        }
        // The defaults of `keys` as cfg_ values.
        function cfg(keys) {
            var out = {};
            keys.forEach(function(k) { out["cfg_" + k] = Prefs.defaults[k]; });
            return out;
        }

        function test_1_appearance_starts_at_the_defaults() {
            appearance(cfg(Prefs.lookKeys.concat(Prefs.layoutKeys)));
            verify(allResets().length >= 9, "a reset button per option: " + allResets().length);
            compare(enabledResets(), 0, "nothing differs from the default");
            compare(named("fontScaleSpin").value, 100);
            compare(named("densityCombo").currentValue, "normal");
            compare(named("chatStyleCombo").currentValue, "plain");
            compare(named("codeThemeCombo").currentValue, "system");
            compare(named("accentButton").text, "Plasma accent");
            compare(named("popupWidthSpin").value, 760);
            compare(named("historySideCombo").currentValue, "left");
            verify(named("workspaceBarCheck").checked);
            verify(named("showPinCheck").checked);
            screenshot(page, "prefs-settings-appearance");
        }

        function test_2_each_option_resets_on_its_own() {
            appearance(cfg(Prefs.lookKeys.concat(Prefs.layoutKeys)));
            var spin = named("fontScaleSpin");
            spin.increase();
            spin.valueModified();
            compare(page.cfg_chatFontScale, 110);
            var reset = resetOf(spin);
            verify(reset.enabled, "the reset button turns on");
            compare(enabledResets(), 1, "only this one");
            mouseClick(reset);
            compare(page.cfg_chatFontScale, 100);
            compare(spin.value, 100);
            verify(!reset.enabled);

            var style = named("chatStyleCombo");
            pickNext(style);
            compare(page.cfg_chatStyle, "bubbles");
            var check = named("showPinCheck");
            mouseClick(check);
            compare(page.cfg_headerShowPin, false);
            compare(enabledResets(), 2);
            mouseClick(resetOf(style));
            compare(page.cfg_chatStyle, "plain");
            compare(style.currentValue, "plain");
            compare(page.cfg_headerShowPin, false, "the other option is left alone");
            mouseClick(resetOf(check));
            compare(page.cfg_headerShowPin, true);
            verify(check.checked);
            compare(enabledResets(), 0);
        }

        function test_3_reset_this_page_on_appearance() {
            appearance({"cfg_chatFontScale": 140, "cfg_chatDensity": "roomy", "cfg_chatStyle": "bubbles",
                        "cfg_codeTheme": "dark", "cfg_accentColor": "#2e7d32", "cfg_customPopupWidth": 900,
                        "cfg_customPopupHeight": 700, "cfg_historySide": "right", "cfg_showWorkspaceBar": false,
                        "cfg_headerShowHistory": false, "cfg_headerShowPin": false, "cfg_headerShowSettings": false,
                        "cfg_headerShowNewChat": false, "cfg_headerShowInfo": false,
                        "cfg_appDisplayName": "My helper", "cfg_notifyOnError": false, "cfg_playNotificationSound": false});
            compare(named("accentButton").text, "#2e7d32");
            verify(enabledResets() >= 13, "every changed option can be reset: " + enabledResets());
            root.width = 480;
            page.width = 480;
            wait(150);
            screenshot(page, "prefs-settings-appearance-changed-narrow");
            named("pageResetButton").clicked();
            Prefs.lookKeys.concat(Prefs.layoutKeys).forEach(function(k) {
                compare(page["cfg_" + k], Prefs.defaults[k], k);
            });
            compare(page.cfg_appDisplayName, "KDE AI Chat");
            compare(page.cfg_notifyOnError, true);
            compare(page.cfg_playNotificationSound, true);
            compare(enabledResets(), 0);
        }

        function test_4_chat_page_behaviour() {
            open("ConfigChat.qml", Object.assign({"cfg_contextMessageLimit": -1, "cfg_autoNameChats": true, "cfg_promptTemplates": "[]",
                                                  "cfg_perChatModelSettings": false, "cfg_perChatPriority": "chat"}, cfg(Prefs.behaviourKeys)));
            compare(enabledResets(), 0);
            compare(named("sendKeyCombo").currentValue, "enter");
            compare(named("timeFormatCombo").currentValue, "24h");
            verify(named("autoScrollCheck").checked);
            verify(!named("confirmDeleteCheck").checked);
            verify(!named("newChatOnOpenCheck").checked);
            screenshot(page, "prefs-settings-chat");

            var send = named("sendKeyCombo");
            pickNext(send);
            compare(page.cfg_sendKey, "ctrlEnter");
            mouseClick(named("confirmDeleteCheck"));
            compare(page.cfg_confirmDeleteChat, true);
            mouseClick(resetOf(send));
            compare(page.cfg_sendKey, "enter");
            compare(page.cfg_confirmDeleteChat, true);
        }

        function test_5_reset_this_page_on_chat_keeps_the_templates() {
            var templates = JSON.stringify([{"name": "sum", "text": "Summarize this"}]);
            open("ConfigChat.qml", {"cfg_contextMessageLimit": 10, "cfg_autoNameChats": false, "cfg_allowAskUser": false,
                                    "cfg_promptTemplates": templates, "cfg_openCodeWorkspaceCwd": "/home/me/project",
                                    "cfg_perChatModelSettings": true, "cfg_perChatPriority": "main",
                                    "cfg_sendKey": "ctrlEnter", "cfg_autoScroll": false, "cfg_timeFormat": "12h",
                                    "cfg_confirmDeleteChat": true, "cfg_newChatOnOpen": true});
            compare(enabledResets(), 5);
            mouseClick(named("pageResetButton"));
            compare(page.cfg_sendKey, "enter");
            compare(page.cfg_autoScroll, true);
            compare(page.cfg_timeFormat, "24h");
            compare(page.cfg_confirmDeleteChat, false);
            compare(page.cfg_newChatOnOpen, false);
            compare(page.cfg_contextMessageLimit, -1);
            compare(page.cfg_autoNameChats, true);
            compare(page.cfg_allowAskUser, true);
            compare(page.cfg_openCodeWorkspaceCwd, "");
            compare(page.cfg_perChatModelSettings, false);
            compare(page.cfg_perChatPriority, "chat");
            compare(page.cfg_promptTemplates, templates, "the templates are the user's own writing");
            compare(enabledResets(), 0);
        }

        function test_6_chat_page_narrow() {
            root.width = 480;
            open("ConfigChat.qml", Object.assign({"cfg_contextMessageLimit": -1, "cfg_autoNameChats": true, "cfg_promptTemplates": "[]",
                                                  "cfg_perChatModelSettings": false, "cfg_perChatPriority": "chat"}, cfg(Prefs.behaviourKeys)));
            screenshot(page, "prefs-settings-chat-narrow");
        }
    }
}
