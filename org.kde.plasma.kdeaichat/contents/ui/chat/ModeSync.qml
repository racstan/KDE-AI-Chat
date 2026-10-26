// Puts the widget in the open chat's mode (provider / OpenCode / Pi) and keeps
// it there. A chat keeps the mode it was started in (chat/EffectiveConfig.js):
// the main mode (Settings -> Connection) only decides the mode of NEW chats, so
// changing it, or the per-chat settings, never moves an open chat to another
// mode, and never touches a reply that is streaming. When one of those settings
// changes, apply() just runs again for the open chat, which re-reads the
// provider, model and agent of the chat's own mode.
import QtQuick
import "EffectiveConfig.js" as EffectiveConfig
import "../ProviderService.js" as ProviderService

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

    // The mode, provider and model a chat really uses: the main settings, the
    // chat's project or the chat's own, per the two "per chat" settings
    // (chat/EffectiveConfig.js has the rules). main.qml's effectiveConfig.
    function effectiveConfig(sessionId) {
        var idx = sync.chat.sessionIndexById(sessionId || sync.chat.currentSessionId);
        var session = idx < 0 ? null : sync.chat.sessions[idx];
        var config = sync.chat.plasmoid.configuration;
        var providerOf = function(id) { return ProviderService.getProviderConfig(id, config); };
        return EffectiveConfig.forSession(config, session, function(id) { return providerOf(id).model; },
                                          function(id) { return providerOf(id).variant; },
                                          sync.chat.projects ? sync.chat.projects.byId(session ? session.projectId : "") : null);
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
        // The workspace is the chat's own, else its project's (chat/Projects.js);
        // none when neither has one. (The main setting only fills it in when a
        // chat is created.)
        sync.chat.openCodeWorkspaceCwd = !session ? ""
            : sync.chat.projects ? sync.chat.projects.workspaceFor(session.value).path : String(session.openCodeWorkspaceCwd || "");
        return eff.mode;
    }

    // The workspace of a new chat: the "Default workspace for new chats" setting.
    function newChatWorkspace() {
        var config = sync.chat && sync.chat.plasmoid ? sync.chat.plasmoid.configuration : null;
        return config ? String(config.openCodeWorkspaceCwd || "").trim() : "";
    }

    // Sets (or, with "", clears) the open chat's workspace folder.
    function chooseWorkspace(path) {
        sync.chat.setSessionProperty(sync.chat.currentSessionId, "openCodeWorkspaceCwd", String(path || ""));
        sync.applyOpenChat();
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
