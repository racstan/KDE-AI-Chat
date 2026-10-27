// The project editor: name, colour, instructions, working folder and an
// optional model for direct chats. Opened by chat.projects.openEditor() (new
// project, or an existing one to rename, recolour or delete). Nothing is saved
// until Save. Lives in chat/ChatBody.qml so every menu can open it.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../ProviderService.js" as ProviderService

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Popup {
    id: editor

    property var chat: null
    // The project edited ("" = a new one) and a chat to put in it once saved.
    property string projectId: ""
    property string moveChatId: ""

    // The draft.
    property string name: ""
    property string color: ""
    property string instructions: ""
    property string folder: ""
    property string provider: ""
    property string model: ""

    readonly property var _config: chat && chat.plasmoid ? chat.plasmoid.configuration : ({})
    // "" (the main settings) and the configured direct providers.
    readonly property var providerIds: [""].concat(ProviderService.getSupportedProviders(_config))

    function openFor(projectId, moveChatId) {
        var p = projectId ? chat.projects.byId(projectId) : null;
        editor.projectId = p ? p.id : "";
        editor.moveChatId = moveChatId || "";
        name = p ? p.name : "";
        color = p ? p.color : chat.projects.colors[chat.projects.list.length % chat.projects.colors.length];
        instructions = p ? p.instructions : "";
        folder = p ? p.folder : "";
        provider = p ? p.provider : "";
        model = p ? p.model : "";
        nameField.text = name;
        instructionsArea.text = instructions;
        modelField.text = model;
        providerCombo.currentIndex = Math.max(0, providerIds.indexOf(provider));
        open();
        nameField.forceActiveFocus();
    }

    function save() {
        var fields = {"name": name, "color": color, "instructions": instructions, "folder": folder,
                      "provider": provider, "model": provider ? model : ""};
        var id = projectId;
        if (id)
            chat.projects.update(id, fields);
        else
            id = chat.projects.create(fields);
        if (moveChatId)
            chat.projects.moveChat(moveChatId, id);
        close();
    }

    function remove() {
        var id = projectId;
        close();
        chat.projects.remove(id);
    }

    Connections {
        target: editor.chat ? editor.chat.projects : null
        function onEditorRequested(projectId, moveChatId) { editor.openFor(projectId, moveChatId); }
    }

    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(Kirigami.Units.gridUnit * 24, (parent ? parent.width : 500) - Kirigami.Units.largeSpacing * 2)
    height: Math.min(implicitHeight, (parent ? parent.height : 600) - Kirigami.Units.largeSpacing * 2)
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    padding: Kirigami.Units.largeSpacing

    FolderDialog {
        id: folderDialog
        title: i18n("Select the project's working folder")
        onAccepted: {
            var path = selectedFolder.toString();
            editor.folder = path.indexOf("file://") === 0 ? decodeURIComponent(path.substring(7)) : path;
        }
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            level: 3
            text: editor.projectId ? i18n("Edit project") : i18n("New project")
            Layout.fillWidth: true
        }

        PC3.TextField {
            id: nameField
            objectName: "projectName"
            Layout.fillWidth: true
            placeholderText: i18n("Project name")
            Accessible.name: i18n("Project name")
            onTextChanged: editor.name = text
            onAccepted: if (editor.name.trim() !== "") editor.save()
        }

        // Colour swatches.
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: editor.chat ? editor.chat.projects.colors : []
                delegate: Rectangle {
                    id: swatch
                    required property string modelData
                    required property int index
                    readonly property bool chosen: editor.color === swatch.modelData
                    objectName: "colorSwatch"
                    width: Kirigami.Units.gridUnit * 1.4
                    height: width
                    radius: width / 2
                    color: swatch.modelData
                    border.width: swatch.chosen || swatch.activeFocus ? 3 : 1
                    border.color: swatch.chosen ? Kirigami.Theme.textColor : Qt.rgba(0, 0, 0, 0.25)
                    activeFocusOnTab: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: i18n("Colour %1", swatch.index + 1)
                    Accessible.checked: swatch.chosen
                    Keys.onSpacePressed: editor.color = swatch.modelData
                    TapHandler { onTapped: editor.color = swatch.modelData }
                }
            }
        }

        PC3.Label {
            text: i18n("Instructions for every chat in this project")
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        PC3.TextArea {
            Keys.onTabPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
            Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
            Accessible.name: placeholderText
            id: instructionsArea
            objectName: "projectInstructions"
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 5
            wrapMode: Text.Wrap
            placeholderText: i18n("For example: answer in French, keep code in Python")
            onTextChanged: editor.instructions = text
        }

        PC3.Label {
            text: i18n("Working folder (OpenCode and Pi work here)")
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            PC3.Label {
                objectName: "projectFolder"
                Layout.fillWidth: true
                text: editor.folder || i18n("No folder")
                elide: Text.ElideMiddle
                opacity: editor.folder ? 1 : 0.6
            }
            PC3.Button {
                text: i18n("Choose…")
                icon.name: "folder-open"
                onClicked: folderDialog.open()
            }
            PC3.ToolButton {
                visible: editor.folder !== ""
                icon.name: "edit-clear"
                Accessible.name: i18n("No folder")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: Accessible.name
                onClicked: editor.folder = ""
            }
        }

        PC3.Label {
            text: i18n("Model for direct chats")
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.ComboBox {
                Accessible.name: i18n("Model for direct chats")
                id: providerCombo
                objectName: "projectProvider"
                Layout.fillWidth: true
                model: editor.providerIds.map(function(id) {
                    return id ? (editor.chat.providerDisplayName(id) || id) : i18n("Main settings");
                })
                onActivated: editor.provider = editor.providerIds[currentIndex] || ""
            }
            PC3.TextField {
                Accessible.name: placeholderText
                id: modelField
                objectName: "projectModel"
                Layout.fillWidth: true
                enabled: editor.provider !== ""
                placeholderText: editor.provider ? ProviderService.getProviderConfig(editor.provider, editor._config).model || i18n("Model")
                                                 : i18n("Model")
                onTextChanged: editor.model = text
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            PC3.Button {
                objectName: "deleteProject"
                visible: editor.projectId !== ""
                text: i18n("Delete project")
                icon.name: "edit-delete"
                onClicked: editor.remove()
            }
            Item { Layout.fillWidth: true }
            PC3.Button {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onClicked: editor.close()
            }
            PC3.Button {
                objectName: "saveProject"
                text: i18n("Save")
                icon.name: "dialog-ok-apply"
                enabled: editor.name.trim() !== ""
                onClicked: editor.save()
            }
        }
    }
}
