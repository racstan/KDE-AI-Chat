// The editor's live preview, from the helper's schedule_preview: the whole
// schedule in one line, the next three runs, and warnings (clock changes,
// days 29-31, "never runs"). An error from the helper is shown in red.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: preview

    // {ok, error?, summary, rules[], nextRuns[], warnings[]} or null while loading.
    property var result: null
    property ScheduleFormat format: ScheduleFormat {}

    readonly property bool never: result !== null && result.ok === true && (result.nextRuns || []).length === 0

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        objectName: "previewSummary"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.bold: true
        visible: preview.result !== null && preview.result.ok === true
        text: preview.result && preview.result.summary ? preview.result.summary : ""
    }
    QQC2.Label {
        objectName: "previewNext"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        visible: preview.result !== null && preview.result.ok === true
        color: preview.never ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        text: preview.never ? i18n("Never runs")
            : i18n("Next runs: %1", preview.format.runs(preview.result ? preview.result.nextRuns : []))
    }
    Repeater {
        model: preview.result && preview.result.ok ? (preview.result.warnings || []) : []
        delegate: QQC2.Label {
            required property string modelData
            objectName: "previewWarning"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Kirigami.Theme.neutralTextColor
            text: "⚠ " + modelData
        }
    }
    QQC2.Label {
        objectName: "previewError"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        visible: preview.result !== null && preview.result.ok === false
        color: Kirigami.Theme.negativeTextColor
        text: preview.result && preview.result.error ? i18n("Not valid yet: %1", preview.result.error) : ""
    }
}
