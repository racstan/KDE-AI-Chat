// Saves the reply being written every `interval` ms (not every token), so a
// crash or restart keeps what had arrived. Only the open chat is saved, with
// the reply marked streaming: true (chat/ReplyState.js); chat.messages itself
// is not changed, and the normal save at the end of the reply replaces it.
// Works the same in every mode. `chat` is the widget root (main.qml).
import QtQuick
import "ReplyState.js" as ReplyState

QtObject {
    id: partial

    property var chat: null
    property alias interval: saveTimer.interval

    property Timer _timer: Timer {
        id: saveTimer
        interval: 20000
        repeat: true
        running: !!partial.chat && partial.chat.streamingResponse && partial.chat.currentStreamIndex >= 0
        onTriggered: partial.save()
    }

    function save() {
        var c = partial.chat;
        if (c.sessionHistoryLoadBlocked || (c.incognito && c.incognito.isIncognito(c.currentSessionId)))
            return;
        c.streamBuffer.flush();
        var messages = ReplyState.withPartialReply(c.messages, c.currentStreamIndex, c.currentStreamText, c.currentStreamReasoning);
        if (!messages)
            return;
        var list = c.sessions.slice();
        for (var i = 0; i < list.length; i++) {
            if (list[i].value === c.currentSessionId) {
                list[i] = Object.assign({}, list[i], {"messages": messages});
                try { c.store.save(list); } catch (e) { console.error("KDE AI Chat: partial reply save failed:", e); }
                return;
            }
        }
    }
}
