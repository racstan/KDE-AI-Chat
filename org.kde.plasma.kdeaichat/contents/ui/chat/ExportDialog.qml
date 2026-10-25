// The save dialog for "Export chat…". The name filter picks the format
// (Markdown, plain text or JSON) and the file gets that extension; the text
// itself is built by ChatExport.js and written by chat.writeExportFile (the
// helper's validated, atomic write).
import QtQuick
import QtQuick.Dialogs
import "ChatExport.js" as ChatExport

FileDialog {
    id: dialog

    // The widget root (main.qml).
    property var chat: null

    // What the chat is, for the file's details.
    function describe() {
        var id = chat.currentSessionId;
        var idx = chat.sessionIndexById ? chat.sessionIndexById(id) : -1;
        var session = idx >= 0 ? chat.sessions[idx] : null;
        var eff = chat.effectiveConfig ? chat.effectiveConfig(id) : null;
        var mode = eff ? eff.mode : "provider";
        var provider = "";
        var model = eff ? String(eff.model || "") : "";
        if (mode === "provider" && eff && chat.providerDisplayName)
            provider = chat.providerDisplayName(eff.provider);
        else if (eff)
            provider = String(eff.provider || "");
        return {
            "title": chat.currentSessionTitle,
            "createdAt": session ? Number(session.createdAt) || 0 : 0,
            "exportedAt": Date.now(),
            "mode": mode, "provider": provider, "model": model,
            "messages": chat.messages
        };
    }

    // Builds the file for the chosen filter and saves it.
    function exportTo(path, filterIndex) {
        var target = ChatExport.resolveTarget(path, filterIndex);
        chat.writeExportFile(target.path, ChatExport.build(target.format, describe(), {"includeReasoning": false}));
    }

    function openWith(suggestedFile) {
        currentFile = suggestedFile;
        open();
    }

    title: i18n("Export chat") // qmllint disable unqualified
    fileMode: FileDialog.SaveFile
    nameFilters: ChatExport.filterLabels()
    onAccepted: {
        var path = selectedFile.toString();
        if (path.indexOf("file://") === 0)
            path = decodeURIComponent(path.slice(7));
        dialog.exportTo(path, selectedNameFilter.index);
    }
}
