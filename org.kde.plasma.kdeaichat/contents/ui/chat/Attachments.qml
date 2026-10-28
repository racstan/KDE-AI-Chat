// Attachments of the message being written: adds files, clipboard files and
// images, removes them and cleans up temporary clipboard/screenshot files.
// `chat` is the widget root (main.qml); the list itself is chat.attachedFiles.
//
// What an attached document becomes depends on the open chat's mode (never
// switched): in direct mode doc_extractor.py reads it and the text goes in the
// message (a very large text gets a warning); in Pi and OpenCode chats it is
// not read at all, the message names its path and the agent reads what it
// needs. Images are read (inline) in every mode.
import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "../Security.js" as Sec
import "MessageContent.js" as MessageContent
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

P5Support.DataSource {
    id: attachments
    engine: "executable"
    connectedSources: []

    property var chat: null
    // marker -> {path, source} of extractions still running.
    property var pendingRequests: ({})
    property int requestCounter: 0

    // True when the open chat is a Pi or OpenCode chat (files go as paths).
    function agentMode() {
        var eff = chat && typeof chat.effectiveConfig === "function" ? chat.effectiveConfig(chat.currentSessionId) : null;
        return MessageContent.isAgentMode(eff ? eff.mode : "");
    }

    function isImagePath(path) {
        return /\.(png|jpe?g|webp|gif|bmp)$/i.test(String(path || ""));
    }

    // Direct mode: the warning for a very large extracted text ("" otherwise).
    function largeFileWarning(file) {
        if (attachments.agentMode() || !MessageContent.isLargeFile(file))
            return "";
        return i18n("This file is very large (about %1 characters of text). Sending it may be slow or expensive, and the AI may not use all of it. Consider attaching only the part you need, or use a Pi or OpenCode chat, which read files themselves.", Math.round(String(file.content).length / 1000) * 1000);
    }

    function fileIconName(filename) {
        var ext = filename.split('.').pop().toLowerCase();
        if (ext === 'pdf')
            return 'document-pdf';

        if (ext === 'csv')
            return 'text-csv';

        if (ext === 'docx' || ext === 'doc')
            return 'document-word';

        if (ext === 'md' || ext === 'txt')
            return 'text-plain';

        return 'document-text';
    }

    function attachmentsReadyToSend() {
        for (var i = 0; i < chat.attachedFiles.length; i++) {
            if (chat.attachedFiles[i].loading || chat.attachedFiles[i].error)
                return false;
        }
        return true;
    }

    function cleanupTemporaryAttachment(path) {
        var value = String(path || "");
        // clipboard images live in the runtime folder (/tmp as a fallback); the extractor checks the folder
        if (!/^\/(?:[^\/]+\/)*kdeaichat_(?:clip|shot)_[^\/]*$/.test(value))
            return;
        var extractor = attachments.getDocExtractorPath();
        var safePath = Sec.validateFilePath(value);
        if (extractor && safePath)
            attachments.connectSource("python3 " + Sec.quoteForShell(extractor) + " --cleanup " + Sec.quotePath(safePath) + " #cleanup-attachment-" + Date.now());
    }

    function removeAttachedFile(index) {
        var files = chat.attachedFiles.slice();
        if (index < 0 || index >= files.length)
            return;
        var removedPath = files[index].path || "";
        attachments.cleanupTemporaryAttachment(removedPath);
        var pending = Object.assign({}, attachments.pendingRequests || {});
        var keys = Object.keys(pending);
        for (var p = 0; p < keys.length; p++) {
            var entry = pending[keys[p]] || {};
            var path = typeof entry === "string" ? entry : entry.path;
            if (path === removedPath) {
                if (typeof entry === "object" && entry.source) {
                    try { attachments.disconnectSource(entry.source); } catch (e) {}
                }
                delete pending[keys[p]];
            }
        }
        attachments.pendingRequests = pending;
        files.splice(index, 1);
        chat.attachedFiles = files;
    }

    function getDocExtractorPath() {
        var urlStr = String(Qt.resolvedUrl("../doc_extractor.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        var path = decodeURIComponent(urlStr);
        return path.endsWith("/contents/ui/doc_extractor.py") ? path : "";
    }

    function attachFile(fileUrl) {
        var localPath = String(fileUrl);
        if (localPath.indexOf("file://") === 0)
            localPath = localPath.substring(7);

        localPath = decodeURIComponent(localPath);
        var files = chat.attachedFiles.slice();
        if (files.length >= 10) {
            chat.pushErrorMessage("You can attach at most 10 files per message.");
            return;
        }
        for (var i = 0; i < files.length; i++) {
            if (files[i].path === localPath)
                return ;

        }
        var filename = localPath.substring(localPath.lastIndexOf("/") + 1);
        var newFile = {
            "path": localPath,
            "name": filename,
            "loading": true,
            "error": "",
            "warning": "",
            "type": "",
            "content": "",
            "mimeType": "",
            "size": 0
        };
        files.push(newFile);
        chat.attachedFiles = files;
        var docExtractorPath = attachments.getDocExtractorPath();
        var safePath = Sec.validateFilePath(localPath);
        if (safePath && attachments.agentMode() && !attachments.isImagePath(safePath)) {
            // Pi / OpenCode: no extraction; the message names the file's path.
            newFile.loading = false;
            newFile.type = "path";
            newFile.path = safePath;
            files[files.length - 1] = newFile;
            chat.attachedFiles = files;
            return;
        }
        if (!docExtractorPath || !safePath) {
            files.pop();
            chat.attachedFiles = files;
            chat.pushErrorMessage("Unable to attach this file: unsupported or unsafe path.");
            return;
        }
        var marker = "extract-file-" + (++attachments.requestCounter) + "-" + Date.now();
        var pending = Object.assign({}, attachments.pendingRequests || {});
        var cmd = "timeout 60s python3 " + Sec.quoteForShell(docExtractorPath) + " " + Sec.quotePath(safePath);
        var source = cmd + " #" + marker;
        pending[marker] = {"path": safePath, "source": source};
        attachments.pendingRequests = pending;
        attachments.connectSource(source);
    }

    function checkClipboardForAttachments() {
        var docExtractorPath = attachments.getDocExtractorPath();
        if (!docExtractorPath) {
            chat.pushErrorMessage("Attachment extractor is not available in the installed widget.");
            return;
        }
        var cmd = "timeout 20s python3 " + Sec.quoteForShell(docExtractorPath) + " --clipboard";
        attachments.connectSource(cmd + " #clipboard-attachments");
    }

    // A clipboard result: its files (or image) join chat.attachedFiles, up to 10.
    function _addClipboardFiles(res) {
        var currentFiles = chat.attachedFiles.slice();
        if (res.mode === "files" && res.files) {
            for (var f = 0; f < Math.min(res.files.length, 10 - currentFiles.length); f++) {
                var fInfo = res.files[f];
                var exists = false;
                for (var idx = 0; idx < currentFiles.length; idx++) {
                    if (currentFiles[idx].path === fInfo.path) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    var clipFile = {
                        "name": fInfo.filename || fInfo.name,
                        "path": fInfo.path,
                        "type": fInfo.type,
                        "content": fInfo.content,
                        "mimeType": fInfo.mimeType,
                        "size": fInfo.size,
                        "loading": false,
                        "error": "",
                        "warning": ""
                    };
                    if (clipFile.type !== "image" && attachments.agentMode()) {
                        clipFile.type = "path";
                        clipFile.content = "";
                    }
                    clipFile.warning = attachments.largeFileWarning(clipFile);
                    currentFiles.push(clipFile);
                }

            }
        } else if (res.mode === "image" && res.file && currentFiles.length < 10) {
            var image = res.file;
            var imageExists = false;
            for (var i = 0; i < currentFiles.length; i++) {
                if (currentFiles[i].path === image.path) {
                    imageExists = true;
                    break;
                }
            }
            if (!imageExists)
                currentFiles.push({
                    "name": image.name,
                    "path": image.path,
                    "type": image.type,
                    "content": image.content,
                    "mimeType": image.mimeType,
                    "size": image.size,
                    "loading": false,
                    "error": "",
                    "warning": ""
                });

        }
        chat.attachedFiles = currentFiles;
    }

    onNewData: function(sourceName, data) {
        var exitCode = Number(data["exit code"]);
        if (isNaN(exitCode)) exitCode = 1;
        var stdout = data["stdout"] || "";
        var stderr = data["stderr"] || "";
        if (sourceName.indexOf("--clipboard") !== -1) {
            if (exitCode === 0 && stderr.trim() === "") {
                try {
                    var clip = JSON.parse(stdout);
                    if (clip.status === "success")
                        attachments._addClipboardFiles(clip);
                } catch (e) {
                    console.log("Failed to parse clipboard data: " + e);
                }
            }
            disconnectSource(sourceName);
            return ;
        }
        var matchedIndex = -1;
        var files = chat.attachedFiles.slice();
        var attachmentPath = "";
        var requestKeys = Object.keys(attachments.pendingRequests || {});
        for (var rk = 0; rk < requestKeys.length; rk++) {
            if (sourceName.indexOf(requestKeys[rk]) !== -1) {
                var pendingEntry = attachments.pendingRequests[requestKeys[rk]] || {};
                attachmentPath = typeof pendingEntry === "string" ? pendingEntry : (pendingEntry.path || "");
                var remainingRequests = Object.assign({}, attachments.pendingRequests);
                delete remainingRequests[requestKeys[rk]];
                attachments.pendingRequests = remainingRequests;
                break;
            }
        }
        if (!attachmentPath) {
            disconnectSource(sourceName);
            return;
        }
        for (var i = 0; i < files.length; i++) {
            if (files[i].path === attachmentPath) {
                matchedIndex = i;
                break;
            }
        }
        if (matchedIndex === -1) {
            disconnectSource(sourceName);
            return;
        }
        var fileObj = Object.assign({}, files[matchedIndex]);
        fileObj.loading = false;
        if (exitCode !== 0 || stderr.trim() !== "") {
            fileObj.error = stderr.trim() || ("Command exited with code " + exitCode);
        } else {
            try {
                var res = JSON.parse(stdout);
                if (res.status === "success") {
                    fileObj.type = res.type;
                    fileObj.content = res.content;
                    fileObj.mimeType = res.mimeType;
                    fileObj.size = res.size;
                    fileObj.warning = attachments.largeFileWarning(fileObj);
                } else {
                    fileObj.error = res.message || "Failed to extract file contents";
                }
            } catch (e) {
                fileObj.error = "Failed to parse extractor output: " + e;
            }
        }
        files[matchedIndex] = fileObj;
        chat.attachedFiles = files;
        disconnectSource(sourceName);
    }
}
