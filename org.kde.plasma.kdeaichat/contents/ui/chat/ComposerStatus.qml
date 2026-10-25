// The line above the composer's input: what the widget is doing (thinking,
// writing, reading aloud, voice status) or, in a new empty chat, the keys that work.
// It always takes the same height, so the input never jumps when a reply
// starts or ends.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

RowLayout {
    id: status

    property var chat: null
    // What a slash command just did (CommandRunner.qml); wins over the key hint.
    property string notice: ""

    readonly property var voice: chat ? chat.voiceManagerRef : null
    readonly property string voiceText: voice && voice.statusText ? voice.statusText : ""
    readonly property bool busy: !!chat && (chat.loading || (voiceText !== "" && voiceText !== "Reading aloud..." && voiceText !== "Paused" && !voice.callModeActive))
    readonly property bool isNewChat: !!chat && (chat.messages || []).length === 0
    readonly property string text: {
        if (chat.loading)
            return (chat.currentStreamIndex >= 0 ? i18n("Writing…") : i18n("Thinking…")) + " " + i18n("Esc stops it.");
        if (voiceText !== "")
            return voiceText;
        if (notice !== "")
            return notice;
        // The keys are explained once, in a new chat; never in one with messages.
        return status.isNewChat ? i18n("Enter sends · Shift+Enter adds a line · / for commands and templates") : "";
    }

    Layout.fillWidth: true
    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
    spacing: Kirigami.Units.smallSpacing

    PC3.BusyIndicator {
        objectName: "statusSpinner"
        // A reply that has started shows its own spinner in the message.
        running: status.busy && !(status.chat.loading && status.chat.currentStreamIndex >= 0)
        visible: running
        Layout.preferredWidth: Kirigami.Units.iconSizes.small
        Layout.preferredHeight: Kirigami.Units.iconSizes.small
    }

    PC3.ToolButton {
        icon.name: (status.voice && status.voice.callModeActive) ? "call-start" : "media-playback-stop"
        visible: !status.chat.loading && !!status.voice && (status.voiceText === "Reading aloud..." || status.voiceText === "Generating speech..." || status.voice.callModeActive === true)
        display: PC3.AbstractButton.IconOnly
        Layout.preferredHeight: status.height
        Layout.preferredWidth: status.height
        Accessible.name: (status.voice && status.voice.callModeActive) ? i18n("End call mode") : i18n("Stop reading")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
        onClicked: {
            if (status.voice.callModeActive)
                status.voice.stopCallMode();
            else
                status.voice.stopTTS();
            status.chat.playingMessageIndex = -1;
        }
    }

    PC3.Label {
        objectName: "statusText"
        Layout.fillWidth: true
        text: status.text
        elide: Text.ElideRight
        font: Kirigami.Theme.smallFont
        opacity: status.busy || status.voiceText !== "" || status.notice !== "" ? 0.85 : 0.55
    }
}
