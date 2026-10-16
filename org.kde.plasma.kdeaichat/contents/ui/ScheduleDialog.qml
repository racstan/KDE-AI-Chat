import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Lists, creates and edits scheduled prompts. Every change is saved right
// away through the hosting settings page (page.schedSaveAll()).
QQC2.Dialog {
    id: scheduleDialog

    // The settings page that owns the schedule store. Must be set when
    // instantiating: ScheduleDialog { page: configPage }
    property var page: null

    property int editingIndex: -1 // -2 = new, >= 0 = edit, -1 = list
    property var draft: ({})
    property string currentTab: "active"
    property var localActiveList: []
    property var localArchivedList: []
    property bool hasUnsavedChanges: false

    readonly property bool editing: editingIndex !== -1
    readonly property bool isSingle: (draft.taskType || "single") === "single"
    readonly property string repeatUnit: draft.schedType || "days"
    // A one-off schedule must be in the future to ever run.
    readonly property bool startsInPast: isSingle && new Date(draft.startDate || 0).getTime() < Date.now()

    Timer {
        id: refreshTimer
        interval: 5000
        repeat: true
        running: scheduleDialog.opened && scheduleDialog.editingIndex === -1
        onTriggered: {
            if (page && typeof page.schedLoadSchedules === "function")
                page.schedLoadSchedules();
        }
    }

    Connections {
        target: page
        ignoreUnknownSignals: true
        function onSchedulerListChanged() {
            if (scheduleDialog.opened && scheduleDialog.editingIndex === -1 && !scheduleDialog.hasUnsavedChanges)
                scheduleDialog.localActiveList = page.schedulerList.slice();
        }
        function onSchedulerArchivedListChanged() {
            if (scheduleDialog.opened && scheduleDialog.editingIndex === -1 && !scheduleDialog.hasUnsavedChanges)
                scheduleDialog.localArchivedList = page.schedulerArchivedList.slice();
        }
    }

    function updateDraft(patch) {
        let d = Object.assign({}, draft);
        for (let k in patch)
            d[k] = patch[k];
        draft = d;
    }

    function saveAndSync() {
        if (page) {
            page.schedulerList = localActiveList;
            page.schedulerArchivedList = localArchivedList;
            scheduleDialog.hasUnsavedChanges = false;
            page.schedSaveAll();
        }
    }

    // Chats a schedule can post into, read live from the widget's storage.
    // Chats with the same name get their last-used date to tell them apart.
    function getChatsList() {
        let raw = plasmoid.configuration.chatSessionsJson || "[]";
        let list = [];
        try {
            let arr = JSON.parse(raw);
            if (!Array.isArray(arr))
                return [];
            let counts = {};
            for (let i = 0; i < arr.length; i++) {
                if (arr[i] && arr[i].value && !arr[i].archived) {
                    let title = String(arr[i].text || "").trim();
                    if (title === "" || title === "New Chat")
                        title = i18n("New Chat");
                    counts[title] = (counts[title] || 0) + 1;
                    list.push({"id": arr[i].value, "title": title, "updatedAt": arr[i].updatedAt || arr[i].createdAt || 0});
                }
            }
            for (let j = 0; j < list.length; j++) {
                let item = list[j];
                item.name = counts[item.title] > 1 && item.updatedAt
                    ? i18nc("chat name (date last used)", "%1 (%2)", item.title, Qt.formatDate(new Date(item.updatedAt), Qt.locale().dateFormat(Locale.ShortFormat)))
                    : item.title;
            }
        } catch (e) {
            return [];
        }
        return list;
    }

    // Opens the editor with a new schedule.
    function startNewSchedule() {
        let now = new Date();
        now.setMinutes(now.getMinutes() + 5);
        now.setSeconds(0);
        now.setMilliseconds(0);
        let chats = getChatsList();
        draft = {
            "id": page.schedMakeUuid(),
            "name": "",
            "enabled": true,
            "chatId": chats.length > 0 ? chats[0].id : "",
            "chatName": chats.length > 0 ? chats[0].title : "",
            "message": "",
            "taskType": "single",
            "startDate": now.toISOString(),
            "schedType": "days",
            "schedEvery": 1,
            "schedTime": "09:00",
            "schedDays": [1],
            "schedDayOfMonth": 1,
            "limitEnabled": false,
            "limitCount": 5,
            "notify": true,
            "createdAt": new Date().toISOString()
        };
        editingIndex = -2;
    }

    // Build the cron rule the scheduler daemon runs on.
    function buildCron(d) {
        if (d.taskType === "single")
            return "";

        let t = d.schedType || "days", n = parseInt(d.schedEvery) || 1;
        let sDate = new Date(d.startDate || new Date().toISOString());
        let hr = sDate.getHours(), mn = sDate.getMinutes();
        if (t === "minutes")
            return "*/" + n + " * * * *";

        if (t === "hours")
            return "0 */" + n + " * * *";

        if (t === "days")
            return (n === 1 ? mn + " " + hr + " * * *" : mn + " " + hr + " */" + n + " * *");

        if (t === "weeks") {
            let ds = (d.schedDays && d.schedDays.length > 0) ? d.schedDays.slice().sort().join(",") : "1";
            return mn + " " + hr + " * * " + ds;
        }
        if (t === "months") {
            let dom = d.schedDayOfMonth || 1;
            return (n === 1 ? mn + " " + hr + " " + dom + " * *" : mn + " " + hr + " " + dom + " */" + n + " *");
        }
        return "0 9 * * *";
    }

    function startDateObject() {
        return new Date(draft.startDate || new Date().toISOString());
    }

    function setStartDateField(field, value) {
        let d = startDateObject();
        d.setSeconds(0);
        d.setMilliseconds(0);
        if (field === "year" || field === "month") {
            // Keep the day valid when the month gets shorter (no Feb 31).
            let year = field === "year" ? value : d.getFullYear();
            let month = field === "month" ? value : d.getMonth();
            let maxDay = new Date(year, month + 1, 0).getDate();
            d.setDate(Math.min(d.getDate(), maxDay));
            d.setFullYear(year);
            d.setMonth(month);
        } else if (field === "day") {
            d.setDate(value);
        } else if (field === "hour") {
            d.setHours(value);
        } else if (field === "minute") {
            d.setMinutes(value);
        }
        updateDraft({"startDate": d.toISOString()});
    }

    function unitLabel(unit, n) {
        switch (unit) {
        case "minutes": return i18np("minute", "minutes", n);
        case "hours": return i18np("hour", "hours", n);
        case "weeks": return i18np("week", "weeks", n);
        case "months": return i18np("month", "months", n);
        }
        return i18np("day", "days", n);
    }

    function formatTime(date) {
        return Qt.formatTime(date, Qt.locale().timeFormat(Locale.ShortFormat));
    }

    // Human-readable summary, built from whole translatable sentences.
    function humanText(d) {
        let sDate = new Date(d.startDate || new Date().toISOString());
        let time = formatTime(sDate);
        if (d.taskType === "single")
            return i18nc("%1 date, %2 time", "Once, on %1 at %2", Qt.formatDate(sDate, Qt.locale().dateFormat(Locale.LongFormat)), time);

        let t = d.schedType || "days", n = parseInt(d.schedEvery) || 1;
        let text = "";
        if (t === "minutes") {
            text = i18np("Every minute", "Every %1 minutes", n);
        } else if (t === "hours") {
            text = i18np("Every hour, on the hour", "Every %1 hours, on the hour", n);
        } else if (t === "days") {
            text = n === 1 ? i18n("Every day at %1", time) : i18n("Every %1 days at %2", n, time);
        } else if (t === "weeks") {
            let days = (d.schedDays && d.schedDays.length > 0 ? d.schedDays : [1]).map(function(x) {
                return Qt.locale().dayName(x, Locale.ShortFormat);
            }).join(", ");
            text = n === 1 ? i18nc("%1 list of weekdays, %2 time", "Every week on %1 at %2", days, time)
                           : i18nc("%1 number, %2 list of weekdays, %3 time", "Every %1 weeks on %2 at %3", n, days, time);
        } else if (t === "months") {
            let dom = d.schedDayOfMonth || 1;
            text = n === 1 ? i18nc("%1 day of the month, %2 time", "Every month on day %1 at %2", dom, time)
                           : i18nc("%1 number, %2 day of the month, %3 time", "Every %1 months on day %2 at %3", n, dom, time);
        }
        if (d.limitEnabled && d.limitCount)
            text = i18nc("%1 schedule description", "%1, at most %2 times", text, d.limitCount);
        return text;
    }

    function formatRunTime(iso) {
        if (!iso)
            return "";
        let clean = String(iso);
        if (clean.endsWith("Z"))
            clean = clean.substring(0, clean.length - 1);
        let dt = new Date(clean);
        return isNaN(dt.getTime()) ? String(iso) : dt.toLocaleString(Qt.locale(), Locale.ShortFormat);
    }

    function messagePreview(message) {
        let m = String(message || "").replace(/\s+/g, " ").trim();
        return m.length > 80 ? m.substring(0, 79) + "…" : m;
    }

    title: editingIndex === -2 ? i18n("New Schedule") : (editingIndex >= 0 ? i18n("Edit Schedule") : i18n("Scheduled Prompts"))
    modal: true
    width: Math.min(Kirigami.Units.gridUnit * 40, parent ? parent.width : Kirigami.Units.gridUnit * 40)
    height: Math.min(Kirigami.Units.gridUnit * 38, parent ? parent.height : Kirigami.Units.gridUnit * 38)
    standardButtons: QQC2.Dialog.NoButton
    onOpened: {
        if (page) {
            page.schedLoadSchedules();
            scheduleDialog.hasUnsavedChanges = false;
            localActiveList = page.schedulerList.slice();
            localArchivedList = page.schedulerArchivedList.slice();
        }
        if (editingIndex !== -2 && editingIndex < 0)
            editingIndex = -1;
    }
    onClosed: editingIndex = -1

    // Destructive actions ask first. pendingAction is a function to run.
    Kirigami.PromptDialog {
        id: confirmDialog

        property var pendingAction: null
        property string confirmText: ""

        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: confirmDialog.confirmText
                icon.name: "edit-delete"
                onTriggered: {
                    let action = confirmDialog.pendingAction;
                    confirmDialog.close();
                    if (action)
                        action();
                }
            },
            Kirigami.Action {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onTriggered: confirmDialog.close()
            }
        ]
    }

    function confirm(titleText, subtitleText, buttonText, action) {
        confirmDialog.title = titleText;
        confirmDialog.subtitle = subtitleText;
        confirmDialog.confirmText = buttonText;
        confirmDialog.pendingAction = action;
        confirmDialog.open();
    }

    // Shared row for active and archived schedules. Inline components can't
    // see this file's ids, so the dialog is passed in. Child items of an
    // instance become trailing action buttons.
    component ScheduleRow: QQC2.ItemDelegate {
        id: row

        property var dialog: null
        property var schedule: ({})
        property bool archived: false
        default property alias trailing: trailingRow.data
        signal toggled(bool enabled)

        width: ListView.view ? ListView.view.width : implicitWidth
        hoverEnabled: true
        down: false

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Switch {
                visible: !row.archived
                checked: !!row.schedule.enabled
                Accessible.name: checked ? i18n("Turn off this schedule") : i18n("Turn on this schedule")
                onToggled: row.toggled(checked)
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                opacity: row.archived || row.schedule.enabled ? 1 : 0.6

                QQC2.Label {
                    Layout.fillWidth: true
                    text: row.schedule.name || row.schedule.humanReadable || i18n("Unnamed schedule")
                    font.bold: true
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: row.schedule.chatName
                        ? i18nc("%1 schedule description, %2 chat name", "%1 · in “%2”", row.schedule.humanReadable || row.schedule.cron || "", row.schedule.chatName)
                        : (row.schedule.humanReadable || row.schedule.cron || "")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: !row.archived && !!row.schedule.enabled && !!row.schedule.nextRunAt
                    text: i18n("Next run: %1", row.dialog ? row.dialog.formatRunTime(row.schedule.nextRunAt) : "")
                    font: Kirigami.Theme.smallFont
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: row.schedule.taskType === "repeat" && !!row.schedule.limitEnabled
                    text: i18n("Ran %1 of %2 times", row.schedule.runCount || 0, row.schedule.limitCount || 5)
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: row.dialog ? row.dialog.messagePreview(row.schedule.message) : ""
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: trailingRow
                spacing: 0
            }
        }
    }

    // ── List view ──────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing
        visible: !scheduleDialog.editing

        QQC2.TabBar {
            id: tabBar

            Layout.fillWidth: true
            currentIndex: scheduleDialog.currentTab === "archived" ? 1 : (scheduleDialog.currentTab === "history" ? 2 : 0)

            QQC2.TabButton {
                text: i18n("Active (%1)", scheduleDialog.localActiveList.length)
                onClicked: scheduleDialog.currentTab = "active"
            }
            QQC2.TabButton {
                text: i18n("Paused (%1)", scheduleDialog.localArchivedList.length)
                onClicked: scheduleDialog.currentTab = "archived"
            }
            QQC2.TabButton {
                text: i18n("Past Runs (%1)", page ? page.schedulerHistory.length : 0)
                onClicked: scheduleDialog.currentTab = "history"
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // Active
            QQC2.ScrollView {
                ListView {
                    id: activeList

                    model: scheduleDialog.localActiveList
                    clip: true

                    delegate: ScheduleRow {
                        id: activeRow

                        required property int index
                        required property var modelData
                        dialog: scheduleDialog
                        schedule: modelData

                        function edit() {
                            let d = JSON.parse(JSON.stringify(activeRow.schedule));
                            if (!d.taskType) d.taskType = "repeat";
                            if (!d.startDate) {
                                let now = new Date();
                                now.setMinutes(now.getMinutes() + 5);
                                now.setSeconds(0);
                                now.setMilliseconds(0);
                                d.startDate = now.toISOString();
                            }
                            if (!d.schedType) d.schedType = "days";
                            if (!d.schedEvery) d.schedEvery = 1;
                            if (!d.schedTime) d.schedTime = "09:00";
                            if (!d.schedDays) d.schedDays = [1];
                            if (!d.schedDayOfMonth) d.schedDayOfMonth = 1;
                            scheduleDialog.draft = d;
                            scheduleDialog.editingIndex = activeRow.index;
                        }

                        onToggled: function(enabled) {
                            let copy = scheduleDialog.localActiveList.slice();
                            let s = JSON.parse(JSON.stringify(copy[activeRow.index]));
                            s.enabled = enabled;
                            if (enabled)
                                s.nextRunAt = "";
                            copy[activeRow.index] = s;
                            scheduleDialog.localActiveList = copy;
                            scheduleDialog.saveAndSync();
                        }
                        onClicked: activeRow.edit()

                            QQC2.ToolButton {
                                text: i18n("Edit")
                                icon.name: "document-edit"
                                display: QQC2.AbstractButton.IconOnly
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                onClicked: activeRow.edit()
                            }
                            QQC2.ToolButton {
                                text: i18n("Pause (keep for later)")
                                icon.name: "media-playback-pause"
                                display: QQC2.AbstractButton.IconOnly
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                onClicked: {
                                    let copyActive = scheduleDialog.localActiveList.slice();
                                    let item = copyActive.splice(activeRow.index, 1)[0];
                                    item.archived = true;
                                    let copyArchived = scheduleDialog.localArchivedList.slice();
                                    copyArchived.push(item);
                                    scheduleDialog.localActiveList = copyActive;
                                    scheduleDialog.localArchivedList = copyArchived;
                                    scheduleDialog.saveAndSync();
                                }
                            }
                            QQC2.ToolButton {
                                text: i18n("Delete")
                                icon.name: "edit-delete"
                                display: QQC2.AbstractButton.IconOnly
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                onClicked: {
                                    let idx = activeRow.index;
                                    scheduleDialog.confirm(i18n("Delete This Schedule?"),
                                        i18n("“%1” will be deleted. To stop it but keep it for later, use Pause instead.", activeRow.schedule.name || activeRow.schedule.humanReadable || ""),
                                        i18n("Delete"),
                                        function() {
                                            let copy = scheduleDialog.localActiveList.slice();
                                            copy.splice(idx, 1);
                                            scheduleDialog.localActiveList = copy;
                                            scheduleDialog.saveAndSync();
                                        });
                                }
                            }
                    }

                    Kirigami.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: activeList.count === 0
                        icon.name: "chronometer"
                        text: i18n("No scheduled prompts")
                        explanation: i18n("A scheduled prompt sends a message to a chat at a set time, once or repeatedly, and the assistant replies.")
                        helpfulAction: Kirigami.Action {
                            text: i18n("New Schedule…")
                            icon.name: "list-add"
                            onTriggered: scheduleDialog.startNewSchedule()
                        }
                    }
                }
            }

            // Paused
            QQC2.ScrollView {
                ListView {
                    id: archivedList

                    model: scheduleDialog.localArchivedList
                    clip: true

                    delegate: ScheduleRow {
                        id: archivedRow

                        required property int index
                        required property var modelData
                        dialog: scheduleDialog
                        schedule: modelData
                        archived: true

                            QQC2.ToolButton {
                                text: i18n("Resume")
                                icon.name: "media-playback-start"
                                display: QQC2.AbstractButton.IconOnly
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                onClicked: {
                                    let copyArchived = scheduleDialog.localArchivedList.slice();
                                    let item = copyArchived.splice(archivedRow.index, 1)[0];
                                    item.archived = false;
                                    item.nextRunAt = "";
                                    let copyActive = scheduleDialog.localActiveList.slice();
                                    copyActive.push(item);
                                    scheduleDialog.localActiveList = copyActive;
                                    scheduleDialog.localArchivedList = copyArchived;
                                    scheduleDialog.saveAndSync();
                                }
                            }
                            QQC2.ToolButton {
                                text: i18n("Delete")
                                icon.name: "edit-delete"
                                display: QQC2.AbstractButton.IconOnly
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                onClicked: {
                                    let idx = archivedRow.index;
                                    scheduleDialog.confirm(i18n("Delete This Schedule?"),
                                        i18n("“%1” will be deleted. This can't be undone.", archivedRow.schedule.name || archivedRow.schedule.humanReadable || ""),
                                        i18n("Delete"),
                                        function() {
                                            let copy = scheduleDialog.localArchivedList.slice();
                                            copy.splice(idx, 1);
                                            scheduleDialog.localArchivedList = copy;
                                            scheduleDialog.saveAndSync();
                                        });
                                }
                            }
                    }

                    Kirigami.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 4
                        visible: archivedList.count === 0
                        icon.name: "media-playback-pause"
                        text: i18n("No paused schedules")
                        explanation: i18n("Pause a schedule to stop it without losing its settings.")
                    }
                }
            }

            // Past runs
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: historyList

                        model: page ? page.schedulerHistory : []
                        clip: true

                        delegate: QQC2.ItemDelegate {
                            readonly property bool succeeded: !!modelData.status && modelData.status.indexOf("success") !== -1

                            width: ListView.view.width
                            down: false

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: succeeded ? "dialog-ok" : "dialog-error"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                                    Layout.alignment: Qt.AlignTop
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 0

                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: modelData.scheduleName || i18n("Unnamed schedule")
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: i18nc("%1 run result, %2 chat name, %3 date and time", "%1 · “%2” · %3",
                                                    succeeded ? i18n("Sent") : (modelData.status === "error" ? i18n("Failed") : String(modelData.status || "")),
                                                    modelData.chatName || i18n("Chat"), scheduleDialog.formatRunTime(modelData.timestamp))
                                        font: Kirigami.Theme.smallFont
                                        color: succeeded ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.negativeTextColor
                                        elide: Text.ElideRight
                                    }
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        text: scheduleDialog.messagePreview(modelData.message)
                                        font: Kirigami.Theme.smallFont
                                        color: Kirigami.Theme.disabledTextColor
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Kirigami.PlaceholderMessage {
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.gridUnit * 4
                            visible: historyList.count === 0
                            icon.name: "view-history"
                            text: i18n("No runs yet")
                            explanation: i18n("Each time a schedule runs, it's listed here.")
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                visible: tabBar.currentIndex === 0
                text: i18n("New Schedule…")
                icon.name: "list-add"
                onClicked: scheduleDialog.startNewSchedule()
            }
            QQC2.Button {
                visible: tabBar.currentIndex === 2
                text: i18n("Clear Past Runs…")
                icon.name: "edit-clear-history"
                enabled: !!page && page.schedulerHistory.length > 0
                onClicked: scheduleDialog.confirm(i18n("Clear Past Runs?"),
                    i18n("The list of past runs will be cleared. Your chats and schedules are not affected."),
                    i18n("Clear"),
                    function() {
                        page.schedulerHistory = [];
                        page.schedSaveAll();
                    })
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Changes are saved automatically.")
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
            }
            QQC2.Button {
                text: i18n("Close")
                icon.name: "dialog-close"
                onClicked: scheduleDialog.close()
            }
        }
    }

    // ── Editor ─────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: scheduleDialog.editing
        spacing: Kirigami.Units.smallSpacing

        QQC2.ScrollView {
            id: editorScroll

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth

            Kirigami.FormLayout {
                width: editorScroll.availableWidth

                QQC2.ComboBox {
                    id: chatComboBox

                    Kirigami.FormData.label: i18n("Send to chat:")
                    Layout.fillWidth: true
                    textRole: "name"
                    model: scheduleDialog.opened ? scheduleDialog.getChatsList() : []

                    function syncIndex() {
                        let targetId = scheduleDialog.draft.chatId || "";
                        for (let i = 0; i < (model ? model.length : 0); i++) {
                            if (model[i] && model[i].id === targetId) {
                                currentIndex = i;
                                return;
                            }
                        }
                        currentIndex = model && model.length > 0 ? 0 : -1;
                    }

                    Component.onCompleted: syncIndex()
                    onModelChanged: syncIndex()

                    Connections {
                        target: scheduleDialog
                        function onDraftChanged() {
                            chatComboBox.syncIndex();
                        }
                    }

                    onActivated: function(index) {
                        let selected = model[index];
                        if (selected && selected.id)
                            scheduleDialog.updateDraft({"chatId": selected.id, "chatName": selected.title});
                    }
                }

                QQC2.TextArea {
                    id: dlgMessage

                    Kirigami.FormData.label: i18n("Message:")
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                    maximumLength: 100000
                    wrapMode: TextEdit.Wrap
                    text: scheduleDialog.draft.message || ""
                    placeholderText: i18n("For example: What should I focus on today?")
                    onTextChanged: scheduleDialog.updateDraft({"message": text})
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18n("At the scheduled time this message is sent to the chat, and the assistant replies.")
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.disabledTextColor
                    wrapMode: Text.Wrap
                }

                QQC2.TextField {
                    id: dlgName

                    Kirigami.FormData.label: i18n("Name:")
                    Layout.fillWidth: true
                    text: scheduleDialog.draft.name || ""
                    placeholderText: i18n("Optional; the schedule description is used if empty")
                    onTextChanged: scheduleDialog.updateDraft({"name": text})
                }

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: i18n("When")
                }

                QQC2.RadioButton {
                    id: onceRadio
                    Kirigami.FormData.label: i18n("Runs:")
                    text: i18n("Once")
                    checked: scheduleDialog.isSingle
                    onClicked: {
                        scheduleDialog.updateDraft({"taskType": "single"});
                        onceRadio.checked = Qt.binding(function() { return scheduleDialog.isSingle; });
                        repeatRadio.checked = Qt.binding(function() { return !scheduleDialog.isSingle; });
                    }
                }
                QQC2.RadioButton {
                    id: repeatRadio
                    text: i18n("Repeatedly")
                    checked: !scheduleDialog.isSingle
                    onClicked: {
                        scheduleDialog.updateDraft({"taskType": "repeat"});
                        onceRadio.checked = Qt.binding(function() { return scheduleDialog.isSingle; });
                        repeatRadio.checked = Qt.binding(function() { return !scheduleDialog.isSingle; });
                    }
                }

                RowLayout {
                    Kirigami.FormData.label: scheduleDialog.isSingle ? i18n("Date:") : i18n("Starting:")
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.SpinBox {
                        id: startDaySpin
                        from: 1
                        to: new Date(scheduleDialog.startDateObject().getFullYear(), scheduleDialog.startDateObject().getMonth() + 1, 0).getDate()
                        value: scheduleDialog.startDateObject().getDate()
                        Accessible.name: i18n("Day")
                        onValueModified: scheduleDialog.setStartDateField("day", value)
                    }
                    QQC2.ComboBox {
                        model: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(function(m) { return Qt.locale().monthName(m, Locale.LongFormat); })
                        currentIndex: scheduleDialog.startDateObject().getMonth()
                        Accessible.name: i18n("Month")
                        onActivated: function(index) { scheduleDialog.setStartDateField("month", index); }
                    }
                    QQC2.SpinBox {
                        from: new Date().getFullYear()
                        to: new Date().getFullYear() + 5
                        value: scheduleDialog.startDateObject().getFullYear()
                        textFromValue: function(v) { return String(v); }
                        Accessible.name: i18n("Year")
                        onValueModified: scheduleDialog.setStartDateField("year", value)
                    }
                }

                RowLayout {
                    Kirigami.FormData.label: i18n("Time:")
                    visible: scheduleDialog.isSingle || (scheduleDialog.repeatUnit !== "minutes" && scheduleDialog.repeatUnit !== "hours")
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.SpinBox {
                        from: 0
                        to: 23
                        value: scheduleDialog.startDateObject().getHours()
                        textFromValue: function(v) { return (v < 10 ? "0" : "") + v; }
                        Accessible.name: i18n("Hour")
                        onValueModified: scheduleDialog.setStartDateField("hour", value)
                    }
                    QQC2.Label {
                        text: ":"
                    }
                    QQC2.SpinBox {
                        from: 0
                        to: 59
                        value: scheduleDialog.startDateObject().getMinutes()
                        textFromValue: function(v) { return (v < 10 ? "0" : "") + v; }
                        Accessible.name: i18n("Minute")
                        onValueModified: scheduleDialog.setStartDateField("minute", value)
                    }
                }

                RowLayout {
                    Kirigami.FormData.label: i18n("Repeat every:")
                    visible: !scheduleDialog.isSingle
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.SpinBox {
                        id: dlgEvery
                        from: 1
                        to: 999
                        value: scheduleDialog.draft.schedEvery || 1
                        Accessible.name: i18n("Repeat interval")
                        onValueModified: scheduleDialog.updateDraft({"schedEvery": value})
                    }
                    QQC2.ComboBox {
                        readonly property var units: ["minutes", "hours", "days", "weeks", "months"]
                        model: units.map(function(u) { return scheduleDialog.unitLabel(u, dlgEvery.value); })
                        currentIndex: Math.max(0, units.indexOf(scheduleDialog.repeatUnit))
                        Accessible.name: i18n("Repeat unit")
                        onActivated: function(index) { scheduleDialog.updateDraft({"schedType": units[index]}); }
                    }
                }

                Flow {
                    Kirigami.FormData.label: i18n("On:")
                    visible: !scheduleDialog.isSingle && scheduleDialog.repeatUnit === "weeks"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        // Start the week on the user's first day of the week.
                        model: [0, 1, 2, 3, 4, 5, 6].map(function(i) { return (i + Qt.locale().firstDayOfWeek) % 7; })

                        QQC2.Button {
                            required property int modelData
                            text: Qt.locale().dayName(modelData, Locale.ShortFormat)
                            checkable: true
                            checked: (scheduleDialog.draft.schedDays || [1]).indexOf(modelData) >= 0
                            Accessible.name: Qt.locale().dayName(modelData, Locale.LongFormat)
                            onClicked: {
                                let ds = (scheduleDialog.draft.schedDays || [1]).slice();
                                let pos = ds.indexOf(modelData);
                                if (pos >= 0) {
                                    if (ds.length > 1)
                                        ds.splice(pos, 1);
                                } else {
                                    ds.push(modelData);
                                    ds.sort();
                                }
                                scheduleDialog.updateDraft({"schedDays": ds});
                                checked = Qt.binding(function() { return (scheduleDialog.draft.schedDays || [1]).indexOf(modelData) >= 0; });
                            }
                        }
                    }
                }

                QQC2.SpinBox {
                    Kirigami.FormData.label: i18n("On day of the month:")
                    visible: !scheduleDialog.isSingle && scheduleDialog.repeatUnit === "months"
                    from: 1
                    to: 28
                    value: scheduleDialog.draft.schedDayOfMonth || 1
                    onValueModified: scheduleDialog.updateDraft({"schedDayOfMonth": value})
                }

                RowLayout {
                    Kirigami.FormData.label: i18n("Stop after:")
                    visible: !scheduleDialog.isSingle
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.CheckBox {
                        id: limitCheckbox
                        text: i18n("A number of runs")
                        checked: !!scheduleDialog.draft.limitEnabled
                        onToggled: scheduleDialog.updateDraft({"limitEnabled": checked})
                    }
                    QQC2.SpinBox {
                        enabled: limitCheckbox.checked
                        from: 1
                        to: 9999
                        value: scheduleDialog.draft.limitCount || 5
                        Accessible.name: i18n("Number of runs")
                        onValueModified: scheduleDialog.updateDraft({"limitCount": value})
                    }
                }

                QQC2.CheckBox {
                    Kirigami.FormData.label: i18n("Notification:")
                    text: i18n("Notify me when this runs")
                    checked: scheduleDialog.draft.notify !== false
                    onToggled: scheduleDialog.updateDraft({"notify": checked})
                }

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                }

                QQC2.Label {
                    Kirigami.FormData.label: i18n("Summary:")
                    Layout.fillWidth: true
                    text: scheduleDialog.humanText(scheduleDialog.draft)
                    wrapMode: Text.Wrap
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: scheduleDialog.startsInPast
            type: Kirigami.MessageType.Warning
            text: i18n("This time has already passed. Choose a time in the future.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: chatComboBox.count === 0
            type: Kirigami.MessageType.Warning
            text: i18n("There is no chat to send to. Start a chat first.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Item {
                Layout.fillWidth: true
            }

            QQC2.Button {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onClicked: scheduleDialog.editingIndex = -1
            }

            QQC2.Button {
                text: scheduleDialog.editingIndex === -2 ? i18n("Create Schedule") : i18n("Save")
                icon.name: "dialog-ok-apply"
                highlighted: true
                enabled: dlgMessage.text.trim() !== "" && !scheduleDialog.startsInPast && chatComboBox.count > 0
                onClicked: {
                    let d = Object.assign({}, scheduleDialog.draft);
                    d.cron = scheduleDialog.buildCron(d);
                    d.humanReadable = scheduleDialog.humanText(d);
                    if (!d.name || d.name.trim() === "")
                        d.name = d.humanReadable;
                    d.nextRunAt = "";

                    let copy = scheduleDialog.localActiveList.slice();
                    if (scheduleDialog.editingIndex === -2)
                        copy.push(d);
                    else
                        copy[scheduleDialog.editingIndex] = d;
                    scheduleDialog.localActiveList = copy;
                    scheduleDialog.saveAndSync();
                    scheduleDialog.editingIndex = -1;
                }
            }
        }
    }
}
