// Files waiting to be sent: chips above the message box (a spinner while one
// loads, a thumbnail or icon, a red border and tip when it failed, and a
// button to remove it). Not shown without files. Used by Composer.qml.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.ScrollView {
    id: pending

    property var chat: null

    Layout.fillWidth: true
    visible: pending.chat.attachedFiles.length > 0
    height: Kirigami.Units.gridUnit * 2
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
    QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff

    Row {
        spacing: Kirigami.Units.smallSpacing
        padding: Kirigami.Units.smallSpacing

        Repeater {
            model: pending.chat.attachedFiles

            delegate: Rectangle {
                id: fileChip

                required property var modelData
                required property int index

                width: Math.min(Kirigami.Units.gridUnit * 10, filenameLabel.implicitWidth + Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.smallSpacing * 4)
                height: Kirigami.Units.gridUnit * 1.5
                radius: Kirigami.Units.cornerRadius
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                border.width: 1
                border.color: modelData.error !== "" ? Kirigami.Theme.negativeTextColor : (modelData.warning ? Kirigami.Theme.neutralTextColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15))
                QQC2.ToolTip.visible: fileMouseArea.containsMouse && (modelData.error !== "" || !!modelData.warning)
                QQC2.ToolTip.text: modelData.error !== "" ? modelData.error : (modelData.warning || "")

                MouseArea {
                    id: fileMouseArea

                    anchors.fill: parent
                    hoverEnabled: true
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Item {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small

                        PC3.BusyIndicator {
                            anchors.centerIn: parent
                            visible: fileChip.modelData.loading
                            running: fileChip.modelData.loading
                            width: Kirigami.Units.iconSizes.small
                            height: Kirigami.Units.iconSizes.small
                        }

                        Image {
                            anchors.fill: parent
                            visible: !fileChip.modelData.loading && fileChip.modelData.type === "image"
                            source: fileChip.modelData.content ? ("data:" + (fileChip.modelData.mimeType || "image/png") + ";base64," + fileChip.modelData.content) : ("file://" + fileChip.modelData.path)
                            fillMode: Image.PreserveAspectCrop
                            clip: true
                        }

                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: !fileChip.modelData.loading && fileChip.modelData.type !== "image"
                            source: fileChip.modelData.warning ? "dialog-warning" : pending.chat.fileIconName(fileChip.modelData.name)
                        }
                    }

                    PC3.Label {
                        id: filenameLabel

                        Layout.fillWidth: true
                        text: fileChip.modelData.name
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                    }

                    PC3.ToolButton {
                        icon.name: "dialog-close"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        display: PC3.AbstractButton.IconOnly
                        Accessible.name: i18n("Remove %1", fileChip.modelData.name)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("Remove file")
                        onClicked: pending.chat.removeAttachedFile(fileChip.index)
                    }
                }
            }
        }
    }
}
