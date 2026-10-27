// One timing rule in the schedule editor: its kind (weekly, daily, monthly,
// once, hourly, every N minutes, custom cron) and that kind's fields. Every
// change is emitted as a new rule object (config/ScheduleDraft.js).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ScheduleDraft.js" as Draft

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QQC2.Frame {
    id: ruleRow

    property var rule: ({"kind": "weekly", "days": [], "times": []})
    property var rules: []
    // This rule's one-line summary from the helper's preview ("Mon 16:00").
    property string summary: ""

    signal edited(var rule)
    signal removeRequested()

    readonly property string problem: Draft.ruleProblem(rule)
    readonly property var kindLabels: ({
        "weekly": i18n("Weekly"), "daily": i18n("Every day / every N days"), "monthly": i18n("Monthly"),
        "once": i18n("Once"), "hourly": i18n("Every N hours"), "minutes": i18n("Every N minutes"),
        "cron": i18n("Custom (cron)")
    })

    function emit(next) {
        ruleRow.edited(next);
    }

    function problemText() {
        switch (problem) {
        case "no-days": return i18n("Pick at least one day.");
        case "no-times": return i18n("Add at least one time.");
        case "bad-time": return i18n("A time is not valid. Use 24-hour times such as 09:00.");
        case "too-often": return i18n("Schedules can run at most every 15 minutes.");
        case "bad-cron": return i18n("A cron rule has five fields: minute hour day month weekday.");
        }
        return "";
    }

    Layout.fillWidth: true

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            QQC2.ComboBox {
                Accessible.name: i18n("Schedule type")
                id: kindCombo
                objectName: "ruleKind"
                model: Draft.KINDS.map(function(k) { return {"value": k, "text": ruleRow.kindLabels[k]}; })
                textRole: "text"
                valueRole: "value"
                currentIndex: Math.max(0, Draft.KINDS.indexOf(ruleRow.rule.kind))
                onActivated: ruleRow.emit(Draft.changeKind(ruleRow.rule, currentValue, ruleRow.rules))
            }
            QQC2.Label {
                objectName: "ruleSummary"
                Layout.fillWidth: true
                elide: Text.ElideRight
                opacity: 0.75
                text: ruleRow.summary
            }
            QQC2.ToolButton {
                objectName: "removeRule"
                icon.name: "edit-delete-remove"
                display: QQC2.AbstractButton.IconOnly
                text: i18n("Remove rule")
                visible: ruleRow.rules.length > 1
                onClicked: ruleRow.removeRequested()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: text
            }
        }

        // Weekly: the day chips (Monday first) and presets.
        Flow {
            visible: ruleRow.rule.kind === "weekly"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: Draft.WEEK
                delegate: QQC2.Button {
                    required property int modelData
                    objectName: "dayChip" + modelData
                    checkable: true
                    checked: (ruleRow.rule.days || []).indexOf(modelData) >= 0
                    highlighted: checked
                    icon.name: checked ? "checkmark" : ""
                    implicitWidth: Kirigami.Units.gridUnit * 3.5
                    text: Qt.locale().dayName(modelData, Locale.ShortFormat)
                    onClicked: ruleRow.emit(Draft.toggleDay(ruleRow.rule, modelData))
                }
            }
            QQC2.ToolButton {
                text: i18n("Weekdays")
                onClicked: ruleRow.emit(Draft.setDays(ruleRow.rule, "weekdays"))
            }
            QQC2.ToolButton {
                text: i18n("Every day")
                onClicked: ruleRow.emit(Draft.setDays(ruleRow.rule, "every"))
            }
        }

        // Monthly: the day of the month, or the last day.
        RowLayout {
            visible: ruleRow.rule.kind === "monthly"
            QQC2.Label { text: i18n("On day") }
            QQC2.SpinBox {
                Accessible.name: i18n("Day of the month")
                objectName: "monthDay"
                from: 1
                to: 31
                enabled: ruleRow.rule.day !== "last"
                value: ruleRow.rule.day === "last" ? 31 : (Number(ruleRow.rule.day) || 1)
                onValueModified: ruleRow.emit(Draft.setField(ruleRow.rule, "day", value))
            }
            QQC2.CheckBox {
                objectName: "lastDay"
                text: i18n("Last day of the month")
                checked: ruleRow.rule.day === "last"
                onToggled: ruleRow.emit(Draft.setField(ruleRow.rule, "day", checked ? "last" : 1))
            }
        }

        // Once: a date and a time.
        RowLayout {
            visible: ruleRow.rule.kind === "once"
            QQC2.Label { text: i18n("On") }
            QQC2.TextField {
                Accessible.name: placeholderText
                objectName: "onceDate"
                text: String(ruleRow.rule.at || "").substring(0, 10)
                placeholderText: "2026-11-03"
                implicitWidth: Kirigami.Units.gridUnit * 7
                onEditingFinished: {
                    var date = Draft.normalizeDate(text) || text;
                    ruleRow.emit(Draft.setField(ruleRow.rule, "at", date + "T" + String(ruleRow.rule.at || "T09:00").substring(11, 16)));
                }
            }
            QQC2.Label { text: i18n("at") }
            QQC2.TextField {
                Accessible.name: placeholderText
                objectName: "onceTime"
                text: String(ruleRow.rule.at || "").substring(11, 16)
                placeholderText: "09:00"
                implicitWidth: Kirigami.Units.gridUnit * 4
                onEditingFinished: ruleRow.emit(Draft.setField(ruleRow.rule, "at",
                    String(ruleRow.rule.at || "").substring(0, 10) + "T" + (Draft.normalizeTime(text) || text)))
            }
        }

        // Weekly, daily, monthly: the times.
        RowLayout {
            visible: ruleRow.rule.times !== undefined
            Layout.fillWidth: true
            QQC2.Label {
                Layout.alignment: Qt.AlignTop
                topPadding: Kirigami.Units.smallSpacing
                text: i18n("At")
            }
            ScheduleTimes {
                Layout.fillWidth: true
                times: ruleRow.rule.times || []
                onTimeEdited: (i, text) => ruleRow.emit(Draft.setTime(ruleRow.rule, i, text))
                onTimeRemoved: i => ruleRow.emit(Draft.removeTime(ruleRow.rule, i))
                onTimeAdded: ruleRow.emit(Draft.addTime(ruleRow.rule))
            }
        }

        // The "every N" of each kind.
        RowLayout {
            readonly property var spec: ({
                "daily": ["everyDays", 365, i18n("day(s)")], "weekly": ["everyWeeks", 52, i18n("week(s)")],
                "monthly": ["everyMonths", 12, i18n("month(s)")], "minutes": ["everyMinutes", 59, i18n("minutes")]
            })[ruleRow.rule.kind] || null
            visible: spec !== null
            QQC2.Label { text: i18n("Repeat every") }
            QQC2.SpinBox {
                Accessible.name: i18n("Repeat every")
                objectName: "everyN"
                from: ruleRow.rule.kind === "minutes" ? 15 : 1
                to: parent.spec ? parent.spec[1] : 1
                value: parent.spec ? (Number(ruleRow.rule[parent.spec[0]]) || 1) : 1
                onValueModified: ruleRow.emit(Draft.setField(ruleRow.rule, parent.spec[0], value))
            }
            QQC2.Label { text: parent.spec ? parent.spec[2] : "" }
        }

        // Hourly: the step (divisors of 24), the minute and the hours it runs in.
        GridLayout {
            visible: ruleRow.rule.kind === "hourly"
            columns: 4
            QQC2.Label { text: i18n("Every") }
            QQC2.ComboBox {
                Accessible.name: i18n("Hours between runs")
                objectName: "everyHours"
                model: Draft.HOUR_STEPS.map(function(h) { return i18np("%1 hour", "%1 hours", h); })
                currentIndex: Math.max(0, Draft.HOUR_STEPS.indexOf(Number(ruleRow.rule.everyHours) || 1))
                onActivated: i => ruleRow.emit(Draft.setField(ruleRow.rule, "everyHours", Draft.HOUR_STEPS[i]))
            }
            QQC2.Label { text: i18n("at minute") }
            QQC2.SpinBox {
                Accessible.name: i18n("At minute")
                from: 0
                to: 59
                value: Number(ruleRow.rule.minute) || 0
                onValueModified: ruleRow.emit(Draft.setField(ruleRow.rule, "minute", value))
            }
            QQC2.Label { text: i18n("From hour") }
            QQC2.SpinBox {
                Accessible.name: i18n("From hour")
                from: 0
                to: 23
                value: Number(ruleRow.rule.from) || 0
                onValueModified: ruleRow.emit(Draft.setField(ruleRow.rule, "from", value))
            }
            QQC2.Label { text: i18n("to hour") }
            QQC2.SpinBox {
                Accessible.name: i18n("To hour")
                from: 0
                to: 23
                value: ruleRow.rule.to === undefined ? 23 : Number(ruleRow.rule.to)
                onValueModified: ruleRow.emit(Draft.setField(ruleRow.rule, "to", value))
            }
        }

        // Custom: a five-field cron expression.
        ColumnLayout {
            visible: ruleRow.rule.kind === "cron"
            Layout.fillWidth: true
            QQC2.TextField {
                Accessible.name: i18n("Cron expression")
                objectName: "cronExpr"
                Layout.fillWidth: true
                text: ruleRow.rule.expr || ""
                font.family: "monospace"
                onEditingFinished: ruleRow.emit(Draft.setField(ruleRow.rule, "expr", text.trim()))
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.7
                font: Kirigami.Theme.smallFont
                text: i18n("minute hour day-of-month month weekday, e.g. 0 9 * * 1-5 (09:00 on weekdays)")
            }
        }

        QQC2.Label {
            objectName: "ruleProblem"
            visible: ruleRow.problem !== ""
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Kirigami.Theme.negativeTextColor
            text: ruleRow.problemText()
        }
    }
}
