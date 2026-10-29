// The "Backup" group of Settings → Storage: back up everything to one .zip,
// restore from one (only adds what is missing, schedules come back switched
// off, settings only if asked) and import conversations from a ChatGPT or Claude
// export. The work is done by the helper (kdeaichat/backup.py, import_chats.py);
// this only asks for files, shows what was found and says what happened.
// Nothing here is a setting (no cfg_ property) and no secret is ever read:
// API keys are in KDE Wallet and are not part of a backup.
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: section

    // The helper (HelperRunner or a stand-in), the chat folder chats/applet-<id>,
    // plasmoid.configuration and the widget's version.
    property var helperRunner: null
    property string directory: ""
    property var configuration: null
    property string widgetVersion: ""
    // Asks for a file: pick("backup" | "restore" | "import"); the dialog's answer goes to accepted(kind, path).
    property var pick: function(kind) { dialogFor(kind).open(); }

    property bool busy: false
    property string doneText: ""
    property string errorText: ""
    // backup_inspect's answer for the file waiting to be restored (null: none).
    property var found: null
    property string foundPath: ""
    readonly property alias restoreSettings: settingsBox.checked

    // Settings that are never even handed to the helper (it filters again).
    readonly property var _secretName: /key|token|secret|passw|auth|credential/i

    function settingsToSave() {
        var out = {};
        var names = configuration && configuration.keys ? configuration.keys() : [];
        for (var i = 0; i < names.length; i++) {
            var name = String(names[i]);
            if ((section._secretName.test(name) && name !== "sendKey") || name === "chatSessionsJson")
                continue;
            out[name] = configuration[name];
        }
        return out;
    }

    function dateStamp() {
        var d = new Date();
        function two(n) { return (n < 10 ? "0" : "") + n; }
        return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate());
    }

    function reply(stdout) {
        try {
            return JSON.parse(String(stdout).trim().split("\n").pop());
        } catch (e) {
            return null;
        }
    }

    function fail(data) {
        section.busy = false;
        section.errorText = data && data.error ? data.error : i18n("That didn't work. Nothing was changed.");
    }

    function clearMessages() {
        doneText = "";
        errorText = "";
    }

    // The widget reloads its chat list when this number changes.
    function reloadChats() {
        if (configuration && configuration.chatsReloadRevision !== undefined)
            configuration.chatsReloadRevision = (Number(configuration.chatsReloadRevision) || 0) + 1;
    }

    function backUpTo(path) {
        clearMessages();
        busy = true;
        helperRunner.run("backup_create", {"directory": directory, "dest": path, "settings": settingsToSave(),
                                           "widgetVersion": widgetVersion}, function(stdout) {
            var data = section.reply(stdout);
            if (!data || data.ok !== true)
                return section.fail(data);
            section.busy = false;
            section.doneText = i18n("Backup saved: %1 chats, %2 memories, %3 schedules.",
                                    data.contents.chats, data.contents.memories, data.contents.schedules);
        });
    }

    // Looks into a backup and asks before restoring it.
    function inspect(path) {
        clearMessages();
        found = null;
        busy = true;
        helperRunner.run("backup_inspect", {"path": path}, function(stdout) {
            var data = section.reply(stdout);
            if (!data || data.ok !== true)
                return section.fail(data);
            section.busy = false;
            settingsBox.checked = false;
            section.foundPath = path;
            section.found = data;
        });
    }

    function applySettings(settings) {
        var names = configuration && configuration.keys ? configuration.keys() : [];
        var count = 0;
        for (var name in settings) {
            if (names.indexOf(name) >= 0 && !(section._secretName.test(name) && name !== "sendKey")) {
                configuration[name] = settings[name];
                count++;
            }
        }
        return count;
    }

    function restoreNow() {
        var path = foundPath;
        var withSettings = settingsBox.checked;
        found = null;
        busy = true;
        helperRunner.run("backup_restore", {"path": path, "directory": directory, "mode": "merge",
                                            "withSettings": withSettings}, function(stdout) {
            var data = section.reply(stdout);
            if (!data || data.ok !== true)
                return section.fail(data);
            section.busy = false;
            section.reloadChats();
            var text = i18n("Restored %1 chats (%2 already there), %3 memories and %4 schedules (switched off).",
                            data.chatsAdded, data.chatsSkipped, data.memoriesAdded, data.schedulesAdded);
            if (withSettings && data.settings)
                text += " " + i18n("%1 settings restored.", section.applySettings(data.settings));
            section.doneText = text;
        });
    }

    function importFrom(path) {
        clearMessages();
        found = null;
        busy = true;
        helperRunner.run("import_run", {"path": path, "directory": directory}, function(stdout) {
            var data = section.reply(stdout);
            if (!data || data.ok !== true)
                return section.fail(data);
            section.busy = false;
            section.reloadChats();
            section.doneText = i18n("Imported %1 chats, %2 already there", data.imported, data.existing);
        });
    }

    function accepted(kind, path) {
        if (kind === "backup")
            backUpTo(path);
        else if (kind === "restore")
            inspect(path);
        else
            importFrom(path);
    }

    function pathOf(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    }

    function dialogFor(kind) {
        return kind === "backup" ? saveDialog : kind === "restore" ? restoreDialog : importDialog;
    }

    FileDialog {
        id: saveDialog
        title: i18n("Save backup")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "zip"
        currentFile: StandardPaths.writableLocation(StandardPaths.DocumentsLocation) + "/kdeaichat-backup-" + section.dateStamp() + ".zip"
        nameFilters: [i18n("Backups (*.zip)")]
        onAccepted: section.accepted("backup", section.pathOf(selectedFile))
    }

    FileDialog {
        id: restoreDialog
        title: i18n("Choose a backup")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Backups (*.zip)")]
        onAccepted: section.accepted("restore", section.pathOf(selectedFile))
    }

    FileDialog {
        id: importDialog
        title: i18n("Choose a ChatGPT or Claude export")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Exports (*.zip *.json)")]
        onAccepted: section.accepted("import", section.pathOf(selectedFile))
    }

    spacing: Kirigami.Units.smallSpacing

    Kirigami.Heading {
        level: 3
        text: i18n("Backup")
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.75
        text: i18n("One file with your chats, memories, schedules, MCP servers and settings. Your API keys are not in it: they stay in KDE Wallet, so enter them again on a new computer.")
    }

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            objectName: "backupCreate"
            icon.name: "document-save"
            text: i18n("Back up…")
            enabled: !section.busy && section.directory !== ""
            onClicked: { section.clearMessages(); section.pick("backup"); }
        }
        QQC2.Button {
            objectName: "backupRestore"
            icon.name: "document-open"
            text: i18n("Restore…")
            enabled: !section.busy && section.directory !== ""
            onClicked: { section.clearMessages(); section.pick("restore"); }
        }
        QQC2.Button {
            objectName: "backupImport"
            icon.name: "document-import"
            text: i18n("Import from ChatGPT or Claude…")
            enabled: !section.busy && section.directory !== ""
            onClicked: { section.clearMessages(); section.pick("import"); }
        }
    }

    ColumnLayout {
        objectName: "backupFound"
        Layout.fillWidth: true
        visible: section.found !== null
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            objectName: "backupFoundText"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.bold: true
            text: section.found ? i18n("This backup has %1 chats, %2 memories and %3 schedules.",
                                       section.found.counts.chats, section.found.counts.memories, section.found.counts.schedules) : ""
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("Restoring only adds what you don't have yet. Nothing is overwritten, and restored schedules stay switched off until you turn them on.")
        }
        QQC2.CheckBox {
            id: settingsBox
            objectName: "restoreSettings"
            visible: section.found !== null && section.found.hasSettings === true
            text: i18n("Also restore settings")
            checked: false
        }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.Button {
                objectName: "restoreConfirm"
                icon.name: "document-revert"
                text: i18n("Restore")
                enabled: !section.busy
                onClicked: section.restoreNow()
            }
            QQC2.Button {
                objectName: "restoreCancel"
                text: i18n("Cancel")
                onClicked: section.found = null
            }
        }
    }

    Kirigami.InlineMessage {
        objectName: "backupError"
        Layout.fillWidth: true
        visible: section.errorText !== ""
        type: Kirigami.MessageType.Error
        text: section.errorText
    }

    Kirigami.InlineMessage {
        objectName: "backupDone"
        Layout.fillWidth: true
        visible: section.doneText !== ""
        type: Kirigami.MessageType.Positive
        text: section.doneText
    }
}
