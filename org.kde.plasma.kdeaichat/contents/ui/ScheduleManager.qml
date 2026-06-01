import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// ScheduleManager.qml — Redesigned schedule list + editor for KDE AI Chat
// Schedules are per-chat. Each schedule injects a message into its linked chat at a set time.

Item {
    id: scheduleManager

    property var bridge: null
    property var scheduleList: []
    property int editingIndex: -1
    property var editingDraft: ({})
    property string currentChatId: ""
    property string currentChatName: "this chat"

    signal schedulesChanged(var newList)

    // ── UUID helper ────────────────────────────────────────────────────────────
    function makeUuid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0
            return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
        })
    }

    // ── Cron builder → expression ──────────────────────────────────────────────
    // draft fields used by builder:
    //   schedType: "minutes" | "hours" | "days" | "weeks" | "months" | "custom"
    //   schedEvery: number (X)
    //   schedTime: "HH:MM" string (for daily/weekly/monthly)
    //   schedDays: array of 0-6 (0=Sun) for weekly
    //   schedDayOfMonth: 1-28 for monthly

    function buildCron(draft) {
        var t = draft.schedType || "days"
        var n = parseInt(draft.schedEvery) || 1
        var timeParts = (draft.schedTime || "09:00").split(":")
        var hr = parseInt(timeParts[0]) || 9
        var mn = parseInt(timeParts[1]) || 0

        if (t === "minutes") return "*/" + n + " * * * *"
        if (t === "hours")   return "0 */" + n + " * * *"
        if (t === "days" && n === 1) return mn + " " + hr + " * * *"
        if (t === "days")    return mn + " " + hr + " */" + n + " * *"
        if (t === "weeks") {
            var days = (draft.schedDays && draft.schedDays.length > 0)
                ? draft.schedDays.slice().sort().join(",")
                : "1"
            if (n === 1) return mn + " " + hr + " * * " + days
            // Every N weeks: use step on weeks approximated with day-of-month steps
            return mn + " " + hr + " * * " + days
        }
        if (t === "months" && n === 1) {
            var dom = draft.schedDayOfMonth || 1
            return mn + " " + hr + " " + dom + " * *"
        }
        if (t === "months") {
            var dom2 = draft.schedDayOfMonth || 1
            return mn + " " + hr + " " + dom2 + " */" + n + " *"
        }
        return draft.cron || "0 9 * * *"
    }

    // ── Cron → human readable ─────────────────────────────────────────────────
    function humanCron(expr, draft) {
        if (draft && draft.schedType) {
            var t = draft.schedType
            var n = parseInt(draft.schedEvery) || 1
            var time = draft.schedTime || "09:00"
            var tp = time.split(":")
            var hr = parseInt(tp[0]) || 9
            var mn = parseInt(tp[1]) || 0
            var ampm = hr >= 12 ? "PM" : "AM"
            var h12 = hr % 12 || 12
            var mStr = mn < 10 ? "0" + mn : "" + mn
            var timeStr = h12 + ":" + mStr + " " + ampm

            if (t === "minutes") return "Every " + (n === 1 ? "minute" : n + " minutes")
            if (t === "hours")   return "Every " + (n === 1 ? "hour" : n + " hours")
            if (t === "days")    return "Every " + (n === 1 ? "day" : n + " days") + " at " + timeStr
            if (t === "weeks") {
                var dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
                var days = draft.schedDays && draft.schedDays.length > 0
                    ? draft.schedDays.map(function(d){ return dayNames[d] }).join(", ")
                    : "Mon"
                return "Every " + (n === 1 ? "week" : n + " weeks") + " on " + days + " at " + timeStr
            }
            if (t === "months") {
                var dom = draft.schedDayOfMonth || 1
                var suffix = dom === 1 ? "st" : dom === 2 ? "nd" : dom === 3 ? "rd" : "th"
                return "Every " + (n === 1 ? "month" : n + " months") + " on the " + dom + suffix + " at " + timeStr
            }
        }

        if (!expr) return "No schedule set"
        var parts = expr.trim().split(/\s+/)
        if (parts.length !== 5) return expr
        var min = parts[0], hr2 = parts[1]
        if (min.startsWith("*/")) return "Every " + min.slice(2) + " minutes"
        if (hr2.startsWith("*/")) return "Every " + hr2.slice(2) + " hours"
        if (min === "0" && hr2 !== "*") {
            var h = parseInt(hr2)
            var ap = h >= 12 ? "PM" : "AM"
            var h1 = h % 12 || 12
            var dayMap = {"*":"every day","1-5":"weekdays","0,6":"weekends","6,0":"weekends","1":"Mondays"}
            return "Daily at " + h1 + ":00 " + ap + (dayMap[parts[4]] ? " (" + dayMap[parts[4]] + ")" : "")
        }
        return expr
    }

    function loadFromFile() { if (bridge) bridge.loadSchedules() }
    function saveToFile() {
        if (bridge) bridge.saveSchedules(scheduleList)
        schedulesChanged(scheduleList)
    }

    function startNew(chatId, chatName) {
        currentChatId = chatId || ""
        currentChatName = chatName || "this chat"
        editingDraft = {
            id: makeUuid(),
            name: "",
            enabled: true,
            chatId: chatId || "",
            chatName: chatName || "",
            message: "",
            cron: "0 9 * * *",
            schedType: "days",
            schedEvery: 1,
            schedTime: "09:00",
            schedDays: [1],
            schedDayOfMonth: 1,
            notify: true,
            createdAt: new Date().toISOString(),
            lastRunAt: "",
            nextRunAt: ""
        }
        editingIndex = -2
    }

    function startEdit(index) {
        var s = scheduleList[index]
        editingDraft = JSON.parse(JSON.stringify(s))
        // Ensure builder fields exist
        if (!editingDraft.schedType) editingDraft.schedType = "days"
        if (!editingDraft.schedEvery) editingDraft.schedEvery = 1
        if (!editingDraft.schedTime) editingDraft.schedTime = "09:00"
        if (!editingDraft.schedDays) editingDraft.schedDays = [1]
        if (!editingDraft.schedDayOfMonth) editingDraft.schedDayOfMonth = 1
        editingIndex = index
    }

    function cancelEdit() { editingIndex = -1; editingDraft = {} }

    function saveEdit() {
        // Build cron from builder state
        var d = Object.assign({}, editingDraft)
        d.cron = buildCron(d)
        d.humanReadable = humanCron(d.cron, d)
        if (!d.name || d.name.trim() === "") d.name = d.humanReadable

        var copy = scheduleList.slice()
        if (editingIndex === -2) copy.push(d)
        else if (editingIndex >= 0) copy[editingIndex] = d
        scheduleList = copy
        editingIndex = -1
        editingDraft = {}
        saveToFile()
    }

    function deleteSchedule(index) {
        var copy = scheduleList.slice()
        copy.splice(index, 1)
        scheduleList = copy
        if (editingIndex === index) cancelEdit()
        saveToFile()
    }

    function toggleEnabled(index) {
        var copy = scheduleList.slice()
        var s = JSON.parse(JSON.stringify(copy[index]))
        s.enabled = !s.enabled
        copy[index] = s
        scheduleList = copy
        saveToFile()
    }

    // ── Main Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        // ── Header ─────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 3
                text: "Scheduled Messages"
                Layout.fillWidth: true
            }

            QQC2.Button {
                text: "New Schedule"
                icon.name: "list-add"
                highlighted: true
                visible: editingIndex === -1
                onClicked: startNew(currentChatId, currentChatName)
            }
        }

        // ── How it works info box ──────────────────────────────────────────────
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: scheduleList.length === 0 && editingIndex === -1
            type: Kirigami.MessageType.Information
            text: "<b>How scheduled messages work:</b> At the set time, your message is automatically " +
                  "sent into the linked chat and the AI responds — just like you typed it yourself. " +
                  "Use <b>/schedule</b> in any chat to create one instantly."
        }

        // ── Schedule list ──────────────────────────────────────────────────────
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(scheduleList.length * 80 + 8, 360)
            visible: scheduleList.length > 0 && editingIndex === -1
            clip: true

            ListView {
                id: scheduleListView
                model: scheduleList
                spacing: Kirigami.Units.smallSpacing

                delegate: Rectangle {
                    width: scheduleListView.width
                    height: 74
                    radius: Kirigami.Units.smallSpacing
                    color: modelData.enabled
                           ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                     Kirigami.Theme.highlightColor.g,
                                     Kirigami.Theme.highlightColor.b, 0.06)
                           : Qt.rgba(Kirigami.Theme.textColor.r,
                                     Kirigami.Theme.textColor.g,
                                     Kirigami.Theme.textColor.b, 0.03)
                    border.color: modelData.enabled
                                  ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                            Kirigami.Theme.highlightColor.g,
                                            Kirigami.Theme.highlightColor.b, 0.22)
                                  : Qt.rgba(Kirigami.Theme.textColor.r,
                                            Kirigami.Theme.textColor.g,
                                            Kirigami.Theme.textColor.b, 0.10)
                    border.width: 1
                    opacity: modelData.enabled ? 1.0 : 0.55

                    RowLayout {
                        anchors { fill: parent; margins: Kirigami.Units.smallSpacing * 1.5 }
                        spacing: Kirigami.Units.smallSpacing

                        // Enabled toggle
                        QQC2.Switch {
                            checked: modelData.enabled
                            onToggled: scheduleManager.toggleEnabled(index)
                            QQC2.ToolTip.text: checked ? "Pause this schedule" : "Activate this schedule"
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 500
                        }

                        // Info column
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            QQC2.Label {
                                text: modelData.name || scheduleManager.humanCron(modelData.cron, modelData)
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                text: "⏱ " + scheduleManager.humanCron(modelData.cron, modelData) +
                                      (modelData.chatName ? " · 💬 " + modelData.chatName : "")
                                font.pixelSize: 11
                                opacity: 0.7
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                text: "\"" + (modelData.message || "").substring(0, 60) +
                                      ((modelData.message || "").length > 60 ? "…" : "") + "\""
                                font.pixelSize: 10
                                opacity: 0.50
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                font.italic: true
                            }
                        }

                        // Action buttons
                        QQC2.ToolButton {
                            icon.name: "document-edit"
                            QQC2.ToolTip.text: "Edit"
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 500
                            onClicked: scheduleManager.startEdit(index)
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-delete"
                            QQC2.ToolTip.text: "Remove"
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: 500
                            onClicked: deleteConfirmDialog.openFor(index)
                        }
                    }
                }
            }
        }

        // ── Editor panel ───────────────────────────────────────────────────────
        Rectangle {
            visible: editingIndex !== -1
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, 0.5)
            border.color: Kirigami.Theme.highlightColor
            border.width: 1
            radius: Kirigami.Units.smallSpacing

            QQC2.ScrollView {
                anchors { fill: parent; margins: Kirigami.Units.largeSpacing }
                clip: true

                ColumnLayout {
                    width: parent.parent.width - Kirigami.Units.largeSpacing * 2
                    spacing: Kirigami.Units.largeSpacing

                    // Title
                    Kirigami.Heading {
                        level: 4
                        text: editingIndex === -2 ? "New Scheduled Message" : "Edit Scheduled Message"
                    }

                    // ── Message to send ────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: "Message to send:"
                            font.bold: true
                        }
                        QQC2.Label {
                            text: "This message will be sent into the chat at the scheduled time, and the AI will reply."
                            font.pixelSize: 11
                            opacity: 0.65
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        QQC2.TextArea {
                            id: editorMessage
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            text: editingDraft.message || ""
                            placeholderText: "e.g. Summarize what I should focus on today"
                            wrapMode: TextEdit.Wrap
                            onTextChanged: editingDraft = Object.assign({}, editingDraft, {message: text})
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    // ── Schedule builder ───────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: "When to send:"
                            font.bold: true
                        }

                        // Schedule type selector
                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                model: [
                                    {key: "minutes", label: "Every X minutes"},
                                    {key: "hours",   label: "Every X hours"},
                                    {key: "days",    label: "Every X days"},
                                    {key: "weeks",   label: "Every X weeks"},
                                    {key: "months",  label: "Every X months"},
                                ]
                                QQC2.Button {
                                    text: modelData.label
                                    flat: (editingDraft.schedType || "days") !== modelData.key
                                    highlighted: (editingDraft.schedType || "days") === modelData.key
                                    padding: Kirigami.Units.smallSpacing * 1.5
                                    font.pixelSize: 12
                                    onClicked: {
                                        editingDraft = Object.assign({}, editingDraft, {schedType: modelData.key})
                                    }
                                }
                            }
                        }

                        // Every N
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.Label { text: "Every" }

                            QQC2.SpinBox {
                                id: everySpinBox
                                from: 1; to: 999
                                value: editingDraft.schedEvery || 1
                                onValueChanged: editingDraft = Object.assign({}, editingDraft, {schedEvery: value})
                            }

                            QQC2.Label {
                                text: {
                                    var t = editingDraft.schedType || "days"
                                    var n = editingDraft.schedEvery || 1
                                    if (t === "minutes") return n === 1 ? "minute" : "minutes"
                                    if (t === "hours")   return n === 1 ? "hour" : "hours"
                                    if (t === "days")    return n === 1 ? "day" : "days"
                                    if (t === "weeks")   return n === 1 ? "week" : "weeks"
                                    if (t === "months")  return n === 1 ? "month" : "months"
                                    return ""
                                }
                            }
                        }

                        // Time picker (for days/weeks/months)
                        RowLayout {
                            visible: ["days","weeks","months"].indexOf(editingDraft.schedType || "days") >= 0
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.Label { text: "At time:" }

                            QQC2.SpinBox {
                                id: hourSpinBox
                                from: 0; to: 23
                                value: parseInt((editingDraft.schedTime || "09:00").split(":")[0]) || 9
                                textFromValue: function(v) { return (v < 10 ? "0" : "") + v }
                                onValueChanged: {
                                    var m = parseInt((editingDraft.schedTime || "09:00").split(":")[1]) || 0
                                    editingDraft = Object.assign({}, editingDraft,
                                        {schedTime: (value < 10 ? "0":"") + value + ":" + (m < 10 ? "0":"") + m})
                                }
                            }

                            QQC2.Label { text: ":" }

                            QQC2.SpinBox {
                                id: minSpinBox
                                from: 0; to: 59; stepSize: 5
                                value: parseInt((editingDraft.schedTime || "09:00").split(":")[1]) || 0
                                textFromValue: function(v) { return (v < 10 ? "0" : "") + v }
                                onValueChanged: {
                                    var h = parseInt((editingDraft.schedTime || "09:00").split(":")[0]) || 9
                                    editingDraft = Object.assign({}, editingDraft,
                                        {schedTime: (h < 10 ? "0":"") + h + ":" + (value < 10 ? "0":"") + value})
                                }
                            }
                        }

                        // Day of week selector (for weeks)
                        ColumnLayout {
                            visible: (editingDraft.schedType || "") === "weeks"
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.Label { text: "On these days:" }

                            Flow {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Repeater {
                                    model: ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

                                    Rectangle {
                                        width: 44; height: 28
                                        radius: 5
                                        property bool sel: {
                                            var days = editingDraft.schedDays || [1]
                                            return days.indexOf(index) >= 0
                                        }
                                        color: sel
                                               ? Kirigami.Theme.highlightColor
                                               : Qt.rgba(Kirigami.Theme.textColor.r,
                                                         Kirigami.Theme.textColor.g,
                                                         Kirigami.Theme.textColor.b, 0.08)
                                        border.color: sel
                                                      ? Kirigami.Theme.highlightColor
                                                      : Qt.rgba(Kirigami.Theme.textColor.r,
                                                                Kirigami.Theme.textColor.g,
                                                                Kirigami.Theme.textColor.b, 0.18)
                                        border.width: 1

                                        QQC2.Label {
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.pixelSize: 11
                                            font.bold: sel
                                            color: sel ? "white" : Kirigami.Theme.textColor
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                var days = (editingDraft.schedDays || [1]).slice()
                                                var pos = days.indexOf(index)
                                                if (pos >= 0) {
                                                    if (days.length > 1) days.splice(pos, 1)
                                                } else {
                                                    days.push(index)
                                                    days.sort()
                                                }
                                                editingDraft = Object.assign({}, editingDraft, {schedDays: days})
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Day of month selector (for months)
                        RowLayout {
                            visible: (editingDraft.schedType || "") === "months"
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.Label { text: "On day:" }

                            QQC2.SpinBox {
                                from: 1; to: 28
                                value: editingDraft.schedDayOfMonth || 1
                                onValueChanged: editingDraft = Object.assign({}, editingDraft, {schedDayOfMonth: value})
                            }

                            QQC2.Label { text: "of the month"; opacity: 0.7 }
                        }

                        // Human readable summary
                        Rectangle {
                            Layout.fillWidth: true
                            height: cronSummaryLabel.implicitHeight + Kirigami.Units.gridUnit
                            radius: 6
                            color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                           Kirigami.Theme.highlightColor.g,
                                           Kirigami.Theme.highlightColor.b, 0.10)
                            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                  Kirigami.Theme.highlightColor.g,
                                                  Kirigami.Theme.highlightColor.b, 0.30)
                            border.width: 1

                            QQC2.Label {
                                id: cronSummaryLabel
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left; right: parent.right
                                    margins: Kirigami.Units.gridUnit * 0.6
                                }
                                text: "📅 " + scheduleManager.humanCron(
                                    scheduleManager.buildCron(editingDraft), editingDraft)
                                font.bold: true
                                wrapMode: Text.Wrap
                                color: Kirigami.Theme.highlightColor
                            }
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    // ── Optional name ──────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: "Label (optional):"
                            font.bold: true
                        }
                        QQC2.TextField {
                            id: editorName
                            Layout.fillWidth: true
                            text: editingDraft.name || ""
                            placeholderText: "Leave blank to auto-name from schedule"
                            onTextChanged: editingDraft = Object.assign({}, editingDraft, {name: text})
                        }
                    }

                    // ── Notify toggle ──────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Switch {
                            id: editorNotify
                            checked: editingDraft.notify !== false
                            onCheckedChanged: editingDraft = Object.assign({}, editingDraft, {notify: checked})
                        }
                        QQC2.Label {
                            text: editorNotify.checked
                                  ? "Show a desktop notification when the AI replies"
                                  : "Silent — no notification"
                            opacity: 0.75
                            wrapMode: Text.Wrap
                        }
                    }

                    // ── Action buttons ─────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        QQC2.Button {
                            text: "Cancel"
                            onClicked: scheduleManager.cancelEdit()
                        }
                        QQC2.Button {
                            text: editingIndex === -2 ? "Create Schedule" : "Save Changes"
                            highlighted: true
                            enabled: editorMessage.text.trim() !== ""
                            onClicked: scheduleManager.saveEdit()
                        }
                    }
                }
            }
        }
    }

    // ── Delete confirmation ────────────────────────────────────────────────────
    QQC2.Dialog {
        id: deleteConfirmDialog
        title: "Remove Schedule"
        modal: true
        standardButtons: QQC2.Dialog.Cancel | QQC2.Dialog.Ok
        property int targetIndex: -1
        function openFor(index) { targetIndex = index; open() }
        QQC2.Label {
            text: deleteConfirmDialog.targetIndex >= 0 && scheduleManager.scheduleList.length > deleteConfirmDialog.targetIndex
                  ? "Remove \"" + (scheduleManager.scheduleList[deleteConfirmDialog.targetIndex].name ||
                                   scheduleManager.humanCron(scheduleManager.scheduleList[deleteConfirmDialog.targetIndex].cron,
                                                             scheduleManager.scheduleList[deleteConfirmDialog.targetIndex])) + "\"?"
                  : "Remove this schedule?"
            wrapMode: Text.Wrap
        }
        onAccepted: { if (targetIndex >= 0) scheduleManager.deleteSchedule(targetIndex) }
    }
}
