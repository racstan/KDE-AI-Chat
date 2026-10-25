// The Chat info panel's answer to "which settings does this chat use?": one
// line ("Using Pi · OpenAI · gpt-x (from this chat's settings)") and, when it
// helps, why the main settings apply. `effective` is main.qml's
// effectiveConfig() for the chat (chat/EffectiveConfig.js).
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "EffectiveConfig.js" as EffectiveConfig

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: line

    property var effective: ({"mode": "provider", "provider": "", "model": "", "source": "main"})
    // "Let chats have their own model settings", and whether main settings win.
    property bool perChat: false
    property bool mainWins: false
    // providerId -> name to show, for direct providers.
    property var providerName: function(id) { return id; }

    readonly property string description: EffectiveConfig.describe(line.effective, function(id) {
        return line.effective.mode === "provider" ? line.providerName(id) : id;
    }) || i18n("no model chosen yet")

    spacing: Kirigami.Units.smallSpacing

    PC3.Label {
        objectName: "effectiveLine"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.bold: true
        text: line.effective.source === "chat" ? i18n("Using %1 (from this chat's settings)", line.description)
                                               : i18n("Using %1 (from main settings)", line.description)
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
}
