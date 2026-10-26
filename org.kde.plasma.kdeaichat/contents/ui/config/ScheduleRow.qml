// One schedule in the list: name, chat, when (summary), next run, last
// result, an on/off switch, and Edit / History / Delete. A migrated draft
// that still lacks a chat or a time says so instead of a summary. Delete
// asks first, in the row.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ScheduleDraft.js" as Draft

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QQC2.Frame {
    id: row

    property var item: ({})
    property string chatTitle: ""
    property bool paused: false
    property ScheduleFormat format: ScheduleFormat {}

    signal editRequested()
    signal historyRequested()
    signal deleteRequested()
    signal enabledToggled(bool enabled)

    readonly property bool needsReview: item.needsReview === true
    readonly property var missing: Draft.missingParts(item)
    readonly property var lastResult: format.result(item.runState)
    property bool confirming: false

    function reviewText() {
        var chat = missing.indexOf("chat") >= 0;
        var time = missing.indexOf("time") >= 0;
        if (chat && time)
            return i18n("Needs a chat and a time");
        if (chat)
            return i18n("Needs a chat");
        if (time)
            return i18n("Needs a time");
        if (missing.indexOf("message") >= 0)
            return i18n("Needs a message");
        return i18n("Check it and save it to turn it on");
    }

    Layout.fillWidth: true

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Switch {
                objectName: "scheduleEnabled"
                checked: row.item.enabled === true && !row.needsReview
                enabled: !row.needsReview
                onToggled: row.enabledToggled(checked)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: checked ? i18n("On: runs at the times below") : i18n("Off: never runs")
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Kirigami.Heading {
                    level: 4
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: row.item.name || i18n("Untitled schedule")
                }
                QQC2.Label {
                    objectName: "scheduleChat"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    opacity: 0.75
                    text: row.item.chatId ? i18n("In “%1”", row.chatTitle || i18n("a deleted chat")) : i18n("No chat chosen")
                }
            }
            QQC2.ToolButton {
                objectName: "scheduleEdit"
                icon.name: "document-edit"
                text: row.needsReview ? i18n("Finish…") : ""
                display: row.needsReview ? QQC2.AbstractButton.TextBesideIcon : QQC2.AbstractButton.IconOnly
                onClicked: row.editRequested()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Edit")
            }
            QQC2.ToolButton {
                objectName: "scheduleHistory"
                icon.name: "view-history"
                display: QQC2.AbstractButton.IconOnly
                visible: !row.needsReview
                onClicked: row.historyRequested()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("History")
            }
            QQC2.ToolButton {
                objectName: "scheduleDelete"
                icon.name: "edit-delete"
                display: QQC2.AbstractButton.IconOnly
                onClicked: row.confirming = true
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Delete")
            }
        }

        Kirigami.InlineMessage {
            objectName: "scheduleReview"
            Layout.fillWidth: true
            visible: row.needsReview
            type: Kirigami.MessageType.Warning
            text: i18n("Brought over from the old scheduler. %1.", row.reviewText())
        }

        QQC2.Label {
            objectName: "scheduleSummary"
            Layout.fillWidth: true
            visible: !row.needsReview
            wrapMode: Text.Wrap
            text: row.item.summary || (row.item.warnings && row.item.warnings.length ? row.item.warnings[0] : "")
        }

        QQC2.Label {
            objectName: "scheduleNext"
            Layout.fillWidth: true
            visible: !row.needsReview
            wrapMode: Text.Wrap
            opacity: 0.75
            font: Kirigami.Theme.smallFont
            text: {
                var next;
                if (row.paused)
                    next = i18n("Paused: all schedules are off");
                else if (row.item.enabled !== true)
                    next = i18n("Off");
                else if (row.item.runState && row.item.runState.finished)
                    next = i18n("No more runs");
                else if ((row.item.nextRuns || []).length)
                    next = i18n("Next: %1", row.format.when(row.item.nextRuns[0]));
                else
                    next = i18n("Never runs");
                return next + "  ·  " + row.lastResult.text;
            }
            color: row.lastResult.state === "error" ? Kirigami.Theme.negativeTextColor
                 : row.lastResult.state === "missed" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
        }

        RowLayout {
            objectName: "scheduleConfirm"
            visible: row.confirming
            Layout.fillWidth: true
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("Delete this schedule and its history?")
            }
            QQC2.Button {
                objectName: "scheduleConfirmDelete"
                text: i18n("Delete")
                icon.name: "edit-delete"
                onClicked: {
                    row.confirming = false;
                    row.deleteRequested();
                }
            }
            QQC2.Button {
                text: i18n("Cancel")
                onClicked: row.confirming = false
            }
        }
    }
}
