// Questions from the rest of the desktop (KRunner, the Dolphin menu, the kdeaichat-ask command).
// They leave a private file in the ask inbox folder (kdeaichat/ask_inbox.py, $XDG_RUNTIME_DIR/kdeaichat-ask);
// this watches the folder with a FolderListModel (a file-system watcher, no polling), takes the requests
// through the helper (ask_inbox_take: claimed and deleted, so with two widgets only one gets each) and
// handles them one at a time:
//   - the popup opens (chat.expanded): no D-Bus call into plasmashell is needed, the widget opens itself;
//   - "new chat" starts a new chat (default mode); otherwise the open chat is used, in its own mode: a
//     request never changes the mode of a chat;
//   - files are attached with the normal attachment code (doc_extractor.py);
//   - the text goes into the message box (after what is already typed there); a request marked "send" is sent
//     at once, when the box was empty and the files have loaded, and only while the same chat is still open.
// On start it also re-installs the KRunner/Dolphin/shortcut files if those switches are on (so a moved or updated
// widget keeps them pointing at the right place). `chat` is the widget root (main.qml).
import QtQuick
import Qt.labs.folderlistmodel

Item {
    id: inbox
    visible: false

    property var chat: null
    // runHelper(command, payload, onDone) and whether the chat store is ready to load chats.
    property var runHelper: null
    property bool ready: false
    // The widget's settings (plasmoid.configuration), for the start-up re-install.
    property var config: null
    // Tests: the folder; otherwise the helper says where it is.
    property string directory: ""

    property var _queue: []
    property bool _busy: false
    property bool _started: false
    // A request waiting for its files before it is sent.
    property string _sendChatId: ""
    property int _waited: 0

    FolderListModel {
        id: files
        folder: inbox.directory !== "" ? "file://" + inbox.directory : ""
        nameFilters: ["ask-*.json"]
        showDirs: false
        showHidden: false
        onCountChanged: if (files.count > 0) inbox.take()
        onStatusChanged: if (files.status === FolderListModel.Ready && files.count > 0) inbox.take()
    }

    function take() {
        if (!inbox.ready || !inbox.runHelper || !inbox.chat)
            return;
        inbox.runHelper("ask_inbox_take", {}, function(stdout, exitCode, stderr) {
            var data = null;
            try {
                data = JSON.parse(String(stdout).trim().split("\n").pop());
            } catch (e) {
                return;
            }
            if (!data || data.type !== "ask_items")
                return;
            if (inbox.directory === "" && data.directory)
                inbox.directory = String(data.directory);
            inbox._queue = inbox._queue.concat(data.items || []);
            inbox._next();
        });
    }

    function _next() {
        if (inbox._busy || inbox._queue.length === 0)
            return;
        var item = inbox._queue[0];
        inbox._queue = inbox._queue.slice(1);
        inbox.apply(item);
    }

    function fileUrl(path) {
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }

    function apply(item) {
        chat.triggerInitialLoad();
        chat.expanded = true;
        if (item.newChat === true)
            chat.createSession(true);
        var paths = item.files || [];
        for (var i = 0; i < paths.length; i++)
            chat.attachFile(inbox.fileUrl(paths[i]));
        var text = String(item.text || "").trim();
        // A quoted selection (kdeaichat-ask --selection: "> ..." lines) keeps its blank line after it, so the
        // question is typed below the quote.
        if (text.indexOf("> ") === 0 && item.send !== true)
            text += "\n\n";
        var draft = String(chat.chatInputText || "");
        if (text !== "")
            chat.chatInputText = draft.trim() !== "" ? draft + "\n" + text : text;
        chat.focusInput();
        if (item.send === true && text !== "" && draft.trim() === "") {
            inbox._busy = true;
            inbox._sendChatId = String(chat.currentSessionId);
            inbox._waited = 0;
            sendTimer.restart();
        } else {
            inbox._next();
        }
    }

    // Sends once the attached files have loaded (a few seconds at most).
    Timer {
        id: sendTimer
        interval: 200
        repeat: true
        onTriggered: {
            inbox._waited++;
            var sameChat = String(inbox.chat.currentSessionId) === inbox._sendChatId;
            if (!sameChat || inbox._waited > 150) {
                sendTimer.stop();   // the user moved on: the text stays in the box
            } else if (inbox.chat.attachmentsReadyToSend()) {
                sendTimer.stop();
                inbox.chat.sendMessage();
            } else {
                return;
            }
            inbox._busy = false;
            inbox._next();
        }
    }

    function start() {
        if (!inbox.ready || !inbox.runHelper || !inbox.chat || inbox._started)
            return;
        inbox._started = true;
        inbox.take();   // requests that arrived before the widget did; also creates the folder
        var cfg = inbox.config;
        if (cfg && inbox.runHelper && (cfg.krunnerEnabled === true || cfg.dolphinMenuEnabled === true || cfg.selectionShortcutEnabled === true))
            inbox.runHelper("desktop_sync", {"krunner": cfg.krunnerEnabled === true, "dolphin": cfg.dolphinMenuEnabled === true, "selection": cfg.selectionShortcutEnabled === true,
                                             "prefix": String(cfg.krunnerPrefix || "ai")}, null);
    }

    onReadyChanged: start()
    onRunHelperChanged: start()
    onChatChanged: start()
    Component.onCompleted: start()
}
