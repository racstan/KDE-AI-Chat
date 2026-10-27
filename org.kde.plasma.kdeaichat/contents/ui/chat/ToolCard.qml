// One tool call an agent made: the tool's name, a short summary of its
// input, its status (running, done, failed) and, when opened, the input and
// output. Takes one entry of a reply's `tools`
// ({name, detail, status: "running"|"done"|"error", input, output}, see
// backends/AgentEvents.js).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Rectangle {
    id: card

    property var tool: ({})
    property bool expanded: false

    readonly property string status: tool.status || "running"
    readonly property bool running: status === "running"
    readonly property bool failed: status === "error"
    readonly property bool hasOutput: !!(tool.output || (tool.input && tool.input !== "{}"))
    // The small font in the fixed-width family.
    readonly property font monoFont: {
        var small = Kirigami.Theme.smallFont;
        var family = Kirigami.Theme.fixedWidthFont.family;
        return small.pixelSize > 0 ? Qt.font({"family": family, "pixelSize": small.pixelSize}) : Qt.font({"family": family, "pointSize": small.pointSize});
    }
    // The input as indented JSON when it parses (it's cut at 4,000 characters, so may not).
    readonly property string inputText: {
        var raw = String(tool.input || "");
        try {
            return JSON.stringify(JSON.parse(raw), null, 2);
        } catch (e) {
            return raw;
        }
    }
    readonly property color tone: failed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor

    // Breeze icons for the usual tool names; anything else gets a generic one.
    readonly property string toolIcon: {
        var name = String(tool.name || "").toLowerCase();
        if (/bash|shell|command|exec|run/.test(name))
            return "utilities-terminal-symbolic";
        if (/edit|write|patch|apply/.test(name))
            return "document-edit";
        if (/read|view|open|cat/.test(name))
            return "document-open";
        if (/grep|glob|find|search|list|ls/.test(name))
            return "edit-find";
        if (/web|fetch|http|url/.test(name))
            return "internet-services";
        return "configure";
    }

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.cornerRadius
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
    border.width: failed ? 1 : 0
    border.color: Kirigami.Theme.negativeTextColor

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        QQC2.AbstractButton {
            id: head
            objectName: "toolHead"
            Layout.fillWidth: true
            implicitHeight: headRow.implicitHeight
            enabled: card.hasOutput
            hoverEnabled: true
            Accessible.name: i18n("%1, %2", card.tool.name || i18n("Tool"), card.running ? i18n("running") : card.failed ? i18n("failed") : i18n("done"))
            Accessible.description: card.tool.detail || ""
            onClicked: card.expanded = !card.expanded

            contentItem: RowLayout {
                id: headRow
                spacing: Kirigami.Units.smallSpacing

                Item {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small

                    PC3.BusyIndicator {
                        objectName: "toolRunning"
                        anchors.fill: parent
                        visible: card.running
                        running: card.running
                    }

                    Kirigami.Icon {
                        objectName: "toolStatusIcon"
                        anchors.fill: parent
                        visible: !card.running
                        source: card.failed ? "dialog-error" : "dialog-ok-apply"
                        color: card.failed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
                    }
                }

                Kirigami.Icon {
                    source: card.toolIcon
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    opacity: 0.7
                }

                PC3.Label {
                    text: card.tool.name || i18n("Tool")
                    font.bold: true
                }

                PC3.Label {
                    objectName: "toolDetail"
                    Layout.fillWidth: true
                    text: card.tool.detail || ""
                    font: card.monoFont
                    elide: Text.ElideMiddle
                    opacity: 0.75
                }

                Kirigami.Icon {
                    visible: card.hasOutput
                    source: card.expanded ? "arrow-up" : "arrow-down"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    opacity: 0.6
                }
            }
        }

        Loader {
            active: card.expanded && card.hasOutput
            visible: active
            Layout.fillWidth: true
            sourceComponent: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    visible: !!card.tool.input && card.tool.input !== "{}"
                    text: i18n("Input")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }

                MonoBlock {
                    objectName: "toolInput"
                    visible: !!card.tool.input && card.tool.input !== "{}"
                    text: card.inputText
                    maxHeight: Kirigami.Units.gridUnit * 5
                }

                PC3.Label {
                    visible: !!card.tool.output
                    text: card.failed ? i18n("Error") : i18n("Output")
                    font: Kirigami.Theme.smallFont
                    color: card.tone
                    opacity: card.failed ? 1 : 0.7
                }

                MonoBlock {
                    objectName: "toolOutput"
                    visible: !!card.tool.output
                    text: card.tool.output || ""
                    textColor: card.tone
                }
            }
        }
    }
}
