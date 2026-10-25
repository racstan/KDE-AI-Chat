// The OpenCode bar inside a column layout, as FullRepresentationContent
// has it: resizing the popup across widths must not make the layouts
// rearrange recursively ("Detected recursive rearrange").
import QtQuick
import QtQuick.Layouts
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 300

    function i18n(text) { return text; }

    FakeChat { id: chat }

    ColumnLayout {
        anchors.fill: parent

        Chat.OpenCodeBar {
            id: bar
            chat: chat
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    HarnessTestCase {
        name: "OpenCodeBar"

        function test_resize_does_not_loop() {
            chat.openCodeMode = true;
            chat.openCodeWorkspaceCwd = "/home/user/some/rather/long/project-folder-name";
            chat.openCodeAgentsList = [{text: "build", value: "build"}, {text: "plan", value: "plan"}];
            failOnWarning(/recursive rearrange/);
            for (var w = 700; w >= 180; w -= 13) {
                root.width = w;
                wait(10);
            }
            for (w = 180; w <= 700; w += 17) {
                root.width = w;
                wait(10);
            }
            verify(bar.visible);
            verify(bar.width <= root.width);
        }
    }
}
