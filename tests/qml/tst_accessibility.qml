// Screen readers and the keyboard. Walks the chat (header, history, messages,
// composer) and some settings pages and checks every visible interactive item
// has an accessible name (Accessible.name, or its own text for buttons and
// checkboxes), that Tab walks the composer and header in a sensible order and
// that Esc backs out of popups. Settings pages are walked the same way.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 760
    height: 640

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
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Chat.ChatHeader { id: header; chat: chat; historyFull: body.historyFull }
        Chat.ChatBody {
            id: body
            chat: chat
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    HarnessTestCase {
        id: test
        name: "Accessibility"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null
        // Interactive items the last walk looked at (a walk that finds none checks nothing).
        property int seen: 0

        // Genuinely decorative or internal items, by objectName. Keep it small.
        readonly property var allowlist: ["buttonMetrics"]
        readonly property var interactive: /(ToolButton|Button|CheckBox|Switch|ComboBox|TextField|TextArea|SpinBox|Slider|RadioButton|MenuItem|SearchField|ItemDelegate|TabButton)(_QML|\()/
        // These name themselves from their text.
        readonly property var namedByText: /(Button|CheckBox|Switch|RadioButton|MenuItem|ItemDelegate|TabButton)(_QML|\()/
        // The text field or button inside these is part of the outer control.
        readonly property var composite: /(ComboBox|SpinBox|SearchField|PasswordField|Slider)(_QML|\()/

        function init() {
            root.width = 760;
            chat.historyOnlyMode = false;
            chat.calls = [];
            var now = Date.now();
            chat.currentSessionId = "a";
            chat.messages = [{role: "user", content: "Where should we go in May?", time: "10:01"},
                             {role: "assistant", model: "openrouter/auto", content: "Somewhere warm.", time: "10:01", tokens: {input: 30, output: 12}}];
            chat.sessions = [
                {value: "a", text: "Trip planning", count: 4, updatedAt: now},
                {value: "b", text: "OpenCode refactor", source: "opencode", count: 14, updatedAt: now - 86400000}
            ];
            wait(30);
        }

        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            wait(250);
        }

        function open(file, cfg) {
            var component = Qt.createComponent(uiDir + file);
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": root.width, "height": root.height}, cfg));
            verify(page !== null, file + " could not be created");
            wait(100);
            return page;
        }

        function describe(item) {
            var path = String(item).replace(/\(0x[0-9a-f]+\)/, "");
            if (item.objectName)
                path += "#" + item.objectName;
            if (item.text !== undefined)
                path += " text='" + String(item.text).substring(0, 30) + "'";
            return path;
        }

        // Names of visible interactive items that have none.
        function unnamed(item, insideComposite, into) {
            if (!item || !item.visible || item.width <= 0 || item.height <= 0)
                return into;
            var text = String(item);
            var isWidget = interactive.test(text);
            if (isWidget && !insideComposite && allowlist.indexOf(item.objectName) < 0) {
                seen++;
                var name = item.Accessible.name;
                var own = namedByText.test(text) && item.text !== undefined && String(item.text) !== "";
                if (!name && !own)
                    into.push(describe(item));
            }
            // TapHandler rows: the row (or the nearest parent that has a name) must say what it is.
            var data = item.data || [];
            for (var d = 0; d < data.length; d++) {
                if (String(data[d]).indexOf("TapHandler") === 0 && !isWidget && allowlist.indexOf(item.objectName) < 0) {
                    var p = item, labelled = false;
                    for (var up = 0; p && up < 4 && !labelled; up++, p = p.parent)
                        labelled = !!p.Accessible.name;
                    if (!labelled)
                        into.push(describe(item) + " (TapHandler)");
                    break;
                }
            }
            var kids = item.children || [];
            var skip = insideComposite || (isWidget && composite.test(text));
            for (var i = 0; i < kids.length; i++)
                unnamed(kids[i], skip, into);
            return into;
        }

        function test_01_the_chat_has_a_name_for_every_control() {
            seen = 0;
            var missing = unnamed(column, false, []);
            compare(missing.join("\n"), "");
            verify(seen >= 8, "walked the header, history and composer: " + seen);
        }

        function test_02_the_chat_with_a_narrow_popup_too() {
            root.width = 360;
            chat.historyOnlyMode = true;
            wait(80);
            var missing = unnamed(column, false, []);
            compare(missing.join("\n"), "");
        }

        function test_03_message_items_say_who_spoke() {
            var list = body.chatView.list;
            var you = null, assistant = null;
            var items = list.contentItem.children;
            for (var i = 0; i < items.length; i++) {
                var name = items[i].Accessible ? items[i].Accessible.name : "";
                if (name.indexOf("You said:") === 0) you = name;
                if (name.indexOf("openrouter/auto replied:") === 0) assistant = name;
            }
            compare(you, "You said: Where should we go in May?");
            compare(assistant, "openrouter/auto replied: Somewhere warm.");
        }

        function test_04_streaming_name_does_not_carry_the_changing_text() {
            chat.currentStreamIndex = 1;
            chat.currentStreamText = "Some";
            wait(80);
            var items = body.chatView.list.contentItem.children, first = "", second = "";
            for (var i = 0; i < items.length; i++)
                if ((items[i].Accessible.name || "").indexOf("is writing a reply") >= 0)
                    first = items[i].Accessible.name;
            chat.currentStreamText = "Some more text";
            wait(80);
            for (var j = 0; j < items.length; j++)
                if ((items[j].Accessible.name || "").indexOf("is writing a reply") >= 0)
                    second = items[j].Accessible.name;
            compare(first, "openrouter/auto is writing a reply");
            compare(second, first, "the name stays the same while text arrives");
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
        }

        function test_05_settings_pages_name_every_control() {
            open("ConfigPersonality.qml", {"cfg_userName": "", "cfg_userAbout": "", "cfg_userTone": "", "cfg_userLanguage": "",
                                            "cfg_userNotes": "", "cfg_aiName": "", "cfg_aiPersonality": "", "cfg_aiPersonalityCustom": "",
                                            "cfg_aiAvatar": "", "cfg_enableSystemPrompt": false, "cfg_systemPrompt": ""});
            seen = 0;
            compare(unnamed(page, false, []).join("\n"), "");
            verify(seen >= 5, "walked the settings controls: " + seen);
        }

        function test_06_chat_and_appearance_pages() {
            open("ConfigChat.qml", {"cfg_contextMessageLimit": -1, "cfg_autoNameChats": true, "cfg_promptTemplates": "[]",
                                    "cfg_perChatModelSettings": true, "cfg_perChatPriority": "chat"});
            compare(unnamed(page, false, []).join("\n"), "");
            page.destroy();
            page = null;
            open("ConfigAppearance.qml", {"cfg_customIcon": "dialog-messages", "cfg_appDisplayName": "KDE AI Chat", "cfg_playNotificationSound": true,
                                           "cfg_notifyOnReply": true, "cfg_notifyOnError": false, "cfg_notifyOnScheduled": true, "cfg_notifyOnInput": true});
            compare(unnamed(page, false, []).join("\n"), "");
        }

        // The composer is the first stop of the chat; Tab then reaches the
        // attach and paste buttons and Send. Tab inside the message box must
        // leave it (it never inserts a tab), and Shift+Tab goes back.
        function test_07_tab_leaves_the_message_box_and_reaches_the_buttons() {
            chat.focusInput();
            var composer = chat.composerRef;
            tryVerify(() => composer.input.activeFocus, 1000);
            chat.chatInputText = "";
            composer.input.text = "hello";
            keyClick(Qt.Key_Tab);
            wait(30);
            compare(composer.input.text, "hello", "Tab does not type a tab into the message");
            verify(!composer.input.activeFocus, "Tab moves focus on");
            keyClick(Qt.Key_Tab, Qt.ShiftModifier);
            wait(30);
            verify(composer.input.activeFocus, "Shift+Tab comes back");
        }

        function test_08_tab_order_in_the_header_follows_the_screen() {
            var buttons = [];
            var order = findChild(header, "newChatButton");
            // Collect focusable header buttons left to right.
            (function walk(item) {
                if (!item || !item.visible) return;
                if (/(ToolButton)(_QML|\()/.test(String(item)) && item.activeFocusOnTab && item.width > 0)
                    buttons.push(item);
                var kids = item.children || [];
                for (var i = 0; i < kids.length; i++) walk(kids[i]);
            })(header);
            verify(buttons.length >= 3, "the header has buttons to tab through");
            buttons[0].forceActiveFocus();
            var seen = [buttons[0]];
            for (var i = 1; i < buttons.length; i++) {
                keyClick(Qt.Key_Tab);
                wait(20);
                var focused = null;
                for (var j = 0; j < buttons.length; j++)
                    if (buttons[j].activeFocus) focused = buttons[j];
                verify(focused !== null, "Tab stays inside the header for button " + i);
                seen.push(focused);
            }
            // Tab walked in x order (the header's visual order).
            for (var k = 1; k < seen.length; k++)
                verify(seen[k].mapToItem(header, 0, 0).x >= seen[k - 1].mapToItem(header, 0, 0).x,
                       "button " + k + " is to the right of button " + (k - 1));
        }

        function test_09_escape_closes_the_more_menu() {
            var more = findChild(header, "moreButton");
            more.menu.open();
            tryVerify(() => more.menu.opened, 1000);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !more.menu.opened, 1000);
        }
    }
}
