// One line of Settings → Storage: what it is, how much space it uses, the
// buttons (Open folder; Remove only when it is safe to remove) and a plain
// explanation underneath.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "StorageFormat.js" as Fmt

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: row

    property string title: ""
    property string description: ""
    property double size: 0
    property string folder: ""
    property bool removable: false
    // The size is still being worked out.
    property bool unknown: false

    signal openRequested()
    signal removeRequested()

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            objectName: "storageTitle"
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 4
            text: row.title
            font.bold: true
            wrapMode: Text.Wrap
        }
        QQC2.Label {
            objectName: "storageSize"
            text: row.unknown ? "…" : Fmt.size(row.size)
        }
        QQC2.Button {
            objectName: "storageOpen"
            icon.name: "folder-open"
            text: i18n("Open folder")
            enabled: row.folder !== ""
            onClicked: row.openRequested()
        }
        QQC2.Button {
            objectName: "storageRemove"
            visible: row.removable
            icon.name: "edit-delete"
            text: i18n("Remove…")
            enabled: row.size > 0
            onClicked: row.removeRequested()
        }
    }

    SettingHelp {
        text: row.description
    }
}
