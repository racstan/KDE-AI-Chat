// Where this chat's messages go, always in view at the end of the line above
// the message box: an icon and a short label ("OpenRouter · online",
// "Ollama · this computer", "Pi agent"), with the full sentence on hover and
// for screen readers. The wording comes from Privacy.js.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "Privacy.js" as Privacy
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

RowLayout {
    id: badge

    property var chat: null

    readonly property string mode: chat && chat.openCodeMode ? "opencode" : chat && chat.piMode ? "pi" : "provider"
    readonly property string providerId: mode === "provider" && chat ? chat.getEffectiveProvider(chat.currentSessionId) : ""
    readonly property var providerConfig: mode === "provider" && chat ? chat.getProviderConfig(providerId, chat.currentSessionId) : null
    readonly property string name: mode === "opencode" ? "OpenCode" : mode === "pi" ? "Pi" : chat ? chat.providerDisplayName(providerId) : ""
    readonly property var info: Privacy.describe(mode, providerConfig ? providerConfig.baseUrl : "")
    readonly property string place: info.place
    readonly property string shortText: ({
        "here": i18n("%1 · this computer", name),
        "network": i18n("%1 · your network", name),
        "cloud": i18n("%1 · online", name),
        "agent": i18n("%1 agent", name)
    })[place]
    readonly property string detail: ({
        "here": i18n("%1 runs on this computer: your messages don't leave it.", name),
        "network": i18n("%1 runs on your local network: your messages go to that computer, not to the internet.", name),
        "cloud": i18n("%1: your messages are sent to its servers and handled under its terms.", name),
        "agent": i18n("%1 runs on this computer and sends your messages to the model it is set up with, which may be online.", name)
    })[place]

    visible: name !== ""
    spacing: Kirigami.Units.smallSpacing / 2
    // Keeps its whole label; the status text next to it is the one that shortens.
    Layout.maximumWidth: Kirigami.Units.gridUnit * 11
    Layout.minimumWidth: Math.min(implicitWidth, Layout.maximumWidth)
    Layout.preferredWidth: implicitWidth

    // Reachable with Tab: the explanation shows (and is read out) on focus as on hover.
    activeFocusOnTab: true
    Accessible.role: Accessible.StaticText
    Accessible.name: detail
    Accessible.focusable: true

    Kirigami.Icon {
        source: badge.info.icon
        Layout.preferredWidth: Kirigami.Units.iconSizes.small
        Layout.preferredHeight: Kirigami.Units.iconSizes.small
        opacity: 0.7
    }

    PC3.Label {
        objectName: "privacyLabel"
        Layout.fillWidth: true
        text: badge.shortText
        elide: Text.ElideRight
        font: Kirigami.Theme.smallFont
        opacity: badge.activeFocus ? 1 : 0.7
    }

    HoverHandler { id: hover }
    QQC2.ToolTip.visible: hover.hovered || badge.activeFocus
    QQC2.ToolTip.text: badge.detail
}
