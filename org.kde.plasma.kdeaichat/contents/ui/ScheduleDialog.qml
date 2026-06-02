import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

    QQC2.Dialog {
        id: scheduleDialog

        property int editingIndex: -1 // -2=new, >=0=edit, -1=list
        property var draft: ({
        })
        property string currentTab: "active"
        property bool rtlLayout: false

        LayoutMirroring.enabled: rtlLayout
        LayoutMirroring.childrenInherit: true

        function translate(text) {
            return page.translate(text);
        }

        function getChatsList() {
            var raw = plasmoid.configuration.chatSessionsJson || "[]";
            try {
                var arr = JSON.parse(raw);
                var list = [];
                if (Array.isArray(arr)) {
                    for (var i = 0; i < arr.length; i++) {
                        var session = arr[i];
                        if (session && !session.archived) {
                            var rawId = session.id || session.value || "";
                            var rawTitle = session.title || session.text || "Chat";
                            if (rawId) {
                                var displayId = rawId;
                                if (rawId.length > 10) {
                                    displayId = rawId.substring(0, 8) + "...";
                                }
                                list.push({
                                    "id": rawId,
                                    "name": rawTitle + " (" + displayId + ")"
                                });
                            }
                        }
                    }
                }
                return list;
            } catch (e) {
                return [];
            }
        }

        // Validate a 5-field cron expression; returns {valid:bool, message:string}
        function validateCron(cronStr) {
            if (!cronStr || cronStr.trim() === "")
                return {valid: true, message: ""};

            var parts = cronStr.trim().split(/\s+/);
            if (parts.length !== 5)
                return {valid: false, message: translate("Cron must have 5 fields (min hour day month weekday)")};

            var ranges = [
                {name: "minute", lo: 0, hi: 59},
                {name: "hour", lo: 0, hi: 23},
                {name: "day", lo: 1, hi: 31},
                {name: "month", lo: 1, hi: 12},
                {name: "weekday", lo: 0, hi: 7}
            ];
            for (var i = 0; i < 5; i++) {
                var r = ranges[i];
                var items = parts[i].split(",");
                for (var j = 0; j < items.length; j++) {
                    var v = items[j];
                    if (v === "*") continue;
                    
                    var mSingle = v.match(/^\d+$/);
                    var mRange = v.match(/^(\d+)-(\d+)$/);
                    var mStep = v.match(/^(\d+|\*)\/(\d+)$/);
                    var mRangeStep = v.match(/^(\d+)-(\d+)\/(\d+)$/);
                    
                    if (mSingle) {
                        var n = parseInt(v);
                        if (n < r.lo || n > r.hi)
                            return {valid: false, message: translate("'%1' out of range %2-%3 for %4").arg(v).arg(r.lo).arg(r.hi).arg(r.name)};
                    } else if (mRange) {
                        var a = parseInt(mRange[1]), b = parseInt(mRange[2]);
                        if (a < r.lo || b > r.hi || a > b)
                            return {valid: false, message: translate("Range %1-%2 invalid for %3").arg(a).arg(b).arg(r.name)};
                    } else if (mStep) {
                        var base = mStep[1], step = parseInt(mStep[2]);
                        if (step < 1)
                            return {valid: false, message: translate("Step < 1 in %1 field").arg(r.name)};
                        if (base !== "*") {
                            var bVal = parseInt(base);
                            if (bVal < r.lo || bVal > r.hi)
                                return {valid: false, message: translate("Base out of range in %1").arg(r.name)};
                        }
                    } else if (mRangeStep) {
                        var ra = parseInt(mRangeStep[1]), rb = parseInt(mRangeStep[2]), rstep = parseInt(mRangeStep[3]);
                        if (rstep < 1)
                            return {valid: false, message: translate("Step < 1 in %1 field").arg(r.name)};
                        if (ra < r.lo || rb > r.hi || ra > rb)
                            return {valid: false, message: translate("Range %1-%2 invalid for %3").arg(ra).arg(rb).arg(r.name)};
                    } else {
                        return {valid: false, message: translate("Invalid cron item '%1' in %2 field").arg(v).arg(r.name)};
                    }
                }
            }
            return {valid: true, message: ""};
        }

        // Helper: build cron from draft
        function buildCron(d) {
            if (d.taskType === "single")
                return "";

            var t = d.schedType || "days", n = parseInt(d.schedEvery) || 1;
            var tp = (d.schedTime || "09:00").split(":");
            var hr = parseInt(tp[0]) || 9, mn = parseInt(tp[1]) || 0;
            if (t === "minutes")
                return "*/" + n + " * * * *";

            if (t === "hours")
                return "0 */" + n + " * * *";

            if (t === "days")
                return (n === 1 ? mn + " " + hr + " * * *" : mn + " " + hr + " */" + n + " * *");

            if (t === "weeks") {
                var ds = (d.schedDays && d.schedDays.length > 0) ? d.schedDays.slice().sort().join(",") : "1";
                return mn + " " + hr + " * * " + ds;
            }
            if (t === "months") {
                var dom = d.schedDayOfMonth || 1;
                return (n === 1 ? mn + " " + hr + " " + dom + " * *" : mn + " " + hr + " " + dom + " */" + n + " *");
            }
            return "0 9 * * *";
        }

        function getStartYear(dateStr) {
            if (!dateStr)
                return new Date().getFullYear();

            return new Date(dateStr).getFullYear();
        }

        function getStartMonth(dateStr) {
            if (!dateStr)
                return new Date().getMonth();

            return new Date(dateStr).getMonth();
        }

        function getStartDay(dateStr) {
            if (!dateStr)
                return new Date().getDate();

            return new Date(dateStr).getDate();
        }

        function getStartHour(dateStr) {
            if (!dateStr)
                return 9;

            return new Date(dateStr).getHours();
        }

        function getStartMin(dateStr) {
            if (!dateStr)
                return 0;

            return new Date(dateStr).getMinutes();
        }

        function setStartDateField(field, value) {
            var d = new Date(scheduleDialog.draft.startDate || new Date().toISOString());
            if (field === "year")
                d.setFullYear(value);
            else if (field === "month")
                d.setMonth(value);
            else if (field === "day")
                d.setDate(value);
            else if (field === "hour")
                d.setHours(value);
            else if (field === "minute")
                d.setMinutes(value);
            scheduleDialog.draft = Object.assign({
            }, scheduleDialog.draft, {
                "startDate": d.toISOString()
            });
        }

        // Helper: human-readable summary
        function humanText(d) {
            if (d.taskType === "single") {
                var sDate = new Date(d.startDate || new Date().toISOString());
                var monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                var shr = sDate.getHours(), smn = sDate.getMinutes();
                var sap = shr >= 12 ? translate("PM") : translate("AM"), sh12 = shr % 12 || 12;
                var sms = smn < 10 ? "0" + smn : "" + smn;
                var stimeStr = sh12 + ":" + sms + " " + sap;
                return translate("Once on") + " " + translate(monthNames[sDate.getMonth()]) + " " + sDate.getDate() + ", " + sDate.getFullYear() + " " + translate("at") + " " + stimeStr;
            }
            var t = d.schedType || "days", n = parseInt(d.schedEvery) || 1;
            var tp = (d.schedTime || "09:00").split(":");
            var hr = parseInt(tp[0]) || 9, mn = parseInt(tp[1]) || 0;
            var ap = hr >= 12 ? translate("PM") : translate("AM"), h12 = hr % 12 || 12;
            var ms = mn < 10 ? "0" + mn : "" + mn;
            var timeStr = h12 + ":" + ms + " " + ap;
            var baseText = "";
            if (t === "minutes") {
                baseText = translate("Every") + " " + (n === 1 ? translate("minute") : n + " " + translate("minutes"));
            } else if (t === "hours") {
                baseText = translate("Every") + " " + (n === 1 ? translate("hour") : n + " " + translate("hours"));
            } else if (t === "days") {
                baseText = translate("Every") + " " + (n === 1 ? translate("day") : n + " " + translate("days")) + " " + translate("at") + " " + timeStr;
            } else if (t === "weeks") {
                var dn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                var days = (d.schedDays && d.schedDays.length > 0) ? d.schedDays.map(function(x) {
                    return translate(dn[x]);
                }).join(", ") : translate("Mon");
                baseText = translate("Every") + " " + (n === 1 ? translate("week") : n + " " + translate("weeks")) + " " + translate("on") + " " + days + " " + translate("at") + " " + timeStr;
            } else if (t === "months") {
                var dom = d.schedDayOfMonth || 1;
                var sfx = dom === 1 ? translate("st") : dom === 2 ? translate("nd") : dom === 3 ? translate("rd") : translate("th");
                baseText = translate("Every") + " " + (n === 1 ? translate("month") : n + " " + translate("months")) + " " + translate("on the") + " " + dom + sfx + " " + translate("at") + " " + timeStr;
            }
            if (d.limitEnabled && d.limitCount)
                baseText += " (" + translate("Limit:") + " " + d.limitCount + " " + (d.limitCount === 1 ? translate("run") : translate("runs")) + ")";

            return baseText;
        }

        title: (editingIndex === -2) ? translate("Create Schedule") : ((editingIndex >= 0) ? translate("Edit Schedule") : translate("Schedules"))
        modal: true
        width: Math.min(parent.width * 0.95, Kirigami.Units.gridUnit * 50)
        height: Math.min(parent.height * 0.92, Kirigami.Units.gridUnit * 46)
        standardButtons: QQC2.Dialog.Close
        onOpened: {
            schedLoadSchedules();
            if (editingIndex !== -2 && editingIndex < 0) {
                editingIndex = -1;
            }
        }

        // ── List view ──────────────────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            visible: scheduleDialog.editingIndex === -1

            // ── Segmented Tab Selector ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                
                QQC2.Button {
                    text: translate("Active") + " (" + page.schedulerList.length + ")"
                    icon.name: "appointment-new"
                    highlighted: scheduleDialog.currentTab === "active"
                    flat: scheduleDialog.currentTab !== "active"
                    Layout.fillWidth: true
                    onClicked: scheduleDialog.currentTab = "active"
                }

                QQC2.Button {
                    text: translate("Archived") + " (" + page.schedulerArchivedList.length + ")"
                    icon.name: "archive-insert"
                    highlighted: scheduleDialog.currentTab === "archived"
                    flat: scheduleDialog.currentTab !== "archived"
                    Layout.fillWidth: true
                    onClicked: scheduleDialog.currentTab = "archived"
                }

                QQC2.Button {
                    text: translate("History") + " (" + page.schedulerHistory.length + ")"
                    icon.name: "view-history"
                    highlighted: scheduleDialog.currentTab === "history"
                    flat: scheduleDialog.currentTab !== "history"
                    Layout.fillWidth: true
                    onClicked: scheduleDialog.currentTab = "history"
                }
            }

            // ── Active Tab Header ──
            RowLayout {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "active"

                QQC2.Label {
                    text: page.schedulerList.length === 0 ? translate("No schedules configured yet") : (page.schedulerList.length === 1 ? translate("1 active schedule") : translate("%1 active schedules").arg(page.schedulerList.length))
                    opacity: 0.7
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    text: translate("New Schedule")
                    icon.name: "list-add"
                    highlighted: true
                    onClicked: {
                        var now = new Date();
                        now.setMinutes(now.getMinutes() + 5);
                        var chats = scheduleDialog.getChatsList();
                        var firstChatId = (chats.length > 0) ? chats[0].id : "";
                        var firstChatName = (chats.length > 0) ? chats[0].name : "";
                        scheduleDialog.draft = {
                            "id": page.schedMakeUuid(),
                            "name": "",
                            "enabled": true,
                            "chatId": firstChatId,
                            "chatName": firstChatName,
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
                        scheduleDialog.editingIndex = -2;
                    }
                }
            }

            // ── Archived Tab Header ──
            RowLayout {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "archived"

                QQC2.Label {
                    text: page.schedulerArchivedList.length === 0 ? translate("No archived schedules") : (page.schedulerArchivedList.length === 1 ? translate("1 archived schedule") : translate("%1 archived schedules").arg(page.schedulerArchivedList.length))
                    opacity: 0.7
                    Layout.fillWidth: true
                }
            }

            // ── History Tab Header ──
            RowLayout {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "history"

                QQC2.Label {
                    text: page.schedulerHistory.length === 0 ? translate("No executed runs history") : (page.schedulerHistory.length === 1 ? translate("1 executed run logged") : translate("%1 executed runs logged").arg(page.schedulerHistory.length))
                    opacity: 0.7
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    text: translate("Clear History")
                    icon.name: "edit-clear-all"
                    enabled: page.schedulerHistory.length > 0
                    onClicked: {
                        page.schedulerHistory = [];
                        page.schedSaveAll();
                    }
                }
            }

            // ── Empty State Inline Messages ──
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "active" && page.schedulerList.length === 0
                type: Kirigami.MessageType.Information
                text: translate("No active schedules configured yet. Click <b>New Schedule</b> to create one, or type <b>/schedule</b> in any chat.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "archived" && page.schedulerArchivedList.length === 0
                type: Kirigami.MessageType.Information
                text: translate("No archived schedules. You can archive active schedules to temporarily pause them without losing their settings.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: scheduleDialog.currentTab === "history" && page.schedulerHistory.length === 0
                type: Kirigami.MessageType.Information
                text: translate("No history logs yet. Completed schedules and recurring run results will automatically appear here once triggered.")
            }

            // ── Scrollable Lists Area ──
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // ── 1. ACTIVE SCHEDULES LIST ──
                ListView {
                    id: activeSchedListView
                    visible: scheduleDialog.currentTab === "active"
                    anchors.fill: parent
                    model: page.schedulerList
                    spacing: Kirigami.Units.smallSpacing

                    delegate: Rectangle {
                        width: activeSchedListView.width
                        height: 74
                        radius: 6
                        color: modelData.enabled ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.07) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        border.width: 1
                        opacity: modelData.enabled ? 1 : 0.55

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            anchors {
                                fill: parent
                                margins: Kirigami.Units.smallSpacing * 1.5
                            }

                            QQC2.Switch {
                                checked: modelData.enabled
                                onToggled: {
                                    var copy = page.schedulerList.slice();
                                    var s = JSON.parse(JSON.stringify(copy[index]));
                                    s.enabled = checked;
                                    copy[index] = s;
                                    page.schedulerList = copy;
                                    page.schedSaveSchedules(copy);
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                QQC2.Label {
                                    text: modelData.name || modelData.humanReadable || translate("Unnamed")
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "⏱ " + (modelData.humanReadable || modelData.cron || "") + (modelData.chatName ? " · 💬 " + modelData.chatName : "")
                                    font.pixelSize: 11
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "\"" + (modelData.message || "").substring(0, 60) + ((modelData.message || "").length > 60 ? "…" : "") + "\""
                                    font.pixelSize: 10
                                    opacity: 0.5
                                    elide: Text.ElideRight
                                    font.italic: true
                                    Layout.fillWidth: true
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "document-edit"
                                QQC2.ToolTip.text: translate("Edit")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    var d = JSON.parse(JSON.stringify(modelData));
                                    if (!d.taskType)
                                        d.taskType = "repeat";

                                    if (!d.startDate) {
                                        var now = new Date();
                                        now.setMinutes(now.getMinutes() + 5);
                                        d.startDate = now.toISOString();
                                    }
                                    if (!d.schedType)
                                        d.schedType = "days";

                                    if (!d.schedEvery)
                                        d.schedEvery = 1;

                                    if (!d.schedTime)
                                        d.schedTime = "09:00";

                                    if (!d.schedDays)
                                        d.schedDays = [1];

                                    if (!d.schedDayOfMonth)
                                        d.schedDayOfMonth = 1;

                                    scheduleDialog.draft = d;
                                    scheduleDialog.editingIndex = index;
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "archive-insert"
                                QQC2.ToolTip.text: translate("Archive")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    var copyActive = page.schedulerList.slice();
                                    var item = copyActive.splice(index, 1)[0];
                                    item.archived = true;

                                    var copyArchived = page.schedulerArchivedList.slice();
                                    copyArchived.push(item);

                                    page.schedulerList = copyActive;
                                    page.schedulerArchivedList = copyArchived;
                                    page.schedSaveAll();
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "edit-delete"
                                QQC2.ToolTip.text: translate("Remove")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    var copy = page.schedulerList.slice();
                                    copy.splice(index, 1);
                                    page.schedulerList = copy;
                                    page.schedSaveSchedules(copy);
                                }
                            }
                        }
                    }
                }

                // ── 2. ARCHIVED SCHEDULES LIST ──
                ListView {
                    id: archivedSchedListView
                    visible: scheduleDialog.currentTab === "archived"
                    anchors.fill: parent
                    model: page.schedulerArchivedList
                    spacing: Kirigami.Units.smallSpacing

                    delegate: Rectangle {
                        width: archivedSchedListView.width
                        height: 74
                        radius: 6
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        border.width: 1
                        opacity: 0.7

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            anchors {
                                fill: parent
                                margins: Kirigami.Units.smallSpacing * 1.5
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                QQC2.Label {
                                    text: modelData.name || modelData.humanReadable || translate("Unnamed")
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "📁 " + (modelData.humanReadable || modelData.cron || "") + (modelData.chatName ? " · 💬 " + modelData.chatName : "")
                                    font.pixelSize: 11
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "\"" + (modelData.message || "").substring(0, 60) + ((modelData.message || "").length > 60 ? "…" : "") + "\""
                                    font.pixelSize: 10
                                    opacity: 0.5
                                    elide: Text.ElideRight
                                    font.italic: true
                                    Layout.fillWidth: true
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "archive-extract"
                                QQC2.ToolTip.text: translate("Restore to Active")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    var copyArchived = page.schedulerArchivedList.slice();
                                    var item = copyArchived.splice(index, 1)[0];
                                    item.archived = false;

                                    var copyActive = page.schedulerList.slice();
                                    copyActive.push(item);

                                    page.schedulerList = copyActive;
                                    page.schedulerArchivedList = copyArchived;
                                    page.schedSaveAll();
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "edit-delete"
                                QQC2.ToolTip.text: translate("Delete Permanently")
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: 500
                                onClicked: {
                                    var copyArchived = page.schedulerArchivedList.slice();
                                    copyArchived.splice(index, 1);
                                    page.schedulerArchivedList = copyArchived;
                                    page.schedSaveAll();
                                }
                            }
                        }
                    }
                }

                // ── 3. RUN HISTORY LIST ──
                ListView {
                    id: historySchedListView
                    visible: scheduleDialog.currentTab === "history"
                    anchors.fill: parent
                    model: page.schedulerHistory
                    spacing: Kirigami.Units.smallSpacing

                    delegate: Rectangle {
                        width: historySchedListView.width
                        height: 74
                        radius: 6
                        color: modelData.status === "success" ? Qt.rgba(0.18, 0.8, 0.44, 0.05) : Qt.rgba(0.9, 0.22, 0.22, 0.05)
                        border.color: modelData.status === "success" ? Qt.rgba(0.18, 0.8, 0.44, 0.15) : Qt.rgba(0.9, 0.22, 0.22, 0.15)
                        border.width: 1

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            anchors {
                                fill: parent
                                margins: Kirigami.Units.smallSpacing * 1.5
                            }

                            Kirigami.Icon {
                                source: modelData.status === "success" ? "dialog-ok" : "dialog-error"
                                color: modelData.status === "success" ? "#2ecc71" : "#e74c3c"
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.2
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                QQC2.Label {
                                    text: modelData.scheduleName || translate("Unnamed Run")
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "💬 " + (modelData.chatName || "Chat") + " · ⏱ " + modelData.timestamp
                                    font.pixelSize: 11
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                QQC2.Label {
                                    text: "\"" + (modelData.message || "").substring(0, 60) + ((modelData.message || "").length > 60 ? "…" : "") + "\""
                                    font.pixelSize: 10
                                    opacity: 0.5
                                    elide: Text.ElideRight
                                    font.italic: true
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

            }

        }

        // ── Editor view ────────────────────────────────────────────────────────
        QQC2.ScrollView {
            anchors.fill: parent
            visible: scheduleDialog.editingIndex !== -1
            clip: true

            ColumnLayout {
                width: parent.width - Kirigami.Units.gridUnit
                spacing: Kirigami.Units.largeSpacing

                // Target Chat Selection
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: translate("Target Chat:")
                        font.bold: true
                    }

                    QQC2.ComboBox {
                        id: chatComboBox
                        Layout.fillWidth: true
                        textRole: "name"
                        model: scheduleDialog.getChatsList()

                        Component.onCompleted: {
                            syncIndex();
                        }

                        Connections {
                            target: scheduleDialog
                            function onDraftChanged() {
                                chatComboBox.syncIndex();
                            }
                        }

                        function syncIndex() {
                            var targetId = scheduleDialog.draft.chatId || "";
                            var currentModel = chatComboBox.model;
                            if (currentModel && currentModel.length) {
                                for (var i = 0; i < currentModel.length; i++) {
                                    if (currentModel[i] && currentModel[i].id === targetId) {
                                        chatComboBox.currentIndex = i;
                                        return;
                                    }
                                }
                            }
                            chatComboBox.currentIndex = 0;
                        }

                        onActivated: {
                            var selected = model[index];
                            if (selected && selected.id) {
                                scheduleDialog.draft = Object.assign({}, scheduleDialog.draft, {
                                    "chatId": selected.id,
                                    "chatName": selected.name
                                });
                            }
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                // Message
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: translate("Message to send:")
                        font.bold: true
                    }

                    QQC2.Label {
                        text: translate("This message will be sent into the chat at the scheduled time, and the AI will reply.")
                        font.pixelSize: 11
                        opacity: 0.65
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    QQC2.TextArea {
                        id: dlgMessage

                        Layout.fillWidth: true
                        Layout.preferredHeight: 80
                        wrapMode: TextEdit.Wrap
                        text: scheduleDialog.draft.message || ""
                        placeholderText: translate("e.g. What should I focus on today?")
                        onTextChanged: scheduleDialog.draft = Object.assign({
                        }, scheduleDialog.draft, {
                            "message": text
                        })
                    }

                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                // Schedule builder
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: translate("Task Type:")
                        font.bold: true
                    }

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Button {
                            text: translate("Single Run")
                            highlighted: (scheduleDialog.draft.taskType || "single") === "single"
                            flat: (scheduleDialog.draft.taskType || "single") !== "single"
                            onClicked: scheduleDialog.draft = Object.assign({
                            }, scheduleDialog.draft, {
                                "taskType": "single"
                            })
                        }

                        QQC2.Button {
                            text: translate("Recurring (Repeatable)")
                            highlighted: (scheduleDialog.draft.taskType || "single") === "repeat"
                            flat: (scheduleDialog.draft.taskType || "single") !== "repeat"
                            onClicked: scheduleDialog.draft = Object.assign({
                            }, scheduleDialog.draft, {
                                "taskType": "repeat"
                            })
                        }

                    }

                }

                // ── Date and Time picker ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.mediumSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: (scheduleDialog.draft.taskType || "single") === "single" ? translate("Scheduled Date:") : translate("Start Date (Optional):")
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.ComboBox {
                                id: startMonthCombo

                                Layout.fillWidth: true
                                model: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"].map(function(x) { return translate(x); })
                                currentIndex: scheduleDialog.getStartMonth(scheduleDialog.draft.startDate)
                                onCurrentIndexChanged: {
                                    if (activeFocus)
                                        scheduleDialog.setStartDateField("month", currentIndex);

                                }
                            }

                            QQC2.SpinBox {
                                id: startDaySpin

                                from: 1
                                to: 31
                                value: scheduleDialog.getStartDay(scheduleDialog.draft.startDate)
                                onValueChanged: {
                                    if (activeFocus)
                                        scheduleDialog.setStartDateField("day", value);

                                }
                            }

                            QQC2.SpinBox {
                                id: startYearSpin

                                from: 2026
                                to: 2035
                                value: scheduleDialog.getStartYear(scheduleDialog.draft.startDate)
                                onValueChanged: {
                                    if (activeFocus)
                                        scheduleDialog.setStartDateField("year", value);

                                }
                            }

                        }

                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("Scheduled Time (Local):")
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.SpinBox {
                                id: startHourSpin

                                from: 0
                                to: 23
                                value: scheduleDialog.getStartHour(scheduleDialog.draft.startDate)
                                textFromValue: function(v) {
                                    return (v < 10 ? "0" : "") + v;
                                }
                                onValueChanged: {
                                    if (activeFocus)
                                        scheduleDialog.setStartDateField("hour", value);

                                }
                            }

                            QQC2.Label {
                                text: ":"
                            }

                            QQC2.SpinBox {
                                id: startMinSpin

                                from: 0
                                to: 59
                                value: scheduleDialog.getStartMin(scheduleDialog.draft.startDate)
                                textFromValue: function(v) {
                                    return (v < 10 ? "0" : "") + v;
                                }
                                onValueChanged: {
                                    if (activeFocus)
                                        scheduleDialog.setStartDateField("minute", value);

                                }
                            }

                        }

                    }

                }

                // ── Recurrence options ──
                ColumnLayout {
                    visible: (scheduleDialog.draft.taskType || "single") === "repeat"
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("Repeat Every:")
                            font.bold: true
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                model: [{
                                    "key": "minutes",
                                    "label": "Minutes"
                                }, {
                                    "key": "hours",
                                    "label": "Hours"
                                }, {
                                    "key": "days",
                                    "label": "Days"
                                }, {
                                    "key": "weeks",
                                    "label": "Weeks"
                                }, {
                                    "key": "months",
                                    "label": "Months"
                                }]

                                QQC2.Button {
                                    text: translate(modelData.label)
                                    flat: (scheduleDialog.draft.schedType || "days") !== modelData.key
                                    highlighted: (scheduleDialog.draft.schedType || "days") === modelData.key
                                    padding: Kirigami.Units.smallSpacing * 1.5
                                    font.pixelSize: 12
                                    onClicked: scheduleDialog.draft = Object.assign({
                                    }, scheduleDialog.draft, {
                                        "schedType": modelData.key
                                    })
                                }

                            }

                        }

                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("Repeat Every:")
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.SpinBox {
                                id: dlgEvery

                                from: 1
                                to: 999
                                value: scheduleDialog.draft.schedEvery || 1
                                onValueChanged: scheduleDialog.draft = Object.assign({
                                }, scheduleDialog.draft, {
                                    "schedEvery": value
                                })
                            }

                            QQC2.Label {
                                text: {
                                    var t = scheduleDialog.draft.schedType || "days", n = scheduleDialog.draft.schedEvery || 1;
                                    var labels = {
                                        "minutes": "minute",
                                        "hours": "hour",
                                        "days": "day",
                                        "weeks": "week",
                                        "months": "month"
                                    };
                                    var base = labels[t] || t;
                                    return n === 1 ? translate(base) : translate(base + "s");
                                }
                            }

                        }

                    }

                    ColumnLayout {
                        visible: ["days", "weeks", "months"].indexOf(scheduleDialog.draft.schedType || "days") >= 0
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("Scheduled Time (Local):")
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.SpinBox {
                                id: dlgHour

                                from: 0
                                to: 23
                                value: parseInt((scheduleDialog.draft.schedTime || "09:00").split(":")[0]) || 9
                                textFromValue: function(v) {
                                    return (v < 10 ? "0" : "") + v;
                                }
                                onValueChanged: {
                                    var m = parseInt((scheduleDialog.draft.schedTime || "09:00").split(":")[1]) || 0;
                                    scheduleDialog.draft = Object.assign({
                                    }, scheduleDialog.draft, {
                                        "schedTime": (value < 10 ? "0" : "") + value + ":" + (m < 10 ? "0" : "") + m
                                    });
                                }
                            }

                            QQC2.Label {
                                text: ":"
                            }

                            QQC2.SpinBox {
                                id: dlgMin

                                from: 0
                                to: 59
                                stepSize: 5
                                value: parseInt((scheduleDialog.draft.schedTime || "09:00").split(":")[1]) || 0
                                textFromValue: function(v) {
                                    return (v < 10 ? "0" : "") + v;
                                }
                                onValueChanged: {
                                    var h = parseInt((scheduleDialog.draft.schedTime || "09:00").split(":")[0]) || 9;
                                    scheduleDialog.draft = Object.assign({
                                    }, scheduleDialog.draft, {
                                        "schedTime": (h < 10 ? "0" : "") + h + ":" + (value < 10 ? "0" : "") + value
                                    });
                                }
                            }

                        }

                    }

                    ColumnLayout {
                        visible: (scheduleDialog.draft.schedType || "") === "weeks"
                        spacing: Kirigami.Units.smallSpacing
                        Layout.fillWidth: true

                        QQC2.Label {
                            text: translate("On these days:")
                            font.bold: true
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                model: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

                                Rectangle {
                                    property bool sel: {
                                        var ds = scheduleDialog.draft.schedDays || [1];
                                        return ds.indexOf(index) >= 0;
                                    }

                                    width: 44
                                    height: 28
                                    radius: 5
                                    color: sel ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                    border.color: sel ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                                    border.width: 1

                                    QQC2.Label {
                                        anchors.centerIn: parent
                                        text: translate(modelData)
                                        font.pixelSize: 11
                                        font.bold: sel
                                        color: sel ? "white" : Kirigami.Theme.textColor
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            var ds = (scheduleDialog.draft.schedDays || [1]).slice();
                                            var pos = ds.indexOf(index);
                                            if (pos >= 0) {
                                                if (ds.length > 1)
                                                    ds.splice(pos, 1);

                                            } else {
                                                ds.push(index);
                                                ds.sort();
                                            }
                                            scheduleDialog.draft = Object.assign({
                                            }, scheduleDialog.draft, {
                                                "schedDays": ds
                                            });
                                        }
                                    }

                                }

                            }

                        }

                    }

                    ColumnLayout {
                        visible: (scheduleDialog.draft.schedType || "") === "months"
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("On Day of Month:")
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.SpinBox {
                                from: 1
                                to: 28
                                value: scheduleDialog.draft.schedDayOfMonth || 1
                                onValueChanged: scheduleDialog.draft = Object.assign({
                                }, scheduleDialog.draft, {
                                    "schedDayOfMonth": value
                                })
                            }

                            QQC2.Label {
                                text: translate("of the month")
                                opacity: 0.7
                            }

                        }

                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: translate("Execution Limit:")
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.mediumSpacing

                            QQC2.CheckBox {
                                id: limitCheckbox

                                text: translate("Limit number of runs")
                                checked: !!scheduleDialog.draft.limitEnabled
                                onCheckedChanged: scheduleDialog.draft = Object.assign({
                                }, scheduleDialog.draft, {
                                    "limitEnabled": checked
                                })
                            }

                            QQC2.SpinBox {
                                id: limitSpin

                                visible: limitCheckbox.checked
                                from: 1
                                to: 9999
                                value: scheduleDialog.draft.limitCount || 5
                                onValueChanged: scheduleDialog.draft = Object.assign({
                                }, scheduleDialog.draft, {
                                    "limitCount": value
                                })
                            }

                            QQC2.Label {
                                visible: limitCheckbox.checked
                                text: translate("times")
                                opacity: 0.7
                            }

                        }

                    }

                }

                // Summary chip
                Rectangle {
                    Layout.fillWidth: true
                    height: dlgSummary.implicitHeight + Kirigami.Units.gridUnit
                    radius: 6
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3)
                    border.width: 1

                    QQC2.Label {
                        id: dlgSummary

                        text: "📅 " + scheduleDialog.humanText(scheduleDialog.draft)
                        font.bold: true
                        wrapMode: Text.Wrap
                        color: Kirigami.Theme.highlightColor

                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                            margins: Kirigami.Units.gridUnit * 0.6
                        }

                    }

                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                // Label (always on top)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: translate("Label (optional):")
                        font.bold: true
                    }

                    QQC2.TextField {
                        id: dlgName

                        Layout.fillWidth: true
                        text: scheduleDialog.draft.name || ""
                        placeholderText: translate("Leave blank to auto-name")
                        onTextChanged: scheduleDialog.draft = Object.assign({
                        }, scheduleDialog.draft, {
                            "name": text
                        })
                    }

                }

                RowLayout {
                    QQC2.Switch {
                        id: dlgNotify

                        checked: scheduleDialog.draft.notify !== false
                        onCheckedChanged: scheduleDialog.draft = Object.assign({
                        }, scheduleDialog.draft, {
                            "notify": checked
                        })
                    }

                    QQC2.Label {
                        text: dlgNotify.checked ? translate("Show a notification when the AI replies") : translate("Silent — no notification")
                        opacity: 0.75
                        wrapMode: Text.Wrap
                    }

                }

                // Validation error
                QQC2.Label {
                    id: dlgCronError
                    Layout.fillWidth: true
                    visible: text !== ""
                    color: "#e74c3c"
                    wrapMode: Text.Wrap
                    font.bold: true
                }

                // Buttons
                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    QQC2.Button {
                        text: translate("Cancel")
                        onClicked: {
                            dlgCronError.text = "";
                            scheduleDialog.editingIndex = -1;
                        }
                    }

                    QQC2.Button {
                        text: scheduleDialog.editingIndex === -2 ? translate("Create Schedule") : translate("Save Changes")
                        highlighted: true
                        enabled: dlgMessage.text.trim() !== ""
                        onClicked: {
                            var d = Object.assign({
                            }, scheduleDialog.draft);
                            d.cron = scheduleDialog.buildCron(d);
                            if (d.cron && d.cron.trim() !== "") {
                                var cv = scheduleDialog.validateCron(d.cron);
                                if (!cv.valid) {
                                    dlgCronError.text = cv.message;
                                    return;
                                }
                            }
                            dlgCronError.text = "";
                            d.humanReadable = scheduleDialog.humanText(d);
                            if (!d.name || d.name.trim() === "")
                                d.name = d.humanReadable;

                            var copy = page.schedulerList.slice();
                            if (scheduleDialog.editingIndex === -2)
                                copy.push(d);
                            else
                                copy[scheduleDialog.editingIndex] = d;
                            page.schedulerList = copy;
                            page.schedSaveSchedules(copy);
                            scheduleDialog.editingIndex = -1;
                        }
                    }

                }

            }

        }

    }
