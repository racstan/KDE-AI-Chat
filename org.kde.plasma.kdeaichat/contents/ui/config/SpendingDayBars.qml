// Settings -> Spending: one bar per day that has replies this month. A bar is as long as the day's tokens
// compared with the busiest day (plain rectangles, no chart library); the day's cost is written beside it,
// or "cost unknown" when no reply that day reported one.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../chat/ChatStats.js" as Stats
import "../chat/Spending.js" as Spending

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: bars

    // The helper's per-day totals: {"YYYY-MM-DD": {count, input, output, cacheRead, cost, costCount}}.
    property var days: ({})
    readonly property var rows: Spending.dayRows(bars.days)

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: bars.rows

        delegate: RowLayout {
            id: line
            required property var modelData

            readonly property string summary: {
                const cost = line.modelData.costCount > 0 ? Stats.formatCost(line.modelData.cost) : i18n("cost unknown");
                return i18n("%1 tokens · %2", Stats.formatCount(line.modelData.tokens), cost);
            }

            objectName: "spendingDay-" + line.modelData.key
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                horizontalAlignment: Text.AlignRight
                text: line.modelData.label
                textFormat: Text.PlainText
            }
            Rectangle {
                id: track
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 0.8
                radius: height / 2
                color: Kirigami.Theme.alternateBackgroundColor

                Rectangle {
                    objectName: "spendingDayBar"
                    width: track.width * line.modelData.fraction
                    height: track.height
                    radius: track.radius
                    color: Kirigami.Theme.highlightColor
                }
            }
            QQC2.Label {
                objectName: "spendingDayText"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 13
                text: line.summary
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
            }
        }
    }
}
