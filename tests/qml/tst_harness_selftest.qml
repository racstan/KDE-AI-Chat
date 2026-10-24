// Proves the offscreen harness can type, click and screenshot, using real
// Kirigami/QQC2 controls like the widget does.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: window
    width: 360
    height: 160

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing

        QQC2.TextField {
            id: input
            Layout.fillWidth: true
            placeholderText: "Type a message"
        }
        QQC2.Button {
            id: send
            text: "Send"
            property string sent: ""
            onClicked: sent = input.text
        }
    }

    HarnessTestCase {
        name: "HarnessSelfTest"

        function test_type_click_screenshot() {
            input.forceActiveFocus();
            keyClick("h");
            keyClick("i");
            compare(input.text, "hi");

            mouseClick(send);
            compare(send.sent, "hi");

            let path = screenshot(window, "harness-selftest");
            verify(path.endsWith("harness-selftest.png"));
        }
    }
}
