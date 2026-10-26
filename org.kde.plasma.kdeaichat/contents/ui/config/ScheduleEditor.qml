// The schedule editor's form: name, target chat, message, the timing rules
// (with "Describe when" and a live preview from the helper), and more
// options. `draft` is a schedules.v2.json definition (ScheduleDraft.js);
// ScheduleDialog.qml saves it.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ScheduleDraft.js" as Draft

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: editor

    property var draft: Draft.newSchedule("")
    // Chat metadata ({value, text, archived}) of this widget, for the chat picker.
    property var sessions: []
    property ScheduleService service: null
    property var configuration: null
    property var wallet: null
    property var xhrFactory: null
    // The last schedule_preview answer for the draft (null while it loads).
    property var previewResult: null
    property bool showOptions: false

    readonly property alias describer: describerObject
    readonly property var chats: Draft.chatChoices(sessions, draft.chatId)
    readonly property bool rulesValid: (draft.rules || []).length > 0
        && (draft.rules || []).every(function(rule) { return Draft.ruleProblem(rule) === ""; })
    property int _previewGeneration: 0

    function setField(key, value) {
        var next = Object.assign({}, draft);
        next[key] = value;
        draft = next;
    }
    function setRules(rules) {
        setField("rules", rules);
    }
    function addRule() {
        setRules((draft.rules || []).concat([Draft.defaultRule("weekly", draft.rules)]));
    }

    function refreshPreview() {
        previewTimer.restart();
    }
    function _runPreview() {
        if (!service)
            return;
        var generation = ++_previewGeneration;
        service.preview(Draft.forSave(draft), function(result) {
            if (generation === editor._previewGeneration)
                editor.previewResult = result;
        });
    }

    onDraftChanged: refreshPreview()
    spacing: Kirigami.Units.smallSpacing

    Timer {
        id: previewTimer
        interval: 300
        onTriggered: editor._runPreview()
    }

    ScheduleDescriber {
        id: describerObject
        configuration: editor.configuration
        wallet: editor.wallet
        service: editor.service
        xhrFactory: editor.xhrFactory
        onRulesReady: (rules, preview) => {
            describeBox.filledText = preview.summary || "";
            editor.setRules(rules);
        }
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.TextField {
            objectName: "scheduleName"
            Kirigami.FormData.label: i18n("Name:")
            text: editor.draft.name || ""
            placeholderText: i18n("e.g. Latest news")
            onTextEdited: editor.setField("name", text)
        }
        QQC2.ComboBox {
            objectName: "scheduleChat"
            Kirigami.FormData.label: i18n("Chat:")
            Layout.fillWidth: true
            model: editor.chats
            textRole: "title"
            valueRole: "id"
            currentIndex: editor.chats.findIndex(function(c) { return c.id === editor.draft.chatId; })
            displayText: currentIndex >= 0 ? currentText : (editor.draft.chatId ? i18n("A deleted chat") : i18n("Choose a chat…"))
            onActivated: editor.setField("chatId", currentValue)
        }
    }

    QQC2.Label {
        text: i18n("Message to send:")
    }
    QQC2.TextArea {
        objectName: "scheduleMessage"
        Layout.fillWidth: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 3.5
        wrapMode: TextEdit.Wrap
        placeholderText: i18n("e.g. Summarise today's tech news")
        text: editor.draft.message || ""
        onTextChanged: {
            if (text !== (editor.draft.message || ""))
                editor.setField("message", text.substring(0, 20000));
        }
    }

    Kirigami.Heading {
        level: 4
        text: i18n("When")
    }

    ScheduleDescribeBox {
        id: describeBox
        Layout.fillWidth: true
        describer: describerObject
    }

    Repeater {
        model: editor.draft.rules || []
        delegate: ScheduleRuleRow {
            required property var modelData
            required property int index
            rule: modelData
            rules: editor.draft.rules
            summary: editor.previewResult && editor.previewResult.ok && editor.previewResult.rules
                     ? (editor.previewResult.rules[index] || "") : ""
            onEdited: next => editor.setRules(Draft.replaceRule(editor.draft.rules, index, next))
            onRemoveRequested: editor.setRules(Draft.removeRule(editor.draft.rules, index))
        }
    }

    QQC2.Button {
        objectName: "addRule"
        text: i18n("Add rule")
        icon.name: "list-add"
        enabled: (editor.draft.rules || []).length < 20
        onClicked: editor.addRule()
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: i18n("The schedule runs at the times of every rule, e.g. Mondays at 16:00 and the other days at 15:00.")
    }

    SchedulePreview {
        Layout.fillWidth: true
        result: editor.previewResult
    }

    QQC2.ToolButton {
        objectName: "moreOptions"
        text: editor.showOptions ? i18n("Fewer options") : i18n("More options: dates, run limit, missed runs, notification")
        icon.name: editor.showOptions ? "arrow-up" : "arrow-down"
        onClicked: editor.showOptions = !editor.showOptions
    }

    ScheduleOptions {
        visible: editor.showOptions
        Layout.fillWidth: true
        draft: editor.draft
        onFieldChanged: (key, value) => editor.setField(key, value)
    }
}
