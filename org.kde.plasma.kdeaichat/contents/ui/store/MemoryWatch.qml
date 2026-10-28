// Tells when memory.json changed on disk, so the widget's memory list
// (store/MemoryStore.qml) can load it again. The settings page keeps its own
// MemoryStore: a memory added, edited or deleted there is written by the
// helper (atomically: a new file renamed into place) and reaches the chats
// only through this. A FolderListModel is a file-system watcher, so nothing
// runs or polls while the file stays the same. Changes the widget makes itself
// are seen too; loading again then is harmless.
import QtQuick
import Qt.labs.folderlistmodel

Item {
    id: watch

    // ~/.local/share/kdeaichat (kdeaichat/chats.py data_root()); "" = off.
    property string directory: ""
    property string fileName: "memory.json"

    // The file was created, replaced or removed (several changes close together are one).
    signal changed()

    property string _seen: ""
    // A new folder (or none) starts over: what is there now is not a change.
    onDirectoryChanged: { watch._seen = ""; settle.stop(); }

    function _stamp() {
        if (files.status !== FolderListModel.Ready)
            return null;
        return files.count > 0 ? String(files.get(0, "fileModified")) + "/" + files.get(0, "fileSize") : "none";
    }

    function _check() {
        var stamp = watch._stamp();
        if (stamp === null || watch.directory === "")
            return;
        if (watch._seen !== "" && stamp !== watch._seen)
            settle.restart();
        watch._seen = stamp;
    }

    FolderListModel {
        id: files
        folder: watch.directory !== "" ? "file://" + watch.directory : ""
        nameFilters: [watch.fileName]
        showDirs: false
        showHidden: false
        onCountChanged: watch._check()
        onStatusChanged: watch._check()
        onDataChanged: watch._check()
        onRowsInserted: watch._check()
    }

    Timer {
        id: settle
        interval: 250
        onTriggered: watch.changed()
    }
}
