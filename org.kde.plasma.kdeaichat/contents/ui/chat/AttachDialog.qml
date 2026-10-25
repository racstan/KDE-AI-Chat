// The "Attach Files" dialog. It starts in the chat's workspace folder; a chat
// with no workspace gets the dialog's usual starting folder.
import QtQuick
import QtQuick.Dialogs

FileDialog {
    id: dialog

    // main.qml (or a stand-in): openCodeWorkspaceCwd, attachFile(url).
    property var chat: null
    readonly property string workspace: dialog.chat ? String(dialog.chat.openCodeWorkspaceCwd || "").trim() : ""

    // Points the dialog at the workspace (if any); show() does this and opens it.
    function prepare() {
        if (dialog.workspace)
            dialog.currentFolder = "file://" + encodeURI(dialog.workspace);
    }

    function show() {
        dialog.prepare();
        dialog.open();
    }

    title: "Attach Files"
    fileMode: FileDialog.OpenFiles
    nameFilters: ["All supported files (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.pdf *.csv *.docx *.txt *.md *.json)", "Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)", "Documents (*.pdf *.docx *.csv *.txt *.md *.json)", "All files (*)"]
    onAccepted: {
        for (var i = 0; i < selectedFiles.length; i++)
            dialog.chat.attachFile(selectedFiles[i]);
    }
}
