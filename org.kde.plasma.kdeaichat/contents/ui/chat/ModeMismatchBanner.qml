// Tells the user that the open chat is in another mode than the one Settings
// now selects for new chats. A chat never changes mode (chat/EffectiveConfig.js),
// so the way to the new mode is a new chat; the banner offers one. It can be
// dismissed for this chat (until the configured mode changes again).
import QtQuick
import "EffectiveConfig.js" as EffectiveConfig
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

NoticeBanner {
    id: banner

    // main.qml (or a stand-in): plasmoid.configuration, effectiveConfig(), currentSessionId, createSession().
    property var chat: null
    // "<chat id>:<new-chat mode>" of the notices the user dismissed.
    property var dismissedKeys: ({})

    readonly property string newMode: chat && chat.plasmoid
        ? EffectiveConfig.mainMode(EffectiveConfig.mainFromConfig(chat.plasmoid.configuration, null)) : ""
    readonly property string chatMode: chat && typeof chat.effectiveConfig === "function"
        ? chat.effectiveConfig(chat.currentSessionId).mode : ""
    readonly property string key: (chat ? chat.currentSessionId : "") + ":" + newMode

    function modeName(mode) {
        return mode === "opencode" ? "OpenCode" : mode === "pi" ? "Pi" : i18n("Direct");
    }

    objectName: "modeMismatchBanner"
    dismissible: true
    actionText: i18n("New chat")
    actionIcon: "list-add"
    text: newMode !== "" && chatMode !== "" && newMode !== chatMode && dismissedKeys[key] !== true
        ? i18n("The mode is now %1. This chat stays in %2 mode, because a chat can't change mode. Start a new chat to use %1.", modeName(newMode), modeName(chatMode))
        : ""
    onActionTriggered: chat.createSession(true)
    onDismissed: {
        var copy = Object.assign({}, dismissedKeys);
        copy[key] = true;
        dismissedKeys = copy;
    }
}
