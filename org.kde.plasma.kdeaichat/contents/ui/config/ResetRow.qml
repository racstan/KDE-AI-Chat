// A setting's control with a small "Reset to default" button after it,
// enabled only while the setting differs from its default. The control
// goes inside, like in a RowLayout; `changed` says whether it differs and
// `reset()` is emitted by the button.
//
//     Config.ResetRow {
//         Kirigami.FormData.label: i18n("Text size:")
//         changed: form.fontScale !== 100
//         onReset: form.fontScale = 100
//         QQC2.SpinBox { ... }
//     }
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

RowLayout {
    id: row

    // Whether the setting differs from its default.
    property bool changed: false
    default property alias content: holder.data
    readonly property alias resetButton: button

    signal reset()

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        id: holder
        spacing: Kirigami.Units.smallSpacing
    }

    QQC2.ToolButton {
        id: button
        objectName: "resetButton"
        icon.name: "edit-undo"
        display: QQC2.AbstractButton.IconOnly
        enabled: row.changed
        text: i18n("Reset to default")
        Accessible.name: text
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: text
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        onClicked: row.reset()
    }
}
