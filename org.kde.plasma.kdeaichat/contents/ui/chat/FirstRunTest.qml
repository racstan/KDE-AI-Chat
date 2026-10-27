// Last screen of the first-run setup: the provider works; an optional test message.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: testStep

    // The FirstRun.qml that owns the state.
    property var ctl: null

    spacing: Kirigami.Units.smallSpacing

    Kirigami.Heading {
        objectName: "firstRunReady"
        level: 4
        text: i18n("You're set up")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: testStep.ctl.savedLocal
            ? i18n("%1 · %2. It runs on this computer, so your messages stay here.", testStep.ctl.savedName, testStep.ctl.savedModel)
            : i18n("%1 · %2. Your messages are sent to its servers.", testStep.ctl.savedName, testStep.ctl.savedModel)
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.8
        text: i18n("Want to check that it answers? Send a short test message, or just start chatting.")
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            objectName: "firstRunSendTest"
            highlighted: true
            text: i18n("Send a test message")
            icon.name: "mail-send"
            onClicked: testStep.ctl.sendTest()
        }

        QQC2.Button {
            objectName: "firstRunFinish"
            text: i18n("Start chatting")
            onClicked: testStep.ctl.finish()
        }
    }
}
