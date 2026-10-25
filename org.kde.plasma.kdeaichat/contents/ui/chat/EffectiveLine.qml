// The Chat info panel's answer to "which settings does this chat use?": one
// line (mode · provider · model · variant, e.g. "Pi · openai · gpt-5 · thinking
// high", the same words the quick picker shows), where it comes from ("From this
// chat's settings") and, when it helps, why the main settings apply. With a
// `chat`, a "Change…" button opens the quick model/variant picker
// (ComposerPicker.qml) under the line; the mode is shown, never changed.
// `effective` is main.qml's effectiveConfig() for the chat (chat/EffectiveConfig.js).
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "EffectiveConfig.js" as EffectiveConfig

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: line

    // The widget root (the picker's chat); null: no Change… button.
    property var chat: null
    property var effective: ({"mode": "provider", "provider": "", "model": "", "source": "main"})
    // "Let chats have their own model settings", and whether main settings win.
    property bool perChat: false
    property bool mainWins: false
    // providerId -> name to show, for direct providers.
    property var providerName: function(id) { return id; }

    readonly property alias picker: picker
    readonly property string variantText: EffectiveConfig.variantText(line.effective, "")
    readonly property string description: EffectiveConfig.describe(line.effective, function(id) {
        return line.effective.mode === "provider" ? line.providerName(id) : id;
    }, {"directLabel": i18n("Direct"), "variant": variantText}) || i18n("No model chosen yet")

    // The picker saved a choice: the panel reloads its own copy of the settings.
    signal modelChanged()

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            objectName: "effectiveLine"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.bold: true
            text: line.description
        }

        PC3.Button {
            objectName: "changeModelButton"
            visible: line.chat !== null
            text: i18n("Change…")
            icon.name: "configure"
            Accessible.name: i18n("Change the model for this chat")
            onClicked: picker.opened ? picker.close() : picker.open()
        }
    }

    PC3.Label {
        objectName: "effectiveSource"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
        text: line.effective.source === "chat" ? i18n("From this chat's settings") : i18n("From main settings")
    }

    PC3.Label {
        objectName: "effectiveNote"
        visible: text !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
        text: !line.perChat ? i18n("Every chat uses the main settings. Turn on \"Let chats have their own model settings\" in Settings → Chat to change that for this chat.")
            : line.mainWins ? i18n("Main settings win when they differ from a chat's own (Settings → Chat).")
            : ""
    }

    ComposerPicker {
        id: picker
        chat: line.chat
        below: true
        showMoreSettings: false
    }

    Connections {
        target: picker
        function onClosed() {
            line.modelChanged();
        }
    }
}
