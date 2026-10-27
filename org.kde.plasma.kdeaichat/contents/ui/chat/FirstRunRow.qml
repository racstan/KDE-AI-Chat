// One choice on the first-run setup's first screen: an icon, a name and a
// line of detail. The whole row is the button.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.ItemDelegate {
    id: row

    property string title: ""
    property string detail: ""
    property string iconName: "network-server"

    Layout.fillWidth: true
    Accessible.name: row.detail !== "" ? row.title + ", " + row.detail : row.title

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: row.iconName
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            QQC2.Label {
                objectName: "firstRunRowTitle"
                text: row.title
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            QQC2.Label {
                visible: row.detail !== ""
                text: row.detail
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Kirigami.Icon {
            source: "go-next"
            opacity: 0.5
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
    }
}
