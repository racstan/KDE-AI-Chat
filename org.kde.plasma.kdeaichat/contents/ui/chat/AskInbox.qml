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
//     at once, when the box was empty and the files have loaded, and only while the same chat is still open
//     and is a direct chat: in an OpenCode or Pi chat (agents that run commands) the text only waits in the box.
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

    function refusedText(note) {
        var name = String(note.name || "");
        if (note.reason === "outside")
            return i18n("Not attached (outside your home folder and mounted drives): %1", name);
        if (note.reason === "hidden")
            return i18n("Not attached (inside a hidden folder or a hidden file): %1", name);
        return i18n("Not attached (not a readable file): %1", name);
    }

    // An OpenCode or Pi chat can run commands: text from other programs is never sent into it by itself, it
    // waits in the message box for the user to press Send.
    function agentChat() {
        return inbox.chat.openCodeMode === true || inbox.chat.piMode === true;
    }

    function apply(item) {
        chat.triggerInitialLoad();
        chat.expanded = true;
        if (item.newChat === true)
            chat.createSession(true);
        // Files the helper refused (outside home, hidden folders, unreadable): say so, never silently.
        var notes = item.notes || [];
        for (var n = 0; n < notes.length; n++)
            chat.pushErrorMessage(inbox.refusedText(notes[n]));
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
        // Files never send by themselves: the user looks at them and presses Enter.
        if (item.send === true && paths.length === 0 && text !== "" && draft.trim() === "" && !inbox.agentChat()) {
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
            if (!sameChat || inbox._waited > 150 || inbox.agentChat()) {
                sendTimer.stop();   // the user moved on (or 30 s passed): the text stays in the box
            } else if (inbox.chat.attachmentsReadyToSend()) {
                sendTimer.stop();
                try {
                    inbox.chat.sendMessage();
                } catch (e) {
                    console.warn("ask inbox: sending failed: " + e);   // never leave the inbox stuck busy
                }
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
