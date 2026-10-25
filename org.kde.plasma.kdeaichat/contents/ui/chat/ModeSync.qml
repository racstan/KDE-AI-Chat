// Re-applies the open chat's mode (provider / OpenCode / Pi) when something
// that decides it changes in the settings: the main mode, "Let chats have
// their own model settings" or the priority. main.qml's applySessionSource()
// works out the mode from the stored chat and the configuration
// (chat/EffectiveConfig.js).
import QtQuick

Connections {
    id: sync

    // main.qml (or a stand-in).
    property var chat: null

    function apply() {
        if (sync.chat && typeof sync.chat.applySessionSource === "function")
            sync.chat.applySessionSource(sync.chat.sessions[sync.chat.sessionIndexById(sync.chat.currentSessionId)]);
    }

    target: sync.chat && sync.chat.plasmoid ? sync.chat.plasmoid.configuration : null
    ignoreUnknownSignals: true

    function onUseOpenCodeChanged() { sync.apply(); }
    function onUsePiChanged() { sync.apply(); }
    function onPerChatModelSettingsChanged() { sync.apply(); }
    function onPerChatPriorityChanged() { sync.apply(); }
}
