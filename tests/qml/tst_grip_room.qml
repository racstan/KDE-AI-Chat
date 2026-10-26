// The popup's resize grip (chat/ResizeHandle.qml) never covers a button:
// the rows in its corner (header, composer, history, the chat info panel)
// leave it room, for every panel edge and every view. Laid out and wired as
// FullRepresentationContent.qml does.
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 640

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    QtObject {
        id: config
        property int customPopupWidth: 0
        property int customPopupHeight: 0
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    Item {
        id: popup
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            anchors.rightMargin: dialog.visible ? dialog.width + Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Chat.ChatHeader {
                id: header
                Layout.leftMargin: grip.roomTopLeft
                Layout.rightMargin: dialog.visible ? 0 : grip.roomTopRight
                chat: chat
                historyFull: body.historyFull
            }

            Chat.ChatBody {
                id: body
                chat: chat
                Layout.fillWidth: true
                Layout.fillHeight: true
                roomBottomLeft: grip.roomBottomLeft
                roomBottomRight: dialog.visible ? 0 : grip.roomBottomRight
            }
        }

        Chat.ResizeHandle {
            id: grip
            chat: chat
            config: config
            z: 1001
        }

        Ui.ChatSettingsDialog {
            id: dialog
            rootRef: chat
            hostItem: popup
            roomTop: grip.roomTopRight
            roomBottom: grip.roomBottomRight
        }
    }

    HarnessTestCase {
        name: "GripRoom"

        // Bottom panel (grows up), top or left panel (grows down), right panel (grows left).
        readonly property var edges: [
            {"tag": "bottom", "up": true, "left": false},
            {"tag": "top", "up": false, "left": false},
            {"tag": "right", "up": false, "left": true}
        ]

        function init() {
            chat.messages = [{role: "user", content: "Where should we go in May?", time: "10:01"},
                             {role: "assistant", model: "m", content: "Somewhere warm.", time: "10:01"}];
            chat.sessions = [{value: "a", text: "Trip planning", messages: []}, {value: "b", text: "Shell tips", messages: []}];
            chat.currentSessionId = "a";
            chat.projects.list = [{"id": "p1", "name": "Holidays", "color": "#3daee9"}];
            chat.historyOnlyMode = false;
            dialog.close();
            root.width = 520;
        }

        function rect(item) {
            var p = item.mapToItem(popup, 0, 0);
            return {"x": p.x, "y": p.y, "w": item.width, "h": item.height};
        }

        function overlaps(a, b) {
            return a.x < b.x + b.w - 0.5 && b.x < a.x + a.w - 0.5 && a.y < b.y + b.h - 0.5 && b.y < a.y + a.h - 0.5;
        }

        // Every visible button under `item`.
        function buttons(item, into) {
            into = into || [];
            if (!item || !item.visible || item.opacity === 0)
                return into;
            if (item.checkable !== undefined && item.pressed !== undefined && item.width > 0 && item.height > 0) {
                into.push(item);
                return into;
            }
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++)
                buttons(kids[i], into);
            return into;
        }

        function checkView(edge, view) {
            grip.growsUp = edge.up;
            grip.growsLeft = edge.left;
            wait(80);
            var g = rect(grip);
            var gx = edge.left ? 0 : popup.width - grip.width;
            var gy = edge.up ? 0 : popup.height - grip.height;
            compare(Math.round(g.x), Math.round(gx), "the grip is in the " + edge.tag + " panel's far corner");
            compare(Math.round(g.y), Math.round(gy));
            var list = buttons(popup).filter(function(b) { return b !== grip; });
            verify(list.length > 3, "found the buttons");
            for (var i = 0; i < list.length; i++) {
                var name = list[i].Accessible.name || list[i].text || list[i].icon.name;
                verify(!overlaps(rect(list[i]), g), edge.tag + " panel, " + view + ": the grip covers “" + name + "”");
            }
            screenshot(root, "grip-" + edge.tag + "-" + view);
        }

        function test_1_chat_view() {
            for (var i = 0; i < edges.length; i++)
                checkView(edges[i], "chat");
        }

        function test_2_history_in_place_of_the_chat() {
            chat.historyOnlyMode = true;
            tryVerify(() => body.historyFull && body.sessionList !== null, 2000);
            for (var i = 0; i < edges.length; i++)
                checkView(edges[i], "history");
        }

        function test_3_history_beside_the_chat() {
            root.width = Kirigami.Units.gridUnit * 44;
            chat.historyOnlyMode = true;
            tryVerify(() => body.sideHistory && body.sessionList !== null && body.historyPane.width >= body.panelWidth, 3000);
            for (var i = 0; i < edges.length; i++)
                checkView(edges[i], "side-history");
        }

        function test_4_chat_info_panel_open() {
            root.width = Kirigami.Units.gridUnit * 44;
            dialog.openForSession("a");
            tryVerify(() => dialog.visible, 1000);
            for (var i = 0; i < edges.length; i++)
                checkView(edges[i], "chat-info");
            verify(grip.z > dialog.z, "the grip stays above the panel");
        }
    }
}
