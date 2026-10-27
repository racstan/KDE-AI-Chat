// Incognito chats: a chat that is never written to disk. It lives only in
// chat.sessions (marked `incognito: true`, id "s-incognito-…") while it is
// open, in the main mode, and is gone when you leave it (another chat, a new
// chat, its close button) or when the widget restarts.
//
// What keeps it off the disk:
//   - chat/Sessions.qml stores storable(chat.sessions), which leaves it out,
//     and doesn't call the store at all when only it changed; lastSessionId is
//     never set to it. store/ChatStore.qml skips incognito chats as well.
//   - No memory is saved from it, and none are used in it (chat/Memory.qml):
//     nothing personal goes in or out.
//   - The model is not asked to name it (chat/SessionTitles.qml); no schedule
//     can target it (chat/ScheduleOverlay.qml); it isn't in the history or in
//     search; notifications don't show its text (chat/Notifier.qml).
//   - Pi runs it without a session file (pi_bridge_server.py, --no-session);
//     OpenCode's copy of its session is deleted when it closes.
//   - Pictures in it are files (the widget shows images from files) under
//     images/<its id>/, deleted when it closes, and at the next start if the
//     widget ended with it open (helper incognito_cleanup).
//
// Leaving one that has messages asks first (chat/IncognitoLeaveDialog.qml,
// which sets `confirmer`), unless "don't ask again" turned
// incognitoAskBeforeLeaving off. `chat` is the widget root (main.qml).
import QtQuick
import "../backends/OpenCodeBackend.js" as OpenCodeBackend

QtObject {
    id: incognito

    property var chat: null
    readonly property string prefix: "s-incognito-"
    // The open chat is an incognito one.
    readonly property bool active: !!chat && isIncognito(chat.currentSessionId)
    // Settings → Chat, "Ask before leaving one that has messages" (read when leaving).
    function askBeforeLeaving() {
        return !chat || !chat.plasmoid || chat.plasmoid.configuration.incognitoAskBeforeLeaving !== false;
    }
    // The dialog that asks before leaving, while the popup's content exists. Without one nothing asks.
    property var confirmer: null
    // Asking whether to leave: the dialog shows.
    signal leaveRequested()

    property var _pending: null
    property bool _leaving: false
    // The chats storable() gave the store last time.
    property var _lastStored: null

    function isIncognito(id) {
        return String(id || "").indexOf(prefix) === 0;
    }

    function makeId() {
        return prefix + Date.now() + "-" + Math.floor(Math.random() * 100000);
    }

    // The chats to store: `sessions` without incognito ones. With an incognito
    // chat among them, null when the others are the very ones stored last
    // time (only the incognito chat changed): then the store isn't called.
    function storable(sessions) {
        var list = sessions || [];
        var kept = list.filter(function(s) { return !!s && !isIncognito(s.value) && s.incognito !== true; });
        var previous = _lastStored;
        _lastStored = kept;
        if (kept.length === list.length)
            return list;
        var same = !!previous && previous.length === kept.length && kept.every(function(s, i) { return s === previous[i]; });
        return same ? null : kept;
    }

    function hasMessages() {
        return active && (chat.messages || []).length > 0;
    }

    // Whether the open chat may be left now. An incognito chat with messages
    // asks first (when the user wants that): false then, and `proceed` runs
    // once they agree.
    function mayLeave(proceed) {
        if (_leaving || !hasMessages() || !askBeforeLeaving() || !confirmer)
            return true;
        _pending = proceed;
        leaveRequested();
        return false;
    }

    function confirmLeave(dontAskAgain) {
        if (dontAskAgain && chat && chat.plasmoid)
            chat.plasmoid.configuration.incognitoAskBeforeLeaving = false;
        var proceed = _pending;
        _pending = null;
        if (!proceed)
            return;
        _leaving = true;
        try {
            proceed();
        } finally {
            _leaving = false;
        }
    }

    function cancelLeave() {
        _pending = null;
    }

    // Opens a new incognito chat (in the main mode).
    function start() {
        if (chat && !chat.loading)
            chat.createSession(true, "", true);
    }

    // Leaves the open incognito chat for the latest chat in the list (or a new one).
    function close() {
        if (!active)
            return;
        var next = (chat.sessions || []).filter(function(s) { return !s.archived && !incognito.isIncognito(s.value); })[0];
        if (next)
            chat.switchSession(next.value);
        else
            chat.createSession(true);
    }

    // The open chat changed from `previousId`: an incognito chat it was is dropped.
    function left(previousId) {
        if (!chat || !isIncognito(previousId) || previousId === chat.currentSessionId)
            return;
        var idx = chat.sessionIndexById(previousId);
        var session = idx >= 0 ? chat.sessions[idx] : null;
        var rest = chat.sessions.slice();
        if (idx >= 0) {
            rest.splice(idx, 1);
            chat.sessions = rest;
        }
        _deleteOpenCodeCopy(session);
        cleanup(previousId);
    }

    // Removes the files an incognito chat made (`chatId`), or every one's ("": at start).
    function cleanup(chatId) {
        var store = chat ? chat.store || null : null;
        var directory = chat && chat.chatStore ? chat.chatStore.directory : "";
        if (!store || !store.runHelper || directory === "")
            return;
        var payload = {"directory": directory};
        if (chatId)
            payload.chat = chatId;
        store.runHelper("incognito_cleanup", payload, null);
    }

    // OpenCode keeps sessions on disk itself: the incognito chat's is deleted.
    function _deleteOpenCodeCopy(session) {
        var remote = session ? String(session.openCodeSessionId || "") : "";
        var base = remote && chat.openCodeBaseUrl ? chat.openCodeBaseUrl() : "";
        if (!base)
            return;
        var folder = String(session.openCodeWorkspaceCwd || "");
        var xhr = new XMLHttpRequest();
        xhr.open("DELETE", OpenCodeBackend.url(base, "/session/" + encodeURIComponent(remote), folder), true);
        xhr.send();
    }
}
