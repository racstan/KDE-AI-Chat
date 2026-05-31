import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// ScheduleManager.qml — Schedule list + editor for KDE AI Chat
// Embedded inside ConfigGeneral.qml as a Loader target.
// Communicates upward via schedulerBridge object passed as `bridge`.

Item {
    id: scheduleManager

    // Bridge object passed from ConfigGeneral with helper functions
    property var bridge: null
    // List of schedule objects (JS array)
    property var scheduleList: []
    // Index of the schedule being edited (-1 = none, -2 = new)
    property int editingIndex: -1
    // Draft object being edited
    property var editingDraft: ({})
    property bool daemonRunning: false
    property string daemonStatus: "Checking..."

    signal schedulesChanged(var newList)

    function loadFromFile() {
        if (bridge) bridge.loadSchedules()
    }

    function saveToFile() {
        if (bridge) bridge.saveSchedules(scheduleList)
        schedulesChanged(scheduleList)
    }

    function makeUuid() {
        // Simple UUID v4 using Math.random
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0
            return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
        })
    }

    function startNew() {
        editingDraft = {
            id: makeUuid(),
            name: "New Schedule",
            enabled: true,
            cron: "0 9 * * 1-5",
            prompt: "",
            systemPrompt: "",
            provider: "",
            baseUrl: "",
            model: "",
            apiKey: "",
            maxTokens: 1000,
            notify: true,
            notifyTitle: "",
            saveResults: true,
            keepResultDays: 30,
            createdAt: new Date().toISOString(),
            lastRunAt: "",
            lastRunStatus: "",
            nextRunAt: ""
        }
        editingIndex = -2
    }

    function startEdit(index) {
        var s = scheduleList[index]
        editingDraft = JSON.parse(JSON.stringify(s))
        editingIndex = index
    }

    function cancelEdit() {
        editingIndex = -1
        editingDraft = {}
    }

    function saveEdit() {
        var copy = scheduleList.slice()
        if (editingIndex === -2) {
            copy.push(editingDraft)
        } else if (editingIndex >= 0) {
            copy[editingIndex] = editingDraft
        }
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

    function triggerNow(index) {
        var copy = scheduleList.slice()
        var s = JSON.parse(JSON.stringify(copy[index]))
        s.triggerNow = true
        copy[index] = s
        scheduleList = copy
        saveToFile()
        if (bridge) bridge.reloadDaemon()
    }

    function humanCron(expr) {
        if (!expr) return "No schedule"
        var parts = expr.trim().split(/\s+/)
        if (parts.length !== 5) return expr
        var min = parts[0], hr = parts[1], dom = parts[2], mon = parts[3], dow = parts[4]
        if (min === "0" && hr !== "*" && dom === "*" && mon === "*") {
            var h = parseInt(hr)
            var ampm = h >= 12 ? "PM" : "AM"
            var h12 = h % 12 || 12
            var dayStr = dow === "*" ? "every day" :
                         dow === "1-5" ? "weekdays" :
                         dow === "6,0" || dow === "0,6" ? "weekends" : "on selected days"
            return "Daily at " + h12 + ":00 " + ampm + " " + dayStr
        }
        if (hr.startsWith("*/")) return "Every " + hr.slice(2) + " hours"
        return expr
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ── Header row ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 3
                text: "Scheduled Tasks"
                Layout.fillWidth: true
            }

            // Daemon status badge
            Rectangle {
                width: statusDot.implicitWidth + statusLabel.implicitWidth + Kirigami.Units.smallSpacing * 3
                height: Kirigami.Units.gridUnit * 1.4
                radius: height / 2
                color: daemonRunning
                       ? Qt.rgba(0.13, 0.69, 0.30, 0.18)
                       : Qt.rgba(0.85, 0.17, 0.17, 0.14)
                border.color: daemonRunning
                              ? Qt.rgba(0.13, 0.69, 0.30, 0.55)
                              : Qt.rgba(0.85, 0.17, 0.17, 0.40)
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing / 2

                    Rectangle {
                        id: statusDot
                        width: 8; height: 8; radius: 4
                        color: daemonRunning ? "#22b14c" : "#cc2222"
                    }
                    QQC2.Label {
                        id: statusLabel
                        text: daemonRunning ? "Daemon running" : "Daemon stopped"
                        font.pixelSize: 11
                        color: daemonRunning
                               ? Qt.rgba(0.05, 0.55, 0.20, 1.0)
                               : Qt.rgba(0.75, 0.10, 0.10, 1.0)
                    }
                }
            }

            QQC2.Button {
                text: daemonRunning ? "Restart Daemon" : "Start Daemon"
                icon.name: daemonRunning ? "view-refresh" : "media-playback-start"
                onClicked: {
                    if (bridge) bridge.startDaemon()
                    daemonStatusPollTimer.restart()
                }
            }

            QQC2.Button {
                text: "+ New Schedule"
                icon.name: "list-add"
                highlighted: true
                onClicked: startNew()
            }
        }

        // Daemon status timer
        Timer {
            id: daemonStatusPollTimer
            interval: 2000
            repeat: true
            running: true
            onTriggered: {
                if (bridge) {
                    daemonRunning = bridge.isDaemonRunning()
                    daemonStatus = daemonRunning ? "Running" : "Stopped"
                }
            }
        }

        // ── Info banner ────────────────────────────────────────────────────
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: scheduleList.length === 0 && editingIndex === -1
            type: Kirigami.MessageType.Information
            text: "No schedules yet. Click <b>+ New Schedule</b> to create your first automated AI task. " +
                  "Schedules run independently via a background daemon — even when the widget is closed."
        }

        // ── Schedule list ──────────────────────────────────────────────────
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(scheduleList.length * 72 + 8, 320)
            visible: scheduleList.length > 0 && editingIndex === -1
            clip: true

            ListView {
                id: scheduleListView
                model: scheduleList
                spacing: Kirigami.Units.smallSpacing

                delegate: Rectangle {
                    width: scheduleListView.width
                    height: 66
                    radius: Kirigami.Units.smallSpacing
                    color: modelData.enabled
                           ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                     Kirigami.Theme.highlightColor.g,
                                     Kirigami.Theme.highlightColor.b, 0.06)
                           : Qt.rgba(Kirigami.Theme.textColor.r,
                                     Kirigami.Theme.textColor.g,
                                     Kirigami.Theme.textColor.b, 0.04)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                          Kirigami.Theme.textColor.g,
                                          Kirigami.Theme.textColor.b, 0.12)
                    border.width: 1
                    opacity: modelData.enabled ? 1.0 : 0.55

                    RowLayout {
                        anchors { fill: parent; margins: Kirigami.Units.smallSpacing * 1.5 }
                        spacing: Kirigami.Units.smallSpacing

                        // Enabled toggle
                        QQC2.Switch {
                            checked: modelData.enabled
                            onToggled: scheduleManager.toggleEnabled(index)
                            ToolTip.text: checked ? "Disable this schedule" : "Enable this schedule"
                            ToolTip.visible: hovered
                            ToolTip.delay: 600
                        }

                        // Info column
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            QQC2.Label {
                                text: modelData.name || "Unnamed"
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                text: scheduleManager.humanCron(modelData.cron) +
                                      " · " + (modelData.provider || "provider") +
                                      " · " + (modelData.model || "model")
                                font.pixelSize: 11
                                opacity: 0.7
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            QQC2.Label {
                                visible: !!modelData.lastRunAt
                                text: "Last run: " + (modelData.lastRunStatus || "—") +
                                      " · " + (modelData.lastRunAt ? new Date(modelData.lastRunAt).toLocaleString() : "Never")
                                font.pixelSize: 10
                                opacity: 0.55
                                color: modelData.lastRunStatus === "error"
                                       ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Action buttons
                        QQC2.ToolButton {
                            icon.name: "media-playback-start"
                            ToolTip.text: "Run now (triggers within 30s)"
                            ToolTip.visible: hovered
                            ToolTip.delay: 600
                            onClicked: scheduleManager.triggerNow(index)
                        }
                        QQC2.ToolButton {
                            icon.name: "document-edit"
                            ToolTip.text: "Edit schedule"
                            ToolTip.visible: hovered
                            ToolTip.delay: 600
                            onClicked: scheduleManager.startEdit(index)
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-delete"
                            ToolTip.text: "Delete schedule"
                            ToolTip.visible: hovered
                            ToolTip.delay: 600
                            onClicked: deleteConfirmDialog.openFor(index)
                        }
                    }
                }
            }
        }

        // ── Editor panel ───────────────────────────────────────────────────
        Rectangle {
            visible: editingIndex !== -1
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, 0.6)
            border.color: Kirigami.Theme.highlightColor
            border.width: 1
            radius: Kirigami.Units.smallSpacing

            QQC2.ScrollView {
                anchors { fill: parent; margins: Kirigami.Units.largeSpacing }
                clip: true

                ColumnLayout {
                    width: parent.parent.width - Kirigami.Units.largeSpacing * 2
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        level: 4
                        text: editingIndex === -2 ? "New Schedule" : "Edit Schedule"
                    }

                    // Name
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Name:"; Layout.preferredWidth: 120 }
                        QQC2.TextField {
                            id: editorName
                            Layout.fillWidth: true
                            text: editingDraft.name || ""
                            placeholderText: "Daily standup summary"
                            onTextChanged: editingDraft = Object.assign({}, editingDraft, {name: text})
                        }
                    }

                    // Enabled toggle
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Enabled:"; Layout.preferredWidth: 120 }
                        QQC2.Switch {
                            id: editorEnabled
                            checked: editingDraft.enabled !== false
                            onCheckedChanged: editingDraft = Object.assign({}, editingDraft, {enabled: checked})
                        }
                        QQC2.Label {
                            text: editorEnabled.checked ? "Schedule is active" : "Schedule is paused"
                            opacity: 0.6; font.pixelSize: 11
                        }
                    }

                    // Cron expression
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Schedule (cron):"; Layout.preferredWidth: 120 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            QQC2.TextField {
                                id: editorCron
                                Layout.fillWidth: true
                                text: editingDraft.cron || "0 9 * * 1-5"
                                placeholderText: "0 9 * * 1-5"
                                font.family: "monospace"
                                onTextChanged: editingDraft = Object.assign({}, editingDraft, {cron: text})
                            }
                            QQC2.Label {
                                text: "→ " + scheduleManager.humanCron(editorCron.text)
                                font.pixelSize: 11; opacity: 0.65
                            }
                            QQC2.Label {
                                text: "Format: minute hour day month weekday  (0=Sun, 1=Mon … 5=Fri, 6=Sat)"
                                font.pixelSize: 10; opacity: 0.50; wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Quick cron presets
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Quick presets:"; Layout.preferredWidth: 120 }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Repeater {
                                model: [
                                    {label: "Every hour",    cron: "0 * * * *"},
                                    {label: "Daily 9am",     cron: "0 9 * * *"},
                                    {label: "Weekdays 9am",  cron: "0 9 * * 1-5"},
                                    {label: "Daily 8pm",     cron: "0 20 * * *"},
                                    {label: "Weekly Mon",    cron: "0 9 * * 1"},
                                    {label: "Monthly 1st",   cron: "0 9 1 * *"},
                                ]
                                QQC2.Button {
                                    text: modelData.label
                                    flat: true
                                    font.pixelSize: 11
                                    padding: 4
                                    onClicked: {
                                        editorCron.text = modelData.cron
                                        editingDraft = Object.assign({}, editingDraft, {cron: modelData.cron})
                                    }
                                }
                            }
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    // Provider
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Provider:"; Layout.preferredWidth: 120 }
                        QQC2.ComboBox {
                            id: editorProvider
                            Layout.preferredWidth: 180
                            model: [
                                "openai", "anthropic", "groq", "google", "deepseek",
                                "mistral", "openrouter", "xai", "nvidia", "fireworks",
                                "minimax", "cloudflare", "huggingface", "ollama",
                                "lmstudio", "local", "litellm", "qwen", "moonshot",
                                "mimo", "maritaca"
                            ]
                            currentIndex: {
                                var idx = model.indexOf(editingDraft.provider || "openai")
                                return idx >= 0 ? idx : 0
                            }
                            onCurrentValueChanged: {
                                editingDraft = Object.assign({}, editingDraft, {
                                    provider: currentValue,
                                    baseUrl: defaultBaseUrl(currentValue)
                                })
                                editorBaseUrl.text = editingDraft.baseUrl
                            }
                        }
                    }

                    // Base URL
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Base URL:"; Layout.preferredWidth: 120 }
                        QQC2.TextField {
                            id: editorBaseUrl
                            Layout.fillWidth: true
                            text: editingDraft.baseUrl || ""
                            placeholderText: "https://api.openai.com/v1"
                            onTextChanged: editingDraft = Object.assign({}, editingDraft, {baseUrl: text})
                        }
                    }

                    // Model
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Model:"; Layout.preferredWidth: 120 }
                        QQC2.TextField {
                            id: editorModel
                            Layout.fillWidth: true
                            text: editingDraft.model || ""
                            placeholderText: "gpt-4o-mini"
                            onTextChanged: editingDraft = Object.assign({}, editingDraft, {model: text})
                        }
                    }

                    // API Key
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "API Key:"; Layout.preferredWidth: 120 }
                        QQC2.TextField {
                            id: editorApiKey
                            Layout.fillWidth: true
                            text: editingDraft.apiKey || ""
                            placeholderText: "sk-… (leave empty for keyless providers)"
                            echoMode: TextInput.Password
                            onTextChanged: editingDraft = Object.assign({}, editingDraft, {apiKey: text})
                        }
                        QQC2.ToolButton {
                            icon.name: editorApiKey.echoMode === TextInput.Password
                                       ? "password-show-off" : "password-show-on"
                            onClicked: editorApiKey.echoMode =
                                editorApiKey.echoMode === TextInput.Password
                                ? TextInput.Normal : TextInput.Password
                            ToolTip.text: "Show/hide key"
                            ToolTip.visible: hovered
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    // Prompt
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            text: "Prompt:"
                            Layout.preferredWidth: 120
                            Layout.alignment: Qt.AlignTop
                        }
                        QQC2.TextArea {
                            id: editorPrompt
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            text: editingDraft.prompt || ""
                            placeholderText: "What would you like the AI to do on this schedule?"
                            wrapMode: TextEdit.Wrap
                            onTextChanged: editingDraft = Object.assign({}, editingDraft, {prompt: text})
                        }
                    }

                    // System prompt (optional override)
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label {
                            text: "System prompt\n(optional):"
                            Layout.preferredWidth: 120
                            Layout.alignment: Qt.AlignTop
                            wrapMode: Text.Wrap
                        }
                        QQC2.TextArea {
                            id: editorSystemPrompt
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            text: editingDraft.systemPrompt || ""
                            placeholderText: "Override system prompt (leave blank to use global setting)"
                            wrapMode: TextEdit.Wrap
                            onTextChanged: editingDraft = Object.assign({}, editingDraft, {systemPrompt: text})
                        }
                    }

                    // Max tokens
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Max tokens:"; Layout.preferredWidth: 120 }
                        QQC2.SpinBox {
                            id: editorMaxTokens
                            from: 50; to: 8000; stepSize: 50
                            value: editingDraft.maxTokens || 1000
                            onValueChanged: editingDraft = Object.assign({}, editingDraft, {maxTokens: value})
                        }
                        QQC2.Label { text: "tokens"; opacity: 0.6 }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    // Notifications toggle
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Notify on complete:"; Layout.preferredWidth: 140 }
                        QQC2.Switch {
                            id: editorNotify
                            checked: editingDraft.notify !== false
                            onCheckedChanged: editingDraft = Object.assign({}, editingDraft, {notify: checked})
                        }
                        QQC2.Label {
                            text: editorNotify.checked
                                  ? "Shows a KDE desktop notification when done"
                                  : "Silent — no notification"
                            opacity: 0.6; font.pixelSize: 11
                        }
                    }

                    // Notification title
                    RowLayout {
                        Layout.fillWidth: true
                        visible: editorNotify.checked
                        QQC2.Label { text: "Notification title:"; Layout.preferredWidth: 140 }
                        QQC2.TextField {
                            id: editorNotifyTitle
                            Layout.fillWidth: true
                            text: editingDraft.notifyTitle || ""
                            placeholderText: editingDraft.name || "Schedule name"
                            onTextChanged: editingDraft = Object.assign({}, editingDraft, {notifyTitle: text})
                        }
                    }

                    // Save results toggle
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: "Save results:"; Layout.preferredWidth: 140 }
                        QQC2.Switch {
                            id: editorSaveResults
                            checked: editingDraft.saveResults !== false
                            onCheckedChanged: editingDraft = Object.assign({}, editingDraft, {saveResults: checked})
                        }
                        QQC2.Label {
                            text: editorSaveResults.checked
                                  ? "Results stored in ~/.local/share/kdeaichat/results/"
                                  : "Results discarded after notification"
                            opacity: 0.6; font.pixelSize: 11; wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }

                    // Keep results days
                    RowLayout {
                        Layout.fillWidth: true
                        visible: editorSaveResults.checked
                        QQC2.Label { text: "Keep results for:"; Layout.preferredWidth: 140 }
                        QQC2.SpinBox {
                            id: editorKeepDays
                            from: 1; to: 365; stepSize: 1
                            value: editingDraft.keepResultDays || 30
                            onValueChanged: editingDraft = Object.assign({}, editingDraft, {keepResultDays: value})
                        }
                        QQC2.Label { text: "days, then auto-delete"; opacity: 0.6 }
                    }

                    // Buttons
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        QQC2.Button {
                            text: "Cancel"
                            onClicked: scheduleManager.cancelEdit()
                        }
                        QQC2.Button {
                            text: "Save Schedule"
                            highlighted: true
                            enabled: editorName.text.trim() !== "" && editorPrompt.text.trim() !== ""
                            onClicked: scheduleManager.saveEdit()
                        }
                    }
                }
            }
        }
    }

    // ── Delete confirmation dialog ─────────────────────────────────────────
    QQC2.Dialog {
        id: deleteConfirmDialog
        title: "Delete Schedule"
        modal: true
        standardButtons: QQC2.Dialog.Cancel | QQC2.Dialog.Ok
        property int targetIndex: -1

        function openFor(index) {
            targetIndex = index
            open()
        }

        QQC2.Label {
            text: deleteConfirmDialog.targetIndex >= 0 && scheduleManager.scheduleList.length > deleteConfirmDialog.targetIndex
                  ? "Delete \"" + scheduleManager.scheduleList[deleteConfirmDialog.targetIndex].name + "\"?\nThis cannot be undone."
                  : "Delete this schedule?"
            wrapMode: Text.Wrap
        }
        onAccepted: {
            if (targetIndex >= 0) scheduleManager.deleteSchedule(targetIndex)
        }
    }

    // ── Helper: default base URLs per provider ─────────────────────────────
    function defaultBaseUrl(provider) {
        var urls = {
            "openai":       "https://api.openai.com/v1",
            "anthropic":    "https://api.anthropic.com/v1",
            "groq":         "https://api.groq.com/openai/v1",
            "google":       "https://generativelanguage.googleapis.com/v1beta/openai/",
            "deepseek":     "https://api.deepseek.com",
            "mistral":      "https://api.mistral.ai/v1",
            "openrouter":   "https://openrouter.ai/api/v1",
            "xai":          "https://api.x.ai/v1",
            "nvidia":       "https://integrate.api.nvidia.com/v1",
            "fireworks":    "https://api.fireworks.ai/inference/v1",
            "minimax":      "https://api.minimax.io/v1",
            "cloudflare":   "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1",
            "huggingface":  "https://router.huggingface.co/v1",
            "ollama":       "http://localhost:11434/v1",
            "lmstudio":     "http://localhost:1234/v1",
            "local":        "http://localhost:11434/v1",
            "litellm":      "http://localhost:4000/v1",
            "qwen":         "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
            "moonshot":     "https://api.moonshot.ai/v1",
            "mimo":         "https://api.xiaomimimo.com/v1",
            "maritaca":     "https://chat.maritaca.ai/api",
        }
        return urls[provider] || "https://api.openai.com/v1"
    }
}
