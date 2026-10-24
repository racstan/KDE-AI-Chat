// Everything the widget stores, in one place: API keys (KWallet), chats
// (per-chat files), the helper process, and the one-time 1.4.0 migration.
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
    // What the migration moved, for a one-line notice.
    readonly property string notice: migration.notice

    property bool _chatsLoaded: false
    property bool _chatMigrationSettled: false
    property bool _savePending: false
    property bool _keyMigrationDone: false

    // Emitted when held-back saves may be written; the widget saves again.
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

    Migration {
        id: migration
        configuration: storage.configuration
        wallet: walletStore
        chatStore: chats
        runHelper: helper.run
    }

    Component.onCompleted: chats.prepare()
}
