// Everything the widget stores, in one place: API keys (KWallet), chats
// (per-chat files), memories (memory.json, through the helper), the helper
// process, the one-time 1.4.0 migration, and then removing the settings 1.4.0
// dropped from the applet config (SettingsCleanup.qml).
//
// main.qml loads chats through chatStore, calls chatsLoaded() once they are
// in memory, and saves through save(). Saves are held back until the chat
// migration has run, so an early save can't create the chat store first and
// leave the old history in the config.
import QtQuick

Item {
    id: storage
    visible: false

    property var configuration: null
    property string helperPath: ""
    property string chatDirectory: ""
    // Returns the chats currently in memory (or null to skip migrating them).
    property var currentSessions: function() { return []; }

    readonly property alias wallet: walletStore
    readonly property alias chatStore: chats
    readonly property alias memoryStore: memories
    // What the migration moved, for a one-line notice.
    readonly property string notice: [migration.notice, memoryMigration.notice].filter(function(t) { return t; }).join(" ")

    property bool _chatsLoaded: false
    property bool _chatMigrationSettled: false
    property bool _savePending: false
    property bool _keyMigrationDone: false
    property bool _memoryMigrationDone: false

    // Emitted when held-back saves may be written, or a migration changed the
    // chats in memory; the widget saves again.
    signal savesReleased()

    // Runs a helper command (kde_ai_helper.py): onDone(stdout, exitCode, stderr).
    function runHelper(command, payload, onDone) {
        helper.run(command, payload, onDone);
    }

    function chatsLoaded() {
        _chatsLoaded = true;
        _migrateChatsOnce();
    }

    function save(sessions) {
        if (!_chatMigrationSettled) {
            _savePending = true;
            return;
        }
        chats.save(sessions);
    }

    function _migrateChatsOnce() {
        if (_chatMigrationSettled || !_chatsLoaded || !chats.ready)
            return;
        _chatMigrationSettled = true;
        var sessions = currentSessions();
        if (sessions)
            migration.migrateChats(sessions, null);
        if (_savePending) {
            _savePending = false;
            savesReleased();
        }
        _migrateMemoryOnce();
    }

    // Old memory (config text, chats' chatMemory) moves once memories are
    // loaded and the chats are in memory; the chats are saved again after.
    function _migrateMemoryOnce() {
        if (_memoryMigrationDone || !_chatMigrationSettled || !memories.loaded)
            return;
        _memoryMigrationDone = true;
        memoryMigration.migrate(currentSessions(), function(sessionsChanged) {
            if (sessionsChanged)
                savesReleased();
            settingsCleanup.begin();
        });
    }

    function _migrateKeysOnce() {
        if (_keyMigrationDone || !walletStore.usable)
            return;
        _keyMigrationDone = true;
        migration.migrateKeys(function() { migration.migrateProviders(); });
    }

    Wallet {
        id: walletStore
        onLoaded: storage._migrateKeysOnce()
    }

    HelperRunner {
        id: helper
        helperPath: storage.helperPath
    }

    ChatStore {
        id: chats
        directory: storage.chatDirectory
        runHelper: helper.run
        onReadyChanged: storage._migrateChatsOnce()
    }

    MemoryStore {
        id: memories
        configuration: storage.configuration
        runHelper: helper.run
        onListLoaded: storage._migrateMemoryOnce()
    }

    MemoryMigration {
        id: memoryMigration
        configuration: storage.configuration
        memoryStore: memories
    }

    SettingsCleanup {
        id: settingsCleanup
        runHelper: helper.run
        chatDirectory: storage.chatDirectory
    }

    Migration {
        id: migration
        configuration: storage.configuration
        wallet: walletStore
        chatStore: chats
        runHelper: helper.run
    }

    Component.onCompleted: {
        chats.prepare();
        memories.load();
    }
}
