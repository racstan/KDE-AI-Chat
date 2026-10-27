// Chat names: manual renames, and automatic ones (chat/ChatTitle.js). A chat
// gets an instant name from its first message (session.autoTitle remembers
// it), then, after the first reply, a model-written one. Only a title still
// equal to autoTitle (or the default) is replaced, so a manual rename always
// wins. `chat` is the widget root (main.qml).
import QtQuick
import "ChatTitle.js" as ChatTitle
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QtObject {
    id: titles

    property var chat: null
    // sessionId -> true once a model-written name was asked for.
    property var requested: ({})

    function renameCurrentSession(newTitle) {
        var title = (newTitle || "").trim();
        if (title === "")
            title = "New Chat";

        chat.currentSessionTitle = title;
        chat.saveCurrentSessionState(true);
    }

    function startSessionRename(sessionId) {
        var idx = chat.sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        chat.editingSessionId = sessionId;
        chat.editingSessionDraft = chat.sessions[idx].text || "";
    }

    function cancelSessionRename() {
        chat.editingSessionId = "";
        chat.editingSessionDraft = "";
    }

    function saveSessionRename(sessionId) {
        var idx = chat.sessionIndexById(sessionId);
        if (idx < 0)
            return ;

        var title = (chat.editingSessionDraft || "").trim();
        if (title === "")
            title = "New Chat";

        var updated = chat.sessions.slice();
        var s = Object.assign({}, updated[idx]);
        s.text = title;
        s.updatedAt = Date.now();
        updated[idx] = s;
        chat.sessions = updated;
        if (chat.currentSessionId === sessionId)
            chat.currentSessionTitle = title;

        chat.sortSessionsByUpdated();
        chat.persistSessions();
        titles.cancelSessionRename();
    }

    // Chat names (chat/ChatTitle.js). A chat gets an instant name from its first
    // message (session.autoTitle remembers it), then, after the first reply, a
    // model-written one. Only a title still equal to autoTitle (or the default)
    // is replaced, so a manual rename always wins.
    function nameChatFromFirstMessage(text) {
        var source = titles.titleSource(text);
        var title = titles.imageTitle(ChatTitle.instantTitle(source.text), source.image);
        if (!title || !ChatTitle.isDefaultTitle(chat.currentSessionTitle) || titles.firstUserText() !== String(text).trim())
            return;
        titles.applyAutoTitle(chat.currentSessionId, title);
    }

    // What a chat is named after: a "/image <prompt>" line by its prompt.
    function titleSource(text) {
        var prompt = ChatTitle.imagePrompt(text);
        return prompt !== "" ? {"text": prompt, "image": true} : {"text": String(text || ""), "image": false};
    }

    function imageTitle(title, image) {
        return title && image ? i18n("Image: %1", title) : title;
    }

    function firstUserText() {
        for (var i = 0; i < chat.messages.length; i++)
            if (chat.messages[i].role === "user" || chat.messages[i].role === "queued")
                return String(chat.messages[i].content || "").trim();
        return "";
    }

    // Sets `title` on chat `sessionId` if its name is still automatic.
    function applyAutoTitle(sessionId, title, final) {
        var idx = chat.sessionIndexById(sessionId);
        if (idx < 0)
            return false;
        var isCurrent = sessionId === chat.currentSessionId;
        var current = isCurrent ? chat.currentSessionTitle : chat.sessions[idx].text;
        if (!ChatTitle.isDefaultTitle(current) && !(chat.sessions[idx].autoTitle && current === chat.sessions[idx].autoTitle))
            return false;
        var updated = chat.sessions.slice();
        updated[idx] = Object.assign({}, updated[idx], {"text": title, "autoTitle": final ? "" : title});
        chat.sessions = updated;
        if (isCurrent)
            chat.currentSessionTitle = title;
        chat.persistSessions();
        return true;
    }

    function maybeGenerateChatTitle() {
        var sessionId = chat.currentSessionId;
        var idx = chat.sessionIndexById(sessionId);
        // An incognito chat keeps its first-message name: the model isn't asked (chat/Incognito.qml).
        if (chat.plasmoid.configuration.autoNameChats === false || idx < 0 || titles.requested[sessionId] || chat.sessions[idx].incognito === true)
            return;
        var current = chat.currentSessionTitle;
        if (!ChatTitle.isDefaultTitle(current) && !(chat.sessions[idx].autoTitle && current === chat.sessions[idx].autoTitle))
            return;
        var firstUser = titles.firstUserText();
        // Agent chats use the default direct provider, if it has a key.
        var cfg = chat.getProviderConfig(chat.getEffectiveProvider(sessionId), sessionId);
        if (!firstUser || !cfg || !cfg.model || !cfg.baseUrl || (!cfg.allowEmptyKey && !cfg.apiKey))
            return;
        titles.requested[sessionId] = true;
        var source = titles.titleSource(firstUser);
        ChatTitle.request(cfg, source.text, function() { return new XMLHttpRequest(); }, function(title, error) {
            if (title)
                titles.applyAutoTitle(sessionId, titles.imageTitle(title, source.image), true);
            else
                console.warn("KDE AI Chat: couldn't name the chat with the model (" + error + "); keeping its first-message name");
        });
    }
}
