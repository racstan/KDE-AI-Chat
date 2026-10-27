// What happens after chats were loaded from damaged files (store/ChatStore.qml
// keeps copies and never overwrites them): a damaged chat list blocks saving
// until it is rebuilt from the chat files, and a list restored from its backup
// is told to the user once. A chat's mode is never touched here. `chat` is the
// widget root, `sessions` the chat list manager (chat/Sessions.qml).
import QtQuick

QtObject {
    property var chat: null
    property var sessions: null

    // After loadSessions: blocks saving and explains, or says a backup was used.
    function afterLoad() {
        var store = chat.chatStore;
        if (store.indexProblem) {
            chat.sessionHistoryLoadError = i18n("The chat list could not be read, so nothing is saved. A copy was kept next to it."); // qmllint disable unqualified
            chat.sessionHistoryLoadBlocked = true;
        } else if (store.recoveredFromBackup) {
            chat.privacyNotice = i18n("The chat list was damaged and was restored from its backup. A copy of the damaged file was kept."); // qmllint disable unqualified
        }
    }

    // The banner action: rebuild the list from the chat files, else start over
    // (old config history that could not be parsed).
    function resolve() {
        if (chat.chatStore.indexProblem) {
            chat.chatStore.rebuildIndex(function() { sessions.loadSessions(); });
            return;
        }
        chat.sessionHistoryLoadError = "";
        chat.sessionHistoryLoadBlocked = false;
        chat.sessions = [];
        sessions.createSession(true);
    }
}
