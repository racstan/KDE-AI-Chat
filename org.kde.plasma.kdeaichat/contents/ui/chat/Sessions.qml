// The chat list: loads and normalises stored chats, creates, switches,
// archives and deletes chats, keeps per-chat properties and persists them
// through store/Storage.qml. A chat's mode (source) is set when it is created
// and never changes (chat/EffectiveConfig.js). `chat` is the widget root (main.qml).
import QtQuick
import "../Security.js" as Sec
import "EffectiveConfig.js" as EffectiveConfig
import "ReplyState.js" as ReplyState
import "TimeFormat.js" as TimeFormat

QtObject {
    id: manager

    property var chat: null
    property var modeSyncRef: null        // chat/ModeSync.qml: the mode and workspace of new chats
    property var helperCommandsRef: null  // chat/HelperCommands.qml
    property var recovery: HistoryRecovery { chat: manager.chat; sessions: manager }
    property var messagesRef: SessionMessages { chat: manager.chat }   // reads a chat's messages when it is opened

    function makeSessionId() {
        return "s-" + Date.now() + "-" + Math.floor(Math.random() * 100000);
    }

    // Normalises `stored` (chats read from the chat store) or, when it is
    // null, the chat history older versions kept in the widget's config.
    function parseSessions(stored) {
        chat.sessionHistoryLoadError = "";
        chat.sessionHistoryLoadBlocked = false;
        var raw = stored ? "" : String(chat.plasmoid.configuration.chatSessionsJson || "[]");
        if (raw.length > 25000000) {
            chat.sessionHistoryLoadError = "Stored chat history is too large to load safely.";
            chat.sessionHistoryLoadBlocked = true;
            return [];
        }
        try {
            var arr = stored || JSON.parse(raw);
            if (!Array.isArray(arr)) return [];
            var valid = [];
            var seenIds = {};
            for (var i = 0; i < arr.length; i++) {
                if (!arr[i] || typeof arr[i] !== "object") continue;
                var session = arr[i];
                session.value = Sec.validateSessionId(session.value) || manager.makeSessionId();
                while (seenIds[session.value]) session.value = manager.makeSessionId();
                seenIds[session.value] = true;
                messagesRef.normalise(session);
                if (session.archived === undefined) session.archived = false;
                if (!EffectiveConfig.isMode(session.source)) {
                    session.source = EffectiveConfig.inferSource(session);
                    chat.sessionSourceInferred = true;
                }
                if (!session.updatedAt) session.updatedAt = session.createdAt || Date.now();
                valid.push(session);
            }
            return valid;
        } catch (e) {
            chat.sessionHistoryLoadError = "Stored chat history could not be parsed. It was left untouched.";
            chat.sessionHistoryLoadBlocked = true;
            return [];
        }
    }

    // An incognito chat (chat/Incognito.qml) is left out, and never remembered as the last one.
    // `changedIds` (optional): ids of the chats whose messages changed, so the store
    // need not compare every chat ([] when only chat settings changed).
    function persistSessions(changedIds) {
        if (chat.sessionHistoryLoadBlocked)
            return;
        var incognito = chat.incognito || null;
        try {
            var kept = incognito ? incognito.storable(chat.sessions) : chat.sessions;
            if (kept !== null)
                chat.store.save(kept, false, changedIds);
            if (!incognito || !incognito.isIncognito(chat.currentSessionId))
                chat.plasmoid.configuration.lastSessionId = chat.currentSessionId;
        } catch (e) {
            console.error("KDE AI Chat: failed to persist sessions:", e);
        }
    }

    function sortSessionsByUpdated() {
        var copy = chat.sessions.slice();
        copy.sort(function(a, b) {
            if (!!a.archived !== !!b.archived)
                return a.archived ? 1 : -1;

            return (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0);
        });
        chat.sessions = copy;
    }

    function sessionSubtitle(sessionData) {
        var parts = [];
        if (sessionData.source === "opencode")
            parts.push("OpenCode");
        if (sessionData.archived)
            parts.push("Archived");
        parts.push("Updated " + TimeFormat.formatDateTime(sessionData.updatedAt || sessionData.createdAt || Date.now()));
        return parts.join(" · ");
    }

    function sessionIndexById(sessionId) {
        for (var i = 0; i < chat.sessions.length; i++) {
            if (chat.sessions[i].value === sessionId)
                return i;
        }
        return -1;
    }

    // Session overrides are deliberately stored on the session object rather
    // than in global plasmoid configuration.  This makes provider/model
    // changes apply to the current chat immediately without affecting other
    // chats.
    function getSessionProperty(sessionId, key, defaultValue) {
        var idx = manager.sessionIndexById(sessionId || chat.currentSessionId);
        if (idx < 0 || !chat.sessions[idx] || chat.sessions[idx][key] === undefined || chat.sessions[idx][key] === null)
            return defaultValue;
        return chat.sessions[idx][key];
    }

    function setSessionProperty(sessionId, key, value) {
        var idx = manager.sessionIndexById(sessionId || chat.currentSessionId);
        if (idx < 0 || key === "source")
            return;
        var updated = chat.sessions.slice();
        var session = Object.assign({}, updated[idx]);
        session[key] = value;
        updated[idx] = session;
        chat.sessions = updated;
        manager.persistSessions([]);
    }

    // Apply a dialog's complete draft in one model update.  Per-chat settings
    // are shown in the history sidebar, so assigning chat.sessions once is
    // important: a dozen individual writes otherwise rebuild that ListView
    // a dozen times and can make plasmashell appear hung.
    function setSessionOverrides(sessionId, overrides) {
        var idx = manager.sessionIndexById(sessionId || chat.currentSessionId);
        if (idx < 0 || !overrides)
            return false;

        var updated = chat.sessions.slice();
        var session = Object.assign({}, updated[idx]);
        var changed = false;
        for (var key in overrides) {
            // A chat's mode (source) is set when it is created and never changes.
            if (!Object.prototype.hasOwnProperty.call(overrides, key) || key === "source")
                continue;
            if (session[key] !== overrides[key])
                changed = true;
            session[key] = overrides[key];
        }
        if (!changed)
            return true;
        if (session.value === chat.currentSessionId) {
            session.messages = chat.messages.slice();
            session.text = chat.currentSessionTitle || session.text;
        }

        updated[idx] = session;
        chat.sessions = updated;
        if (session.value === chat.currentSessionId)
            chat.applySessionSource(session);
        manager.persistSessions();
        return true;
    }

    // projectId: the project the chat starts in ("" = none). The mode is the
    // main one either way; a project with a folder gives the chat its folder.
    // incognito: a chat that is never stored (chat/Incognito.qml).
    function createSession(switchToNew, projectId, incognito) {
        var guard = chat.incognito || null;
        if (switchToNew && guard && !guard.mayLeave(function() { manager.createSession(switchToNew, projectId, incognito); }))
            return;
        if (switchToNew && chat.loading)
            chat.invalidateActiveRequest(false);
        var previousId = chat.currentSessionId;
        var project = projectId && chat.projects && !incognito ? chat.projects.byId(projectId) : null;
        var s = {
            "value": incognito && guard ? guard.makeId() : manager.makeSessionId(),
            "text": "New Chat",
            "createdAt": Date.now(),
            "updatedAt": Date.now(),
            "archived": false,
            "source": manager.modeSyncRef.newChatMode(),
            "projectId": project ? project.id : "",
            "openCodeSessionId": "",
            "openCodeWorkspaceCwd": project && project.folder ? "" : manager.modeSyncRef.newChatWorkspace(),
            "messages": []
        };
        if (incognito && guard)
            s.incognito = true;
        chat.sessions = [s].concat(chat.sessions);
        if (switchToNew) {
            chat.currentSessionId = s.value;
            chat.currentSessionTitle = s.text;
            chat.messages = [];
            chat.applySessionSource(s);
            manager._resetOpenChatState();
            chat.historyOnlyMode = chat.historySidePanel && chat.historyOnlyMode;
            chat.focusInput();
            if (guard)
                guard.left(previousId);
        }
        manager.persistSessions();
    }

    function resetUnreadableSessionHistory() { recovery.resolve(); }

    function loadSessions() {
        if (chat.incognito)
            chat.incognito.cleanup("");  // pictures of an incognito chat still open when the widget ended
        chat.sessions = manager.parseSessions(chat.chatStore.loadAll(true));
        recovery.afterLoad();
        if (chat.sessions.length === 0)
            manager.createSession(true);

        var preferred = chat.plasmoid.configuration.lastSessionId || "";
        var idx = manager.sessionIndexById(preferred);
        if (idx < 0)
            idx = 0;

        manager.messagesRef.ensure(chat.sessions[idx].value);
        chat.currentSessionId = chat.sessions[idx].value;
        chat.currentSessionTitle = chat.sessions[idx].text;
        chat.messages = chat.sessions[idx].messages || [];
        chat.applySessionSource(chat.sessions[idx]);
        manager.sortSessionsByUpdated();
        // An index from before 1.5 has no message counts: written once, so the next start reads the index only.
        if (chat.sessionSourceInferred || chat.sessions.some(function(s) { return typeof s.messageCount !== "number"; }))
            manager.persistSessions();
    }

    function saveCurrentSessionState(touchUpdatedAt) {
        var idx = manager.sessionIndexById(chat.currentSessionId);
        if (idx < 0)
            return ;
        var updated = chat.sessions.slice();
        var s = Object.assign({}, updated[idx]);
        s.text = chat.currentSessionTitle || "New Chat";
        s.messages = chat.messages;
        if (touchUpdatedAt !== false)
            s.updatedAt = Date.now();

        updated[idx] = s;
        chat.sessions = updated;
        if (touchUpdatedAt !== false)
            manager.sortSessionsByUpdated();

        manager.persistSessions([chat.currentSessionId]);
    }

    // Un-archives the open chat when it is used; its mode (source) stays as it is.
    function setCurrentSessionSource() {
        var idx = manager.sessionIndexById(chat.currentSessionId);
        if (idx < 0)
            return ;
        var updated = chat.sessions.slice();
        var item = Object.assign({}, updated[idx]);
        item.source = EffectiveConfig.chatMode(item);
        item.archived = false;
        updated[idx] = item;
        chat.sessions = updated;
        manager.persistSessions();
    }

    function setSessionArchived(sessionId, archived) {
        var idx = manager.sessionIndexById(sessionId);
        if (idx < 0)
            return ;
        var updated = chat.sessions.slice();
        var item = Object.assign({}, updated[idx]);
        item.archived = !!archived;
        item.updatedAt = Date.now();
        updated[idx] = item;
        chat.sessions = updated;
        manager.sortSessionsByUpdated();
        manager.persistSessions();
        // The open chat left the list: open the latest chat still in it (or a new one).
        if (archived && sessionId === chat.currentSessionId) {
            var next = chat.sessions.filter(function(s) { return !s.archived; })[0];
            if (next)
                manager.switchSession(next.value);
            else
                manager.createSession(true, item.projectId || "");
        }
    }

    // Clears what belonged to the chat on screen: TTS, the stream, edits and renames.
    function _resetOpenChatState() {
        chat.playingMessageIndex = -1;
        if (chat.voiceManagerRef && chat.voiceManagerRef.isPlaying) { chat.voiceManagerRef.stopTTS(); }
        chat.currentStreamIndex = -1;
        chat.currentStreamText = "";
        chat.streamBuffer.clear();
        chat.currentStreamReasoning = "";
        chat.currentStreamExtractedReasoning = "";
        chat.streamingResponse = false;
        chat.editingMessageIndex = -1;
        chat.editingDraft = "";
        chat.editingSessionId = "";
        chat.editingSessionDraft = "";
        chat.renamingCurrentChat = false;
        chat.currentChatRenameDraft = "";
    }

    // then(): runs once the chat is open (search results jump to a message).
    function switchSession(sessionId, then) {
        var guard = chat.incognito || null;
        if (sessionId && sessionId === chat.currentSessionId && then)
            then();
        if (!sessionId || sessionId === chat.currentSessionId || manager.sessionIndexById(sessionId) < 0
                || (guard && !guard.mayLeave(function() { manager.switchSession(sessionId, then); })))
            return ;
        // A response must never be allowed to write into the newly selected
        // session. Invalidate callbacks before changing the active model.
        chat.invalidateActiveRequest(false);
        manager.saveCurrentSessionState(false);
        manager.messagesRef.ensure(sessionId);
        var idx = manager.sessionIndexById(sessionId);
        var previousId = chat.currentSessionId;
        chat.currentSessionId = chat.sessions[idx].value;
        chat.currentSessionTitle = chat.sessions[idx].text;
        chat.messages = chat.sessions[idx].messages || [];
        chat.applySessionSource(chat.sessions[idx]);
        manager._resetOpenChatState();
        if (guard)
            guard.left(previousId);
        manager.persistSessions();
        chat.scrollToBottom(true);
        chat.focusInput();
        if (!chat.loading)
            Qt.callLater(chat.processNextQueuedMessage);
        if (then)
            then();
    }

    function deleteSession(sessionId) {
        if (chat.sessions.length <= 1)
            return ;
        if (sessionId === chat.currentSessionId)
            chat.invalidateActiveRequest(false);
        var idx = manager.sessionIndexById(sessionId);
        if (idx < 0)
            return ;
        var updated = chat.sessions.slice();
        var removed = updated.splice(idx, 1)[0];
        chat.sessions = updated;
        chat.sessionDeleted(removed, idx);
        manager.helperCommandsRef.deleteSessionSchedules(sessionId);
        if (chat.currentSessionId === sessionId) {
            manager.messagesRef.ensure(chat.sessions[0].value);
            var next = chat.sessions[0];
            chat.currentSessionId = next.value;
            chat.currentSessionTitle = next.text;
            chat.messages = next.messages || [];
            chat.applySessionSource(next);
        }
        chat.cancelSessionRename();
        manager.persistSessions();
    }

    function currentOpenCodeSessionId(sessionId) {
        var idx = manager.sessionIndexById(sessionId || chat.currentSessionId);
        if (idx < 0)
            return "";

        return Sec.validateRemoteSessionId(chat.sessions[idx].openCodeSessionId || "");
    }

    function setCurrentOpenCodeSessionId(remoteSessionId, sessionId) {
        var idx = manager.sessionIndexById(sessionId || chat.currentSessionId);
        if (idx < 0)
            return ;
        var updated = chat.sessions.slice();
        var item = Object.assign({}, updated[idx]);
        item.openCodeSessionId = Sec.validateRemoteSessionId(remoteSessionId || "");
        updated[idx] = item;
        chat.sessions = updated;
        manager.persistSessions();
    }

    function clearCurrentOpenCodeSessionIfNeeded() {
        if (!chat.openCodeMode)
            return ;
        manager.setCurrentOpenCodeSessionId("");
    }
}
