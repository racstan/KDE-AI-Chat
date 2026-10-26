// Create or edit one schedule: a title, the editor (config/ScheduleEditor.qml)
// and Save / Cancel. Saving goes through schedule_save, which validates the
// schedule and writes its systemd timer; its error is shown here and nothing
// closes until it succeeds. Used by Settings → Schedules and, for one chat,
// by the chat's "Schedule a message…" (chat/ScheduleOverlay.qml). It has no
// scrolling of its own: the host scrolls it.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "config" as Config
import "config/ScheduleDraft.js" as Draft

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: dialog

    property Config.ScheduleService service: null
    property var sessions: []
    property var configuration: null
    property var wallet: null
    property var xhrFactory: null

    property bool isNew: true
    property bool saving: false
    property string saveError: ""
    readonly property alias editor: form

    signal saved(var schedule)
    signal closed()

    function openNew(chatId) {
        isNew = true;
        _load(Draft.newSchedule(chatId || ""));
    }

    function openItem(item) {
        isNew = !item || !item.id;
        _load(Draft.fromListItem(item || {}));
    }

    function _load(draft) {
        saveError = "";
        saving = false;
        form.describer.cancel();
        form.showOptions = false;
        form.previewResult = null;
        form.draft = draft;
    }

    function save() {
        if (!service || saving)
            return;
        saving = true;
        saveError = "";
        service.save(Draft.forSave(form.draft), function(result) {
            dialog.saving = false;
            if (result.ok) {
                dialog.saved(result.schedule);
                dialog.closed();
            } else {
                dialog.saveError = result.error || i18n("The schedule could not be saved.");
            }
        });
    }

    function cancel() {
        form.describer.cancel();
        closed();
    }

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        Kirigami.Heading {
            Layout.fillWidth: true
            level: 2
            elide: Text.ElideRight
            text: dialog.isNew ? i18n("New schedule") : i18n("Edit schedule")
        }
        QQC2.ToolButton {
            icon.name: "dialog-close"
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Close")
            onClicked: dialog.cancel()
        }
    }

    Config.ScheduleEditor {
        id: form
        Layout.fillWidth: true
        service: dialog.service
        sessions: dialog.sessions
        configuration: dialog.configuration
        wallet: dialog.wallet
        xhrFactory: dialog.xhrFactory
    }

    Kirigami.InlineMessage {
        objectName: "saveError"
        Layout.fillWidth: true
        visible: dialog.saveError !== ""
        type: Kirigami.MessageType.Error
        text: i18n("Not saved: %1", dialog.saveError)
    }

    RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        QQC2.Button {
            objectName: "saveSchedule"
            text: i18n("Save")
            icon.name: "document-save"
            enabled: form.rulesValid && !dialog.saving
            onClicked: dialog.save()
        }
        QQC2.Button {
            objectName: "cancelSchedule"
            text: i18n("Cancel")
            icon.name: "dialog-cancel"
            onClicked: dialog.cancel()
        }
    }
}
