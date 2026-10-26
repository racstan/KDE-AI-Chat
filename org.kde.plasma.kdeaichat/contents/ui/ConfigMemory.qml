// Settings → Memory: memory on or off for every chat (memoryEnabled, a
// plain setting saved on Apply), and the memories themselves: search, filter,
// add, edit, pin, turn on or off, delete (with Undo).
//
// The memories are never settings (no cfg_ property): they live in the
// helper's memory.json, and every change here goes to the helper at once
// through a store/MemoryStore.qml. Chat and project names for "where it
// applies" are read from this widget's chats folder (store/ChatStore.qml);
// a memory of a chat or project that isn't found shows as "One chat" /
// "One project".
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtCore
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "store" as Store
import "config" as Config
import "config/MemoryList.js" as MemoryList

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property alias cfg_memoryEnabled: enabledSwitch.checked

    readonly property var plasmoidObject: typeof plasmoid !== "undefined" ? plasmoid : null
    // Runs the helper's commands; a property so a test can pass a fake.
    property var helperRunner: defaultRunner
    // {chatId: title} and {projectId: name}; filled from the chats folder
    // unless a test sets them.
    property var chatTitles: null
    property var projectNames: null

    property string query: ""
    property string filter: "any"
    // The memory deleted last, for Undo.
    property var lastDeleted: null

    readonly property var shown: MemoryList.visible(store.list, query, filter, function(m) { return page.scopeText(m); })
    readonly property var offIds: MemoryList.disabledIds(store.list)

    function scopeText(m) {
        if (m.scope === "chat") {
            var title = (chatTitles || {})[m.chatId];
            return title ? i18n("Chat “%1”", title) : i18n("One chat");
        }
        if (m.scope === "project") {
            var name = (projectNames || {})[m.projectId];
            return name ? i18n("Project “%1”", name) : i18n("One project");
        }
        return i18n("All chats");
    }

    function addMemory() {
        var text = addField.text.trim();
        if (text === "")
            return;
        store.add({"text": text, "scope": "all"}, function(ok, result) {
            if (ok)
                addField.text = "";
        });
    }

    function removeMemory(m) {
        lastDeleted = m;
        undoTimer.restart();
        store.remove(m.id, null);
    }

    // Undo is offered for a while after a delete.
    Timer {
        id: undoTimer
        interval: 15000
        onTriggered: page.lastDeleted = null
    }

    function undoDelete() {
        var m = lastDeleted;
        lastDeleted = null;
        if (m)
            store.restore([m], null);
    }

    function turnAllOn() {
        offIds.forEach(function(id) { store.setEnabled(id, true, null); });
    }

    Store.MemoryStore {
        id: store
        runHelper: function(command, payload, onDone) { page.helperRunner.run(command, payload, onDone); }
    }

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    // Only for reading the chat and project names.
    readonly property Store.ChatStore chatIndex: Store.ChatStore {
        directory: page.plasmoidObject && String(page.plasmoidObject.id) !== ""
            ? decodeURIComponent(String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)).replace(/^file:\/\//, ""))
              + "/kdeaichat/chats/applet-" + page.plasmoidObject.id
            : ""
    }

    Component.onCompleted: {
        if (chatTitles === null)
            chatTitles = MemoryList.chatTitles(page.chatIndex.indexJson());
        if (projectNames === null)
            projectNames = MemoryList.projectNames(page.chatIndex.loadProjects());
        store.load(null);
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Switch {
                id: enabledSwitch
                objectName: "memoryEnabledSwitch"
                Kirigami.FormData.label: i18n("Memory:")
                text: i18n("Use memories in chats")
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("Memories are notes you ask the assistant to keep. Only the ones that fit what you ask (and pinned ones) go with a message. Save one with Remember under a message or /remember.")
        }

        Kirigami.InlineMessage {
            objectName: "memoryOffMessage"
            Layout.fillWidth: true
            visible: page.offIds.length > 0
            type: Kirigami.MessageType.Information
            text: i18np("1 memory is turned off and is never sent. Memories brought over from the old version start off.",
                        "%1 memories are turned off and are never sent. Memories brought over from the old version start off.", page.offIds.length)
            actions: [
                Kirigami.Action {
                    text: i18n("Turn on all")
                    icon.name: "checkmark"
                    onTriggered: page.turnAllOn()
                }
            ]
        }

        Kirigami.InlineMessage {
            objectName: "memoryDeletedMessage"
            Layout.fillWidth: true
            visible: page.lastDeleted !== null
            type: Kirigami.MessageType.Positive
            text: i18n("Memory deleted.")
            actions: [
                Kirigami.Action {
                    text: i18n("Undo")
                    icon.name: "edit-undo"
                    onTriggered: page.undoDelete()
                }
            ]
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: store.lastError !== ""
            type: Kirigami.MessageType.Error
            text: i18n("The last change could not be saved: %1", store.lastError)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: addField
                objectName: "memoryAddField"
                Layout.fillWidth: true
                placeholderText: i18n("Add a memory for all chats…")
                maximumLength: 4000
                onAccepted: page.addMemory()
            }
            QQC2.Button {
                objectName: "memoryAddButton"
                text: i18n("Add")
                icon.name: "list-add"
                enabled: addField.text.trim() !== ""
                onClicked: page.addMemory()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.SearchField {
                objectName: "memorySearch"
                Layout.fillWidth: true
                onTextChanged: page.query = text
            }
            QQC2.ComboBox {
                objectName: "memoryFilter"
                textRole: "text"
                valueRole: "value"
                model: [
                    {"text": i18n("All memories"), "value": "any"},
                    {"text": i18n("For all chats"), "value": "all"},
                    {"text": i18n("For a project"), "value": "project"},
                    {"text": i18n("For one chat"), "value": "chat"},
                    {"text": i18n("Turned off"), "value": "off"}
                ]
                onActivated: page.filter = currentValue
            }
        }

        QQC2.Label {
            objectName: "memoryEmpty"
            Layout.fillWidth: true
            visible: page.shown.length === 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            opacity: 0.6
            text: !store.loaded ? i18n("Loading…")
                : store.list.length === 0 ? i18n("No memories yet.") : i18n("No memories match.")
        }

        Repeater {
            model: page.shown

            delegate: ColumnLayout {
                id: item
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: item.index > 0
                }
                Config.MemoryRow {
                    Layout.fillWidth: true
                    memory: item.modelData
                    scopeText: page.scopeText(item.modelData)
                    onToggleEnabled: function(on) { store.setEnabled(item.modelData.id, on, null); }
                    onTogglePinned: function(on) { store.setPinned(item.modelData.id, on, null); }
                    onSaveText: function(text) { store.update(item.modelData.id, {"text": text}, null); }
                    onRemove: page.removeMemory(item.modelData)
                }
            }
        }
    }
}
