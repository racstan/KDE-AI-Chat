// Every setting has its plain explanation, checked on the pages as they are
// laid out (tests/test_setting_help.py checks the QML source of every form):
// each visible form row with a label and something to change in it has a
// visible SettingHelp below it, before the next such row. Also the
// SettingHelp itself: small grey wrapped text with an optional hover text.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami

Item {
    id: root
    width: 820
    height: 1400

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
        name: "SettingHelp"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open(file, props) {
            var component = Qt.createComponent(uiDir + file);
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": root.width}, props || {}));
            verify(page !== null, file);
            wait(100);
            return page;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            wait(200);
        }

        function visibleTree(item, out) {
            if (!item || item.visible === false)
                return out;
            out.push(item);
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++)
                visibleTree(kids[i], out);
            return out;
        }
        // Something to change: a control that isn't a busy indicator.
        function hasControl(item) {
            if (item.focusPolicy !== undefined && item.running === undefined)
                return true;
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++)
                if (kids[i].visible && hasControl(kids[i]))
                    return true;
            return false;
        }
        function yOf(item) { return item.mapToItem(page, 0, 0).y; }

        // Fails with the label of every row without an explanation below it.
        function checkPage(what) {
            var items = visibleTree(page, []);
            var rows = items.filter(function(item) {
                var label = item.Kirigami.FormData.label;
                return label && !item.Kirigami.FormData.isSection && !(item instanceof QQC2.Label) && hasControl(item);
            }).sort(function(a, b) { return yOf(a) - yOf(b); });
            var helps = items.filter(function(item) { return item.isSettingHelp === true && item.text !== ""; });
            verify(rows.length > 0, what + ": no form rows found");
            var missing = [];
            for (var i = 0; i < rows.length; i++) {
                var from = yOf(rows[i]);
                var to = i + 1 < rows.length ? yOf(rows[i + 1]) : Infinity;
                var found = helps.some(function(h) { var y = yOf(h); return y > from && y <= to; });
                if (!found)
                    missing.push(rows[i].Kirigami.FormData.label);
            }
            compare(missing.join(", "), "", what + ": rows without an explanation");
            return {"rows": rows.length, "helps": helps.length};
        }

        function test_setting_help_looks_like_a_note() {
            var component = Qt.createComponent(uiDir + "config/SettingHelp.qml");
            verify(component.status === Component.Ready, component.errorString());
            var help = component.createObject(root, {"text": "What it does.", "details": "More about it."});
            compare(help.isSettingHelp, true);
            compare(help.wrapMode, Text.Wrap);
            verify(help.font.pointSize <= Qt.application.font.pointSize, "small text");
            compare(help.Accessible.description, "More about it.");
            help.destroy();
        }

        function test_chat_page() {
            open("ConfigChat.qml", {"cfg_contextMessageLimit": -1, "cfg_autoNameChats": true, "cfg_promptTemplates": "[]",
                                    "cfg_perChatModelSettings": true, "cfg_perChatPriority": "chat"});
            checkPage("Chat");
        }

        function test_personality_page() {
            open("ConfigPersonality.qml", {"cfg_aiPersonality": "custom", "cfg_enableSystemPrompt": true});
            var counts = checkPage("Personality");
            verify(counts.rows >= 9, "every field of the page: " + counts.rows);
        }

        function test_memory_page() {
            var fake = {"run": function(command, payload, onDone) { if (onDone) onDone(JSON.stringify({"ok": true, "memories": []}), 0, ""); }};
            open("ConfigMemory.qml", {"helperRunner": fake, "chatTitles": {}, "projectNames": {}});
            checkPage("Memory");
        }

        function test_voice_page_read_aloud() {
            open("ConfigVoice.qml", {"cfg_voiceTtsEnabled": true, "cfg_sttEnabled": false,
                                     "runHelper": function(command, payload, onDone) {
                                         if (onDone) onDone(JSON.stringify({"ok": true}), 0, "");
                                     },
                                     "walletCall": function(member, args, onReply, onError) { onError("no wallet in tests"); },
                                     "pluginOverride": {"system": "mock"}});
            wait(500);
            checkPage("Voice");
        }

        function test_appearance_page() {
            open("ConfigAppearance.qml", {"cfg_panelIconMode": "animated", "runHelper": function() {}});
            var counts = checkPage("Appearance");
            verify(counts.helps >= 10, "notifications, sound, name, icon, animation: " + counts.helps);
        }

        function test_connection_forms() {
            open("config/ProviderEditor.qml", {"draft": {"name": "Mine", "type": "openai-compat", "baseUrl": "https://x/v1", "model": "m"}});
            checkPage("ProviderEditor");
            page.destroy();
            open("config/RequestOptions.qml");
            checkPage("RequestOptions");
            page.destroy();
            open("config/ModeChooser.qml");
            compare(visibleTree(page, []).filter(function(i) { return i.isSettingHelp === true; }).length, 3, "one per way to send");
        }

        function test_schedule_options() {
            open("config/ScheduleOptions.qml", {"draft": {"catchUp": {"enabled": true, "withinHours": 12}}});
            checkPage("ScheduleOptions");
        }
    }
}
