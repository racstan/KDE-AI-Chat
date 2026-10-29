// What this chat has used so far, for the Chat info panel: messages, token
// totals, cost, the models that answered and when. Everything is summed from
// what the providers reported on each reply (ChatStats.js); nothing is
// estimated, so a figure the provider never gave is simply left out.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "ChatStats.js" as Stats

ColumnLayout {
    id: summary

    // The chat's messages (the live list) and its creation / last update (ms).
    property var messages: []
    property real createdAt: 0
    property real updatedAt: 0

    readonly property var stats: Stats.summarize(messages, {"createdAt": createdAt, "updatedAt": updatedAt})
    readonly property int unreported: stats.replies - stats.repliesWithUsage
    readonly property bool tokensKnown: stats.hasTokens || stats.replies === 0

    function dateText(ms) {
        return ms > 0 ? new Date(ms).toLocaleString(Qt.locale(), Locale.ShortFormat) : i18n("Unknown");
    }

    // The provider's count; "Not reported" for a chat whose replies carried none.
    function tokenText(count) {
        return tokensKnown ? Stats.formatCount(count) : i18n("Not reported");
    }

    // One line: a grey label and its value.
    component Stat: RowLayout {
        property string label
        property string value
        property string valueName
        property real valueOpacity: 1

        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        PC3.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            Layout.alignment: Qt.AlignTop
            text: label
            wrapMode: Text.Wrap
            color: Kirigami.Theme.disabledTextColor
        }
        PC3.Label {
            objectName: valueName
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            text: value
            wrapMode: Text.Wrap
            opacity: valueOpacity
        }
    }

    spacing: Kirigami.Units.smallSpacing

    Stat {
        label: i18n("Messages")
        valueName: "messagesValue"
        value: Stats.formatCount(summary.stats.messages)
    }

    Stat {
        label: i18n("Input tokens")
        valueName: "inputValue"
        value: summary.tokenText(summary.stats.inputTokens)
        valueOpacity: summary.tokensKnown ? 1 : 0.6
    }

    Stat {
        label: i18n("Output tokens")
        valueName: "outputValue"
        value: summary.tokenText(summary.stats.outputTokens)
        valueOpacity: summary.tokensKnown ? 1 : 0.6
    }

    Stat {
        visible: summary.stats.hasCost
        label: i18n("Total cost")
        valueName: "costValue"
        value: Stats.formatCost(summary.stats.cost)
    }

    Stat {
        visible: summary.stats.models.length > 0
        label: i18ncp("Chat info: the models used in this chat", "Model", "Models", summary.stats.models.length)
        valueName: "modelsValue"
        value: summary.stats.models.join("\n")
    }

    Stat {
        label: i18n("Created")
        valueName: "createdValue"
        value: summary.dateText(summary.stats.createdAt)
    }

    Stat {
        label: i18n("Last active")
        valueName: "lastValue"
        value: summary.dateText(summary.stats.lastActive)
    }

    PC3.Label {
        objectName: "unreportedNote"
        visible: summary.unreported > 0 && summary.stats.replies > 0
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        text: i18np("The provider gave no usage for 1 reply, so it isn't counted.",
                    "The provider gave no usage for %1 replies, so they aren't counted.", summary.unreported)
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }
}
