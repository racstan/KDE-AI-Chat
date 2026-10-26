// One schedule's run history (schedule_history), newest first: when, for
// which planned time, and what happened.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: history

    property string title: ""
    // The run state from schedule_history, or null while loading.
    property var runState: null
    property ScheduleFormat format: ScheduleFormat {}
    signal closeRequested()

    readonly property var entries: runState && runState.history ? runState.history.slice().reverse() : []

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        Kirigami.Heading {
            level: 3
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: i18n("History: %1", history.title || i18n("Untitled schedule"))
        }
        QQC2.Button {
            objectName: "historyClose"
            text: i18n("Back")
            icon.name: "go-previous"
            onClicked: history.closeRequested()
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: history.runState !== null
        opacity: 0.75
        text: history.runState ? i18np("Ran once", "Ran %1 times", history.runState.runCount || 0) : ""
    }

    Kirigami.PlaceholderMessage {
        objectName: "historyEmpty"
        Layout.fillWidth: true
        visible: history.runState !== null && history.entries.length === 0
        text: i18n("Nothing has run yet")
    }

    Repeater {
        model: history.entries
        delegate: RowLayout {
            id: entry
            required property var modelData
            objectName: "historyEntry"
            Layout.fillWidth: true
            QQC2.Label {
                text: history.format.when(entry.modelData.at)
                Layout.preferredWidth: Kirigami.Units.gridUnit * 9
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: entry.modelData.status === "ok" ? Kirigami.Theme.positiveTextColor
                     : /^error/.test(entry.modelData.status) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                text: history.format.status(entry.modelData)
                    + (entry.modelData.scheduledFor && entry.modelData.scheduledFor.substring(0, 16) !== String(entry.modelData.at).substring(0, 16)
                       ? "  (" + i18n("planned for %1", history.format.when(entry.modelData.scheduledFor)) + ")" : "")
            }
        }
    }
}
