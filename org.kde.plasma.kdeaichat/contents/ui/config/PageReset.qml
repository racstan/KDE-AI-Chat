// "Reset this page" at the end of a settings page: puts every setting on
// the page back to its default. Like any change on the page, it is only
// kept when the user presses Apply or OK. `note` says what it leaves alone.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: pageReset

    property string note: ""

    signal reset()

    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.largeSpacing
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            objectName: "pageResetNote"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Puts every setting on this page back to its default. Nothing is kept until you press Apply or OK.")
                + (pageReset.note ? " " + pageReset.note : "")
        }

        QQC2.Button {
            objectName: "pageResetButton"
            text: i18n("Reset this page")
            icon.name: "edit-reset"
            onClicked: pageReset.reset()
        }
    }
}
