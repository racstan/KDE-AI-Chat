// One-time move of the memory older versions kept (1.4.0) into the memory
// list (store/MemoryStore.qml).
//
// Old memory was one text in the widget's config (userMemory, used when
// enableMemory was on) and one text per chat (the chat's chatMemory, used
// unless its chatMemoryEnabled was false). Each line of them (bullets
// removed, blank lines skipped) becomes a memory: the config's for every
// chat, a chat's for that chat; ones that were off come in turned off.
//
// The old copies are cleared only after the list was read back from the
// helper and has every one of them. Running it again adds nothing twice
// (the helper keeps one of each), and once the old copies are cleared there
// is nothing left to move.
import QtQuick

QtObject {
    id: migration

    property var configuration: null   // plasmoid.configuration
    property var memoryStore: null     // store/MemoryStore.qml (loaded)

    property string notice: ""
    property int skippedCount: 0       // old lines that were malformed and left behind
    readonly property int maxText: 4000

    // Memory texts from one old text: one per line, bullets and numbers removed.
    function splitItems(text) {
        var out = [];
        var lines = String(text || "").replace(/\r\n?/g, "\n").split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].replace(/^\s*(?:[-*+•]|\d{1,3}[.)])\s+/, "").trim();
            if (line)
                out.push(line.substring(0, maxText).trim());
        }
        return out;
    }

    // The memories to create from the old config text and `sessions`.
    function legacyItems(sessions) {
        var items = [];
        var on = configuration && configuration.enableMemory === true;
        splitItems(configuration ? configuration.userMemory : "").forEach(function(text) {
            items.push({"text": text, "scope": "all", "enabled": on});
        });
        (sessions || []).forEach(function(session) {
            if (!session || typeof session.chatMemory !== "string")
                return;
            splitItems(session.chatMemory).forEach(function(text) {
                items.push({"text": text, "scope": "chat", "chatId": session.value, "sourceChatId": session.value,
                            "enabled": session.chatMemoryEnabled !== false});
            });
        });
        return items;
    }

    function _clearOld(sessions) {
        var changed = false;
        if (configuration && String(configuration.userMemory || "") !== "")
            configuration.userMemory = "";
        (sessions || []).forEach(function(session) {
            if (session && (session.chatMemory !== undefined || session.chatMemoryEnabled !== undefined)) {
                delete session.chatMemory;
                delete session.chatMemoryEnabled;
                changed = true;
            }
        });
        return changed;
    }

    // Moves the old memory. sessions: the chats in memory (their old fields
    // are removed in place) or null. callback(sessionsChanged, movedCount).
    function migrate(sessions, callback) {
        var items = legacyItems(sessions);
        var hasOldFields = (sessions || []).some(function(s) {
            return s && (s.chatMemory !== undefined || s.chatMemoryEnabled !== undefined);
        });
        if (items.length === 0) {
            var cleaned = hasOldFields || String(configuration ? configuration.userMemory || "" : "") !== "" ? _clearOld(sessions) : false;
            if (callback) callback(cleaned, 0);
            return;
        }
        if (!memoryStore) {
            if (callback) callback(false, 0);
            return;
        }
        memoryStore.addMany(items, function(ok, result) {
            if (!ok) {
                console.warn("KDE AI Chat: old memory could not be saved; it was kept.");
                if (callback) callback(false, 0);
                return;
            }
            var skipped = Number(result.skipped || 0);
            memoryStore.load(function(loadedOk) {
                // Every item has an id (new, or of the memory it matched), and each is in the list read back.
                var ids = (result.added || []).concat(result.existing || []);
                var stored = {};
                (memoryStore.list || []).forEach(function(m) { stored[m.id] = true; });
                var verified = loadedOk && ids.length + skipped === items.length && ids.every(function(id) { return stored[id] === true; });
                if (!verified) {
                    console.warn("KDE AI Chat: old memory could not be verified; it was kept.");
                    if (callback) callback(false, 0);
                    return;
                }
                var moved = (result.added || []).length;
                if (skipped > 0) {
                    // Keep the old text so nothing is lost; the good lines are already in (re-adding them adds nothing).
                    skippedCount = skipped;
                    console.warn("KDE AI Chat: skipped", skipped, "malformed old memory lines; the old memory was kept.");
                    if (moved > 0)
                        notice = i18np("Moved %1 remembered note into the new memory list.", "Moved %1 remembered notes into the new memory list.", moved); // qmllint disable unqualified
                    if (callback) callback(false, moved);
                    return;
                }
                var changed = migration._clearOld(sessions);
                console.info("KDE AI Chat: moved", items.length, "old memory lines into the memory list (", moved, "new )");
                if (moved > 0)
                    notice = i18np("Moved %1 remembered note into the new memory list.", "Moved %1 remembered notes into the new memory list.", moved); // qmllint disable unqualified
                if (callback) callback(changed, moved);
            });
        }, {"skipInvalid": true});
    }
}
