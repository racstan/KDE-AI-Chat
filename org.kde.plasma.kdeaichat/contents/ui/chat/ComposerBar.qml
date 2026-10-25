// The line above the message box: what this chat talks to, as
// "Direct · NVIDIA NIM · model", "OpenCode · provider · model · agent build" or
// "Pi · provider · model · thinking high". The values are the chat's effective
// config (EffectiveConfig.js, the same as the Chat info panel). Click it for
// the quick picker (ComposerPicker.qml). The mode is shown, never changed:
// a chat keeps the mode it was started in.
//
// In a narrow popup the provider and the model shrink (with "…") before the
// mode and the variant do; the whole line is in the tooltip.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "EffectiveConfig.js" as EffectiveConfig
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Item {
    id: bar
    objectName: "composerBar"

    property var chat: null
    // Text to show at the end of the line instead of the chat's own variant
    // (the effective config's: a direct chat's or OpenCode's variant, Pi's
    // thinking level, OpenCode's agent); shown when not empty, and wins.
    property string variant: ""

    readonly property alias picker: picker
    readonly property alias tooltip: tip

    // Asks the widget to open the Chat info panel.
    signal chatInfoRequested()

    readonly property var effective: chat && typeof chat.effectiveConfig === "function"
        ? chat.effectiveConfig(chat.currentSessionId) : ({"mode": "provider", "provider": "", "model": "", "agent": "", "thinking": ""})
    readonly property string variantText: EffectiveConfig.variantText(effective, variant)
    function providerName(id) {
        return effective.mode === "provider" && chat ? chat.providerDisplayName(id) : id;
    }
    readonly property string fullText: EffectiveConfig.describe(effective, providerName, {"directLabel": i18n("Direct"), "variant": variantText})
        || i18n("No model chosen yet")
    // [{text, grows}]: the pieces of the line.
    readonly property var segments: {
        var list = [];
        list.push({"text": effective.mode === "opencode" ? "OpenCode" : effective.mode === "pi" ? "Pi" : i18n("Direct"), "grows": false});
        if (effective.provider)
            list.push({"text": providerName(effective.provider), "grows": true});
        if (effective.model)
            list.push({"text": effective.model, "grows": true});
        if (variantText !== "")
            list.push({"text": variantText, "grows": false});
        return list;
    }

    Layout.fillWidth: true
    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
    implicitHeight: Kirigami.Units.gridUnit * 1.5
    Accessible.role: Accessible.Button
    Accessible.name: i18n("Chat model: %1. Click to change it.", fullText)

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, mouse.pressed ? 0.12 : mouse.containsMouse ? 0.07 : 0)
    }

    RowLayout {
        id: line
        objectName: "composerBarLine"
        anchors.left: parent.left
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.right: chevron.left
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        Repeater {
            model: bar.segments

            delegate: PC3.Label {
                id: segment

                required property var modelData
                required property int index

                objectName: "composerBarSegment"
                text: (index > 0 ? " · " : "") + modelData.text
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: index === 0 ? 0.85 : 0.7
                Layout.fillWidth: modelData.grows
                // Rounded up: a layout rounds down, and a hair too narrow elides.
                Layout.preferredWidth: Math.ceil(implicitWidth)
                Layout.maximumWidth: Math.ceil(implicitWidth)
                Layout.minimumWidth: modelData.grows ? Math.min(Math.ceil(implicitWidth), Kirigami.Units.gridUnit * 4) : Math.ceil(implicitWidth)
            }
        }

        // Takes what the pieces don't need, so they stay together at the left.
        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.minimumWidth: 0
        }
    }

    Kirigami.Icon {
        id: chevron
        source: "arrow-up"
        opacity: 0.5
        anchors.right: parent.right
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.iconSizes.small
        height: Kirigami.Units.iconSizes.small
    }

    MouseArea {
        id: mouse
        objectName: "composerBarButton"
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: picker.opened ? picker.close() : picker.open()

        QQC2.ToolTip {
            id: tip
            objectName: "composerBarTip"
            // Never over the open picker: it would be drawn on top of its list.
            visible: mouse.containsMouse && !mouse.pressed && !picker.visible
            delay: Kirigami.Units.toolTipDelay
            text: bar.fullText + "\n" + i18n("Click to change the model for this chat.")
        }
    }

    ComposerPicker {
        id: picker
        chat: bar.chat
        onChatInfoRequested: bar.chatInfoRequested()
    }
}
