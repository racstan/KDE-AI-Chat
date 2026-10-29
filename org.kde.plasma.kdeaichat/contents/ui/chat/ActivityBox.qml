// One box per direct or Pi reply for the model's thinking and the steps it
// takes (tool calls, notices, changed files), in the order they happened
// (Activity.js). Collapsed it is one line: what the AI is doing right now while
// the reply streams ("Running read_file…"), or "Thought for 12 s · 3 steps"
// once it is done. Opened, it lists thinking as text and each tool as a
// ToolCard; while streaming the newest thinking grows at the end.
//
// While the reply streams the box stays collapsed unless it is opened: a live
// one-line status doesn't move the text below it, which a growing list would.
// Only `liveText` changes per streamed delta, and only while opened.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "Activity.js" as Activity
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Rectangle {
    id: box

    // The message (a row of chat.messageModel); changes when a step is added or updated.
    property var message: ({})
    property bool streaming: false
    // The reply's thinking so far while it streams (the stream buffer's), "" otherwise.
    property string streamReasoning: ""
    // The reply's text has started.
    property bool writing: false
    property bool expanded: false

    readonly property var list: Activity.items(message)
    readonly property var stats: Activity.summary(list)
    // The thinking that isn't in the list yet.
    readonly property string liveText: streaming ? streamReasoning.substring(Activity.thinkingChars(message.activity)) : ""
    readonly property bool hasContent: list.length > 0 || liveText !== ""

    readonly property string summaryText: {
        var parts = [];
        if (streaming) {
            if (stats.running !== "")
                parts.push(i18n("Running %1…", stats.running));
            else if (liveText !== "" && !writing)
                parts.push(i18n("Thinking…"));
            else
                parts.push(writing ? i18n("Writing…") : i18n("Working…"));
            if (stats.steps > 0)
                parts.push(i18np("1 step", "%1 steps", stats.steps));
        } else {
            if (stats.ms > 0) {
                const secs = Activity.seconds(stats.ms);
                parts.push(secs < 60 ? i18n("Thought for %1 s", secs) : i18n("Thought for %1 min %2 s", Math.floor(secs / 60), secs % 60));
            } else if (list.some(function(i) { return i.kind === "thinking"; })) {
                parts.push(i18n("Thought"));
            }
            if (stats.steps > 0)
                parts.push(i18np("1 step", "%1 steps", stats.steps));
            if (stats.failed > 0)
                parts.push(i18np("1 failed", "%1 failed", stats.failed));
        }
        return parts.join(" · ");
    }

    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.cornerRadius
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        QQC2.AbstractButton {
            id: header
            objectName: "activitySummary"
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight
            focusPolicy: Qt.StrongFocus
            Accessible.role: Accessible.Button
            Accessible.name: (box.expanded ? i18n("Hide activity") : i18n("Show activity")) + ": " + box.summaryText
            onClicked: box.expanded = !box.expanded
            Keys.onReturnPressed: box.expanded = !box.expanded
            Keys.onEnterPressed: box.expanded = !box.expanded

            contentItem: RowLayout {
                id: headerRow
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: box.expanded ? "arrow-down" : "arrow-right"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                PC3.Label {
                    textFormat: Text.PlainText
                    objectName: "activityText"
                    Layout.fillWidth: true
                    text: box.summaryText
                    elide: Text.ElideRight
                    color: box.stats.failed > 0 && !box.streaming ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    opacity: box.stats.failed > 0 && !box.streaming ? 1 : 0.75
                }
            }

            // Shows keyboard focus.
            background: Rectangle {
                radius: Kirigami.Units.cornerRadius
                color: "transparent"
                border.width: header.visualFocus ? 1 : 0
                border.color: Kirigami.Theme.highlightColor
            }
        }

        // Built only while opened.
        Loader {
            active: box.expanded
            visible: active
            Layout.fillWidth: true
            sourceComponent: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: box.list

                    delegate: Loader {
                        id: entry
                        required property var modelData
                        Layout.fillWidth: true
                        sourceComponent: modelData.kind === "tool" ? toolComponent : modelData.kind === "thinking" ? thinkingComponent : lineComponent

                        Component {
                            id: toolComponent
                            ToolCard {
                                tool: entry.modelData.tool
                            }
                        }

                        Component {
                            id: thinkingComponent
                            Thinking {
                                text: entry.modelData.text
                            }
                        }

                        Component {
                            id: lineComponent
                            Line {
                                icon: entry.modelData.kind === "file" ? "document-edit" : entry.modelData.kind === "notice" ? "dialog-information" : ""
                                text: entry.modelData.kind === "notice" ? String(entry.modelData.text).replace(/^[ℹ⚠️\s]+/, "") : entry.modelData.text
                            }
                        }
                    }
                }

                // Thinking that is still arriving.
                Thinking {
                    visible: box.liveText !== ""
                    text: box.liveText
                }
            }
        }
    }

    // A stretch of thinking: plain text with a quiet bar at its side.
    component Thinking: RowLayout {
        property alias text: body.text

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 2
            radius: 1
            color: Kirigami.Theme.textColor
            opacity: 0.2
        }

        PC3.Label {
            id: body
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            font: Kirigami.Theme.smallFont
            opacity: 0.8
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
