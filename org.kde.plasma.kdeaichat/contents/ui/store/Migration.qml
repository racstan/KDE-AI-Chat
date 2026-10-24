// One-time move of data older versions left in plaintext (1.4.0).
//
// Keys: entries in the old "KaiChat" wallet folder move to the "KDE AI Chat"
// folder. Plaintext API keys in the widget's config (every key setting ever
// declared), in custom provider JSON and in ~/.config/kdeaichatrc go to
// KWallet. Plaintext copies are cleared only after KWallet accepted the
// write; if KWallet is off or refuses access, nothing is touched.
//
// Chats: when there is no chat store yet, the chat history kept in the
// widget's config is written to per-chat files, read back to verify, backed
// up inside the private chats folder, and only then cleared from the config.
import QtQuick

QtObject {
    id: migration

    property var configuration: null   // plasmoid.configuration
    property var wallet: null          // store/Wallet.qml (loaded)
    property var chatStore: null       // store/ChatStore.qml (prepared)
    property var runHelper: function(command, payload, onDone) { if (onDone) onDone("{}", 0, ""); }

    // Must match LEGACY_KEY_PROVIDERS in kdeaichat/privacy.py (tested).
    readonly property var legacyKeyProviders: ({
        "apiKey": "openai",
        "anthropicApiKey": "anthropic",
        "groqApiKey": "groq",
        "deepSeekApiKey": "deepseek",
        "miniMaxApiKey": "minimax",
        "fireworksApiKey": "fireworks",
        "googleApiKey": "google",
        "openRouterApiKey": "openrouter",
        "mistralApiKey": "mistral",
        "cloudflareApiKey": "cloudflare",
        "nvidiaApiKey": "nvidia",
        "huggingFaceApiKey": "huggingface",
        "xaiApiKey": "xai",
        "litellmApiKey": "litellm",
        "maritacaApiKey": "maritaca",
        "perplexityApiKey": "perplexity",
        "qwenApiKey": "qwen",
        "moonshotApiKey": "moonshot",
        "mimoApiKey": "mimo",
        "huggingfaceImageApiKey": "huggingface-image",
        "replicateApiKey": "replicate",
        "stabilityApiKey": "stability",
        "togetherImageApiKey": "together-image"
    })

    // What happened, for a one-line notice. Empty when nothing was moved.
    property string notice: ""

    function _say(text) {
        notice = notice ? notice + " " + text : text;
    }

    // Moves the old wallet folder and plaintext keys into KWallet.
    // callback(movedCount) counts plaintext keys moved.
    function migrateKeys(callback) {
        if (!wallet || !wallet.usable) {
            if (callback) callback(0);
            return;
        }
        wallet.migrateLegacyFolder(function(movedFromFolder) {
            console.info("KDE AI Chat: legacy wallet folder: moved", movedFromFolder, "keys (-1 = not removed)");
            if (movedFromFolder > 0)
                _say(i18n("Moved %1 API keys from the old KaiChat wallet folder to \"KDE AI Chat\".", movedFromFolder));
            wallet.load(function() { _migratePlaintextKeys(callback); });
        });
    }

    function _migratePlaintextKeys(callback) {
        var plaintext = {};        // providerId -> key
        var configNames = [];      // config entries to clear afterwards
        var names = Object.keys(legacyKeyProviders);
        for (var i = 0; i < names.length; i++) {
            var value = configuration[names[i]];
            if (value === undefined || value === null)
                continue;
            value = String(value).trim();
            if (value) {
                plaintext[legacyKeyProviders[names[i]]] = value;
                configNames.push(names[i]);
            }
        }
        var customs = [];
        try { customs = JSON.parse(configuration.customProvidersJson || "[]"); } catch (e) { customs = []; }
        var customsHaveKeys = false;
        for (var c = 0; c < customs.length; c++) {
            var custom = customs[c];
            if (custom && custom.id && String(custom.apiKey || "").trim()) {
                plaintext[String(custom.id)] = String(custom.apiKey).trim();
                customsHaveKeys = true;
            }
        }

        runHelper("read_legacy_keyfile", {}, function(stdout, exitCode) {
            var fileKeys = {};
            try { fileKeys = exitCode === 0 ? (JSON.parse(stdout).keys || {}) : {}; } catch (e) { fileKeys = {}; }
            var fileIds = Object.keys(fileKeys);
            for (var f = 0; f < fileIds.length; f++) {
                if (!plaintext.hasOwnProperty(fileIds[f]))
                    plaintext[fileIds[f]] = fileKeys[fileIds[f]];
            }

            // A key already in KWallet is the one in use; keep it.
            var toWrite = {};
            var ids = Object.keys(plaintext);
            for (var k = 0; k < ids.length; k++) {
                if (!wallet.keys[ids[k]])
                    toWrite[ids[k]] = plaintext[ids[k]];
            }
            var moved = Object.keys(toWrite).length;
            console.info("KDE AI Chat: plaintext keys found", ids.length, "to write", moved);

            function clearPlaintext() {
                for (var n = 0; n < configNames.length; n++)
                    configuration[configNames[n]] = "";
                if (customsHaveKeys) {
                    for (var m = 0; m < customs.length; m++)
                        if (customs[m]) delete customs[m].apiKey;
                    configuration.customProvidersJson = JSON.stringify(customs);
                }
                if (fileIds.length > 0)
                    runHelper("remove_legacy_keyfile", {}, null);
                if (moved > 0)
                    _say(i18n("Moved %1 API keys into KWallet and removed their plaintext copies.", moved));
                else
                    _say(i18n("Removed plaintext copies of %1 API keys that were already in KWallet.", ids.length));
                if (callback) callback(moved);
            }

            if (ids.length === 0) {
                if (callback) callback(0);
                return;
            }
            if (moved === 0) {
                clearPlaintext();
                return;
            }
            wallet.writeMany(toWrite, function(ok) {
                if (ok)
                    clearPlaintext();
                else if (callback)
                    callback(0);
            });
        });
    }

    // Writes chats loaded from the old config entry to the chat store.
    // `sessions` are the already-normalised chats. callback(ok).
    function migrateChats(sessions, callback) {
        var legacy = String(configuration.chatSessionsJson || "");
        console.info("KDE AI Chat: chat migration check: store index", chatStore ? chatStore.hasIndex() : "none",
                     "ready", chatStore ? chatStore.ready : false, "old history bytes", legacy.length, "chats", sessions.length);
        if (!chatStore || chatStore.hasIndex() || legacy === "" || legacy === "[]") {
            if (callback) callback(false);
            return;
        }
        chatStore.save(sessions, true);
        var check = chatStore.loadAll();
        var ok = check !== null && check.length === sessions.length;
        for (var i = 0; ok && i < sessions.length; i++)
            ok = check[i].value === sessions[i].value
                && (check[i].messages || []).length === (sessions[i].messages || []).length;
        if (!ok) {
            console.warn("KDE AI Chat: chat migration could not be verified; the old history was kept.");
            if (callback) callback(false);
            return;
        }
        chatStore.writeBackup("legacy-chat-history-backup.ini", legacy);
        configuration.chatSessionsJson = "";
        console.info("KDE AI Chat: moved", sessions.length, "chats to", chatStore.directory);
        _say(i18n("Moved %1 chats into private files.", sessions.length));
        if (callback) callback(true);
    }
}
