// What an agent did for a reply (tools, changed files, notices), collapsed
// to a one-line summary ("4 steps · 1 failed") until opened. Opened, each
// tool is a ToolCard and notices and changed files are one line each. Fed by
// backends/AgentEvents.js; `items` is its one-line-per-step summary, which
// is all older chats have, so those are listed as plain lines.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: context

    // One summary line per step.
    property var items: []
    // The reply's tool calls: callId -> {name, detail, status, input, output}.
    property var tools: ({})
    property var notices: []
    property var files: []
    property bool expanded: false

    readonly property var toolList: {
        var list = [];
        for (var id in tools)
            list.push(tools[id]);
        return list;
    }
    readonly property bool structured: toolList.length > 0 || notices.length > 0 || files.length > 0
    readonly property int stepCount: structured ? toolList.length + notices.length + files.length : items.length
    readonly property int runningCount: toolList.filter(function(t) { return t.status === "running"; }).length
    readonly property int failedCount: toolList.filter(function(t) { return t.status === "error"; }).length

    // "ℹ text" / "⚠ text" -> text, for the notices AgentEvents.js prefixes.
    function noticeText(line) {
        return String(line).replace(/^[ℹ⚠️\s]+/, "");
    }

    spacing: Kirigami.Units.smallSpacing

    QQC2.AbstractButton {
        id: summary
        objectName: "contextSummary"
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight
        Accessible.name: context.expanded ? i18n("Hide activity") : i18n("Show activity")
        onClicked: context.expanded = !context.expanded

        contentItem: RowLayout {
            id: header
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: context.expanded ? "arrow-down" : "arrow-right"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }

            PC3.Label {
                Layout.fillWidth: true
                text: {
                    var parts = [i18np("1 step", "%1 steps", context.stepCount)];
                    if (context.runningCount > 0)
                        parts.push(i18n("running"));
                    if (context.failedCount > 0)
                        parts.push(i18np("1 failed", "%1 failed", context.failedCount));
                    return parts.join(" · ");
                }
                font: Kirigami.Theme.smallFont
                color: context.failedCount > 0 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                opacity: context.failedCount > 0 ? 1 : 0.7
            }
        }
    }

    Loader {
        active: context.expanded
        visible: active
        Layout.fillWidth: true
        sourceComponent: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: context.structured ? context.toolList : []

                delegate: ToolCard {
                    required property var modelData
                    tool: modelData
                }
            }

            Repeater {
                model: context.structured ? context.notices : []

                delegate: Line {
                    required property string modelData
                    icon: "dialog-information"
                    text: context.noticeText(modelData)
                }
            }

            Repeater {
                model: context.structured ? context.files : []

                delegate: Line {
                    required property string modelData
                    icon: "document-edit"
                    text: modelData
                }
            }

            Repeater {
                model: context.structured ? [] : context.items

                delegate: Line {
                    required property string modelData
                    text: modelData
                }
            }
        }
    }

    component Line: RowLayout {
        property string icon: ""
        property alias text: label.text

        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            visible: parent.icon !== ""
            source: parent.icon
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            opacity: 0.7
        }

        PC3.Label {
            id: label
            Layout.fillWidth: true
            font: Kirigami.Theme.smallFont
            elide: Text.ElideMiddle
            opacity: 0.75
        }
    }
}
