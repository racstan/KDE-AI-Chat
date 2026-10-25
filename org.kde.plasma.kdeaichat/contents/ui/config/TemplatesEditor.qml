// Prompt templates: typing /<name> in the chat box replaces it with the
// template's text. Edits the JSON list kept in `promptTemplates`
// ([{name, prompt}]); `json` is the page's cfg_promptTemplates.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: editor

    property string json: "[]"
    readonly property var templates: {
        try {
            const list = JSON.parse(json || "[]");
            return Array.isArray(list) ? list : [];
        } catch (e) {
            return [];
        }
    }
    property int editingIndex: -1

    spacing: Kirigami.Units.smallSpacing

    function cleanName(text) {
        return String(text || "").trim().replace(/^\/+/, "").replace(/\s+/g, "-");
    }

    function store(list) {
        json = JSON.stringify(list);
    }

    function save(index, name, prompt) {
        var list = templates.slice();
        var entry = {"name": cleanName(name), "prompt": String(prompt || "").trim()};
        if (!entry.name)
            return;
        if (index >= 0 && index < list.length)
            list[index] = entry;
        else
            list.push(entry);
        store(list);
        editingIndex = -1;
    }

    function remove(index) {
        var list = templates.slice();
        list.splice(index, 1);
        store(list);
        editingIndex = -1;
    }

    Repeater {
        model: editor.templates

        delegate: RowLayout {
            id: row
            required property var modelData
            required property int index
            Layout.fillWidth: true
            visible: editor.editingIndex !== index

            QQC2.Label {
                text: "/" + (row.modelData.name || "")
                font.family: "monospace"
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: row.modelData.prompt || ""
                elide: Text.ElideRight
                maximumLineCount: 1
                opacity: 0.7
            }
            QQC2.ToolButton {
                icon.name: "document-edit"
                onClicked: {
                    nameField.text = row.modelData.name || "";
                    promptField.text = row.modelData.prompt || "";
                    editor.editingIndex = row.index;
                }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Edit")
                Accessible.name: i18n("Edit /%1", row.modelData.name)
            }
            QQC2.ToolButton {
                icon.name: "edit-delete"
                onClicked: editor.remove(row.index)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Remove")
                Accessible.name: i18n("Remove /%1", row.modelData.name)
            }
        }
    }

    QQC2.Label {
        visible: editor.templates.length === 0 && editor.editingIndex < 0
        text: i18n("No templates yet.")
        opacity: 0.7
    }

    // One editor, used both for adding and for changing a template.
    GridLayout {
        Layout.fillWidth: true
        visible: editor.editingIndex !== -1
        columns: 2

        QQC2.TextField {
            id: nameField
            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            placeholderText: i18n("Name, e.g. review")
            Accessible.name: i18n("Template name")
        }
        QQC2.TextField {
            id: promptField
            Layout.fillWidth: true
            placeholderText: i18n("Text that replaces /name")
            Accessible.name: i18n("Template text")
            onAccepted: editor.save(editor.editingIndex, nameField.text, text)
        }
        Item { implicitWidth: 1 }
        RowLayout {
            QQC2.Button {
                text: i18n("Save")
                icon.name: "document-save"
                enabled: editor.cleanName(nameField.text) !== ""
                onClicked: editor.save(editor.editingIndex, nameField.text, promptField.text)
            }
            QQC2.Button {
                text: i18n("Cancel")
                onClicked: editor.editingIndex = -1
            }
        }
    }

    QQC2.Button {
        visible: editor.editingIndex === -1
        text: i18n("Add template")
        icon.name: "list-add"
        onClicked: {
            nameField.text = "";
            promptField.text = "";
            editor.editingIndex = -2;
            nameField.forceActiveFocus();
        }
    }
}
