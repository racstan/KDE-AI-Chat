// Puts the widget in the open chat's mode (provider / OpenCode / Pi) and keeps
// it there. A chat keeps the mode it was started in (chat/EffectiveConfig.js):
// the main mode (Settings -> Connection) only decides the mode of NEW chats, so
// changing it, or the per-chat settings, never moves an open chat to another
// mode, and never touches a reply that is streaming. When one of those settings
// changes, apply() just runs again for the open chat, which re-reads the
// provider, model and agent of the chat's own mode.
import QtQuick
import "EffectiveConfig.js" as EffectiveConfig

Connections {
    id: sync

    // main.qml (or a stand-in): sessions, effectiveConfig(), plasmoid, openCodeMode, piMode, ...
    property var chat: null
    // The chat the widget was last put in; a notice about another chat is dropped.
    property string _appliedSessionId: ""

    // The mode a new chat starts in: the one the main settings select.
    function newChatMode() {
        var config = sync.chat && sync.chat.plasmoid ? sync.chat.plasmoid.configuration : null;
        return EffectiveConfig.mainMode(EffectiveConfig.mainFromConfig(config, null));
    }

    // Puts the widget in the mode of `session` (the open chat). Returns the mode.
    function apply(session) {
        var eff = sync.chat.effectiveConfig(session ? session.value : "");
        var config = sync.chat.plasmoid.configuration;
        if (session && session.value !== sync._appliedSessionId) {
            sync._appliedSessionId = session.value;
            sync.chat.modeNotice = "";
        }
        sync.chat.openCodeMode = eff.mode === "opencode";
        sync.chat.piMode = eff.mode === "pi";
        sync.chat.openCodeAgent = eff.mode === "opencode" ? eff.agent : String(config.openCodeAgent || "");
        sync.chat.openCodeWorkspaceCwd = session && session.openCodeWorkspaceCwd !== undefined
            ? String(session.openCodeWorkspaceCwd || "") : String(config.openCodeWorkspaceCwd || "");
        return eff.mode;
    }

    function applyOpenChat() {
        if (sync.chat && typeof sync.chat.effectiveConfig === "function")
            sync.apply(sync.chat.sessions[sync.chat.sessionIndexById(sync.chat.currentSessionId)]);
    }

    target: sync.chat && sync.chat.plasmoid ? sync.chat.plasmoid.configuration : null
    ignoreUnknownSignals: true

    function onUseOpenCodeChanged() { sync.applyOpenChat(); }
    function onUsePiChanged() { sync.applyOpenChat(); }
    function onPerChatModelSettingsChanged() { sync.applyOpenChat(); }
    function onPerChatPriorityChanged() { sync.applyOpenChat(); }
}
