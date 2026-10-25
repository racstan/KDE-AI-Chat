// What the user can do about an error message: Try again, Open settings
// (when settings can fix it) and, when the original message says more than
// the plain-language text, a way to read it. `info` is ErrorText.describe().
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: actions

    property var info: ({})
    property bool showDetail: false

    signal retryRequested()
    signal settingsRequested()
    signal copyRequested()
    signal deleteRequested()

    spacing: Kirigami.Units.smallSpacing

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PrimaryButton {
            objectName: "retryButton"
            text: i18n("Try again")
            icon.name: "view-refresh"
            onClicked: actions.retryRequested()
        }

        PC3.Button {
            objectName: "settingsButton"
            visible: actions.info.settings === true
            text: i18n("Open settings")
            icon.name: "configure"
            onClicked: actions.settingsRequested()
        }

        PC3.ToolButton {
            objectName: "detailsButton"
            visible: !!actions.info.detail
            text: actions.showDetail ? i18n("Hide details") : i18n("Show details")
            icon.name: actions.showDetail ? "arrow-up" : "arrow-down"
            onClicked: actions.showDetail = !actions.showDetail
        }

        PC3.ToolButton {
            objectName: "copyErrorButton"
            display: PC3.AbstractButton.IconOnly
            icon.name: copied.running ? "checkmark" : "edit-copy"
            text: copied.running ? i18n("Copied") : i18n("Copy error")
            Accessible.name: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: text
            onClicked: {
                actions.copyRequested();
                copied.restart();
            }
        }

        PC3.ToolButton {
            objectName: "deleteErrorButton"
            display: PC3.AbstractButton.IconOnly
            icon.name: "trash-empty"
            text: i18n("Delete")
            Accessible.name: i18n("Delete this message")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: Accessible.name
            onClicked: actions.deleteRequested()
        }
    }

    Timer {
        id: copied
        interval: 1500
    }

    MonoBlock {
        objectName: "errorDetail"
        visible: actions.showDetail && !!actions.info.detail
        text: actions.info.detail || ""
        maxHeight: Kirigami.Units.gridUnit * 6
    }
}
