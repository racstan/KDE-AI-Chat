// A rule's list of times ("HH:MM"): one small field per time, a remove
// button next to each (when there is more than one) and "Add time".
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ScheduleDraft.js" as Draft

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Flow {
    id: flow

    property var times: []
    signal timeEdited(int index, string text)
    signal timeRemoved(int index)
    signal timeAdded()

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: flow.times
        delegate: RowLayout {
            id: timeItem
            required property string modelData
            required property int index
            spacing: 0

            QQC2.TextField {
                id: field
                objectName: "ruleTime"
                text: timeItem.modelData
                implicitWidth: Kirigami.Units.gridUnit * 4
                horizontalAlignment: Text.AlignHCenter
                inputMethodHints: Qt.ImhPreferNumbers
                placeholderText: "09:00"
                readonly property bool bad: text.length > 0 && Draft.normalizeTime(text) === ""
                color: bad ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                onEditingFinished: {
                    if (text !== timeItem.modelData)
                        flow.timeEdited(timeItem.index, text);
                }
                QQC2.ToolTip.visible: bad && activeFocus
                QQC2.ToolTip.text: i18n("Type a 24-hour time such as 09:00 or 16:30")
            }
            QQC2.ToolButton {
                visible: flow.times.length > 1
                icon.name: "list-remove"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Remove time")
                onClicked: flow.timeRemoved(timeItem.index)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: text
            }
        }
    }

    QQC2.ToolButton {
        objectName: "addTime"
        visible: flow.times.length < 24
        icon.name: "list-add"
        text: i18n("Add time")
        onClicked: flow.timeAdded()
    }
}
