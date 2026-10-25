// One provider in the list of ProvidersPanel.qml: name, model and host, a
// warning if the model is gone or the key is missing, and its buttons.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: row

    property var entry: ({})
    // An image service (AI Horde, Pollinations): its "default" is the one /image uses.
    readonly property bool imageService: entry.type === "image"
    property bool isDefault: false
    property bool local: false
    property bool missingKey: false
    property string host: ""
    // Why the model was found unavailable ("" if it was not).
    property string unavailable: ""
    // Another provider is being edited: editing and removing are off.
    property bool busy: false
    property bool editing: false
    property bool confirmingRemove: false

    signal useByDefault()
    signal edit()
    signal askRemove()
    signal confirmRemove()
    signal cancelRemove()

    Layout.fillWidth: true
    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        visible: !row.editing
        Kirigami.Icon {
            source: row.local ? "computer" : "network-server"
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            QQC2.Label {
                text: row.entry.name + (row.isDefault ? "  · " + (row.imageService ? i18n("used by /image") : i18n("default")) : "")
                font.bold: row.isDefault
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            QQC2.Label {
                objectName: "detailLabel"
                text: (row.entry.model || i18n("no model set")) + " · " + row.host
                    + (row.missingKey ? " · " + i18n("no API key") : "")
                    + (row.imageService && row.entry.accepted !== true ? " · " + i18n("switched off") : "")
                    + (row.unavailable !== "" ? " · " + i18n("model unavailable: %1", row.unavailable) : "")
                color: row.unavailable !== "" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
        QQC2.Button {
            visible: !row.isDefault && !row.confirmingRemove
            text: row.imageService ? i18n("Use for /image") : i18n("Use by default")
            onClicked: row.useByDefault()
        }
        QQC2.ToolButton {
            visible: !row.confirmingRemove
            icon.name: "document-edit"
            enabled: !row.busy
            onClicked: row.edit()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Edit")
            Accessible.name: i18n("Edit %1", row.entry.name)
        }
        QQC2.ToolButton {
            visible: !row.confirmingRemove
            icon.name: "edit-delete"
            enabled: !row.busy
            onClicked: row.askRemove()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Remove")
            Accessible.name: i18n("Remove %1", row.entry.name)
        }
        QQC2.Label {
            visible: row.confirmingRemove
            text: i18n("Remove this provider and its key?")
        }
        QQC2.Button {
            visible: row.confirmingRemove
            text: i18n("Remove")
            icon.name: "edit-delete"
            onClicked: row.confirmRemove()
        }
        QQC2.Button {
            visible: row.confirmingRemove
            text: i18n("Cancel")
            onClicked: row.cancelRemove()
        }
    }

    Kirigami.Separator {
        Layout.fillWidth: true
        opacity: 0.4
    }
}
