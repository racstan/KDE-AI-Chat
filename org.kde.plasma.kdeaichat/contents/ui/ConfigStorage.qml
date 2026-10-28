// Settings → Storage: where the widget keeps its data, how much space it uses
// and what uses it. Nothing here is a setting (no cfg_ property): sizes come
// from the helper's storage_usage and Remove goes through storage_remove,
// which only ever removes backups, caches and the old voice engines.
//
// The data folder cannot be moved. Chats, pictures and memories are only
// shown (they are managed in Chat and Memory); Speech Note's models belong to
// Speech Note: they are shown as a link, never counted and never removed.
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import "chat/DisplayPath.js" as Paths
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "store" as Store
import "config" as Config
import "config/StorageFormat.js" as Fmt

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    // Runs the helper's commands; a property so a test can pass a fake.
    property var helperRunner: defaultRunner
    property var openUrl: function(url) { Qt.openUrlExternally(url); }

    // The last storage_usage reply (null until it arrives).
    property var usage: null
    property bool loading: false
    property string errorText: ""
    property string doneText: ""
    // The item waiting for the answer to "Remove?".
    property string pendingItem: ""
    readonly property alias confirmDialog: confirm

    readonly property var rows: [
        {"id": "chats", "title": i18n("Chats"),
         "text": i18n("Your conversations: the text of every chat and the list of chats. Delete chats in the chat history; this page only shows the space they use.")},
        {"id": "pictures", "title": i18n("Pictures"),
         "text": i18n("Pictures the AI made for you, saved next to the chats they belong to. Deleting a chat deletes its pictures; they can't be removed from here.")},
        {"id": "memories", "title": i18n("Memories"),
         "text": i18n("The notes you asked the assistant to remember. Manage them in Settings → Memory.")},
        {"id": "schedules", "title": i18n("Schedules and their logs"),
         "text": i18n("Your scheduled prompts and the record of when each one last ran. Manage them in Settings → Schedules.")},
        {"id": "backups", "title": i18n("Backups"),
         "text": i18n("Copies of your Plasma widget settings, made automatically before a clean-up. Safe to remove once you are happy with how the widget works; it never needs them to run.")},
        {"id": "caches", "title": i18n("Temporary files"),
         "text": i18n("Short-lived files the widget makes while it works (spoken audio, recordings and logs). Safe to remove; the widget makes new ones when needed.")},
        {"id": "voice_old", "title": i18n("Old voice engines (no longer used)"),
         "text": i18n("Programs and speech models that earlier versions of the widget installed for reading aloud and dictation. Voice now uses the separate app Speech Note, so you can remove these to free space. Removing them also stops their background services.")},
        {"id": "other", "title": i18n("Other files"),
         "text": i18n("Small files the widget needs, such as connection details for its helper programs. They can't be removed here.")}
    ]

    function refresh() {
        loading = true;
        helperRunner.run("storage_usage", {}, function(stdout, exitCode, stderr) {
            page.loading = false;
            var data = Fmt.parse(stdout);
            if (data) {
                page.usage = data;
                page.errorText = "";
            } else {
                page.errorText = i18n("Could not work out the sizes.");
            }
        });
    }

    function itemInfo(id) {
        return Fmt.find(usage, id);
    }

    function openFolder(path) {
        if (path)
            openUrl(Fmt.fileUrl(path));
    }

    function titleOf(id) {
        for (var i = 0; i < rows.length; i++)
            if (rows[i].id === id)
                return rows[i].title;
        return id;
    }

    function askRemove(id) {
        pendingItem = id;
        confirm.open();
    }

    function removeItem(id) {
        doneText = "";
        errorText = "";
        helperRunner.run("storage_remove", {"item": id, "confirm": true}, function(stdout, exitCode, stderr) {
            var data = null;
            try {
                data = JSON.parse(String(stdout).trim().split("\n").pop());
            } catch (e) {
                data = null;
            }
            if (data && data.type === "storage_removed")
                page.doneText = i18n("Removed. %1 freed.", Fmt.size(data.freed));
            else
                page.errorText = data && data.error ? data.error : i18n("Could not remove it.");
            page.refresh();
        });
    }

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    Kirigami.PromptDialog {
        id: confirm
        objectName: "storageConfirm"
        title: i18n("Remove %1?", page.titleOf(page.pendingItem))
        subtitle: {
            var info = page.itemInfo(page.pendingItem);
            return i18n("This frees %1 and can't be undone.", Fmt.size(info ? info.size : 0));
        }
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: page.removeItem(page.pendingItem)
    }

    Component.onCompleted: refresh()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("Everything the widget keeps on this computer is in one folder. It can't be moved. Your API keys are not in it: they are kept in KDE Wallet.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("Folder:")
                font.bold: true
            }
            QQC2.Label {
                objectName: "storageRoot"
                Layout.fillWidth: true
                text: page.usage ? Paths.tilde(page.usage.root, StandardPaths.writableLocation(StandardPaths.HomeLocation)) : ""
                elide: Text.ElideMiddle
                font.family: "monospace"
            }
            QQC2.Button {
                objectName: "storageOpenRoot"
                icon.name: "folder-open"
                text: i18n("Open folder")
                enabled: page.usage !== null && page.usage.root_exists === true
                onClicked: page.openFolder(page.usage.root)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                objectName: "storageTotal"
                Layout.fillWidth: true
                font.bold: true
                wrapMode: Text.Wrap
                text: page.usage === null ? (page.loading ? i18n("Counting…") : "")
                      : page.usage.partial ? i18n("In total: at least %1", Fmt.size(page.usage.total))
                      : i18n("In total: %1", Fmt.size(page.usage.total))
            }
            QQC2.Button {
                objectName: "storageRefresh"
                icon.name: "view-refresh"
                text: i18n("Refresh")
                enabled: !page.loading
                onClicked: page.refresh()
            }
        }

        Kirigami.InlineMessage {
            objectName: "storageError"
            Layout.fillWidth: true
            visible: page.errorText !== ""
            type: Kirigami.MessageType.Error
            text: page.errorText
        }

        Kirigami.InlineMessage {
            objectName: "storageDone"
            Layout.fillWidth: true
            visible: page.doneText !== ""
            type: Kirigami.MessageType.Positive
            text: page.doneText
        }

        Repeater {
            model: page.rows

            Config.StorageRow {
                id: line
                required property var modelData
                readonly property var info: page.itemInfo(modelData.id)
                objectName: "storageRow-" + modelData.id

                // The old voice engines only show while some are left.
                visible: page.usage !== null && (modelData.id !== "voice_old" || (info !== null && info.size > 0))
                Layout.fillWidth: true
                title: modelData.title
                description: modelData.text
                size: info ? info.size : 0
                folder: info ? info.folder : ""
                removable: info ? info.removable === true : false
                onOpenRequested: page.openFolder(folder)
                onRemoveRequested: page.askRemove(modelData.id)
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: page.usage !== null && page.usage.speech_note.exists === true
        }

        ColumnLayout {
            objectName: "storageSpeechNote"
            Layout.fillWidth: true
            spacing: 0
            visible: page.usage !== null && page.usage.speech_note.exists === true

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18n("Speech models are kept by Speech Note")
                    font.bold: true
                    wrapMode: Text.Wrap
                }
                QQC2.Button {
                    objectName: "storageOpenSpeechNote"
                    icon.name: "folder-open"
                    text: i18n("Open folder")
                    onClicked: page.openFolder(page.usage.speech_note.folder)
                }
            }

            Config.SettingHelp {
                text: i18n("The voices and speech models used for reading aloud and dictation belong to the Speech Note app. They are not counted above and this widget never removes them; manage them in Speech Note.")
            }
        }
    }
}
