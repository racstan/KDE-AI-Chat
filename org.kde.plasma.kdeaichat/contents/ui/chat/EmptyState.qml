// What an empty chat shows: who you are talking to (and whether your
// messages leave the computer), a hint, and a few starting points. Starting
// points are the prompt templates from the settings; a chip puts the
// template's text in the input for you to change and send.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "Privacy.js" as Privacy
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Item {
    id: empty

    property var chat: null

    readonly property string mode: chat && chat.openCodeMode ? "opencode" : chat && chat.piMode ? "pi" : "provider"
    readonly property string providerId: mode === "provider" && chat ? chat.getEffectiveProvider(chat.currentSessionId) : ""
    readonly property var providerConfig: mode === "provider" && chat ? chat.getProviderConfig(providerId, chat.currentSessionId) : null
    readonly property string providerName: mode === "opencode" ? "OpenCode" : mode === "pi" ? "Pi" : chat ? chat.providerDisplayName(providerId) : ""
    readonly property string modelName: providerConfig && providerConfig.model ? providerConfig.model : ""
    // Where the messages go: this computer, the local network, online, or an agent (Privacy.js).
    readonly property var privacy: Privacy.describe(mode, providerConfig ? providerConfig.baseUrl : "")

    readonly property var templates: chat && chat.promptTemplates ? chat.promptTemplates : []
    // Shown when no templates are set up.
    readonly property var examples: [
        {"name": i18n("Explain something simply"), "prompt": i18n("Explain this in simple terms: ")},
        {"name": i18n("Help me write"), "prompt": i18n("Help me write ")},
        {"name": i18n("Brainstorm ideas"), "prompt": i18n("Give me ten ideas for ")}
    ]
    readonly property var starters: (templates.length > 0 ? templates : examples).slice(0, 6)

    function useStarter(prompt) {
        chat.chatInputText = prompt;
        chat.focusInput();
    }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 28)
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Icon {
            source: "dialog-messages"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            opacity: 0.6
        }

        Kirigami.Heading {
            objectName: "emptyTitle"
            level: 2
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: empty.modelName !== "" ? i18n("Chat with %1", empty.modelName) : i18n("Start a conversation")
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: empty.privacy.icon
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                opacity: 0.7
            }

            PC3.Label {
                objectName: "emptyProvider"
                text: empty.privacy.place === "agent" ? i18n("%1 agent · runs here, sends your messages to its model", empty.providerName)
                    : empty.privacy.place === "here" ? i18n("%1 · runs on this computer", empty.providerName)
                    : empty.privacy.place === "network" ? i18n("%1 · runs on your local network", empty.providerName)
                    : i18n("%1 · your messages are sent to its servers", empty.providerName)
                opacity: 0.7
                elide: Text.ElideRight
                Layout.maximumWidth: column.width - Kirigami.Units.iconSizes.small - Kirigami.Units.smallSpacing
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: i18n("Ask a question, drop in a file, or start from one of these. Type / in the box for your templates.")
            opacity: 0.8
        }

        // An incognito chat (chat/Incognito.qml) says what that means.
        PC3.Label {
            objectName: "incognitoHint"
            visible: !!empty.chat && !!empty.chat.incognito && empty.chat.incognito.active
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.bold: true
            text: i18n("Incognito: this chat is never saved, uses no memories and adds none. It is gone when you leave it.")
        }

        // The chips are centred as one row, wrapping when they don't fit.
        // `measure` is a copy of the row, only to know how wide it wants to be.
        Row {
            id: measure
            visible: false
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: empty.starters
                delegate: PC3.Button {
                    required property var modelData
                    text: modelData.name
                }
            }
        }

        Flow {
            id: chips
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(Math.ceil(measure.implicitWidth), column.width)
            spacing: Kirigami.Units.smallSpacing
            visible: empty.starters.length > 0

            Repeater {
                model: empty.starters

                delegate: PC3.Button {
                    required property var modelData
                    objectName: "starterChip"
                    text: modelData.name
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: modelData.prompt
                    Accessible.name: i18n("Start with %1", modelData.name)
                    onClicked: empty.useStarter(modelData.prompt)
                }
            }
        }
    }
}
