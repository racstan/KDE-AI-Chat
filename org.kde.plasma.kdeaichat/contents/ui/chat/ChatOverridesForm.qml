// This chat's own settings, for the Chat info panel: where replies come from
// (provider, OpenCode or Pi), the model, the working folder, instructions and
// response length. It edits a ChatSettingsDraft; nothing is saved until Apply
// in ChatSettingsDialog.qml.
//
// The drop-downs are QQC2.ComboBox, not PC3.ComboBox: with libplasma 6.8 the
// PC3 one reports "Binding loop detected for property implicitWidth" (or
// implicitHeight) whenever it is created after another window already showed
// one, as in the test suite.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../ProviderCheck.js" as ProviderCheck

ColumnLayout {
    id: form

    // A small grey label above its input(s).
    component Field: ColumnLayout {
        property string label
        default property alias content: slot.data

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            text: label
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
        }
        ColumnLayout {
            id: slot
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
        }
    }

    spacing: Kirigami.Units.largeSpacing

    // The ChatSettingsDraft being edited.
    property var draft: null

    // The inputs, for tests.
    property alias providerCombo: providerCombo
    property alias modelCombo: modelCombo
    property alias cwdField: cwdField
    property alias systemCheck: systemCheck
    property alias systemArea: systemArea
    property alias responseLengthCombo: responseLengthCombo

    function edited() {
        if (draft && !draft.loading)
            draft.dirty = true;
    }

    // Puts the draft's values into the lists and inputs. The values are copied
    // first: giving an editable combo a new model resets its text, which would
    // overwrite the draft through the edit handlers.
    function fill(withFields) {
        var rootRef = draft.rootRef;
        var model = draft.model, agent = draft.ocAgent, ocProvider = draft.ocProvider, ocModel = draft.ocModel;
        var entries = draft.providerEntries();
        providerCombo.model = entries;
        providerCombo.currentIndex = 0;
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].value === draft.provider) {
                providerCombo.currentIndex = i;
                break;
            }
        }
        modelCombo.model = draft.modelCandidates;
        modelCombo.editText = model;
        agentCombo.model = draft.names(rootRef ? rootRef.openCodeAgentsList : [], draft.defaultAgentText);
        agentCombo.editText = agent || "";
        ocProviderCombo.model = draft.names(rootRef ? rootRef.openCodeProvidersList : [], draft.defaultProviderText);
        ocProviderCombo.editText = ocProvider || "";
        ocModelCombo.model = draft.names(rootRef ? rootRef.openCodeModelsList : [], draft.defaultModelText);
        ocModelCombo.editText = ocModel || "";
        draft.model = model;
        draft.ocAgent = agent;
        draft.ocProvider = ocProvider;
        draft.ocModel = ocModel;
        if (withFields) {
            cwdField.text = draft.ocCwd;
            systemCheck.checked = draft.systemEnabled;
            systemArea.text = draft.system;
            responseLengthCombo.currentIndex = draft.responseLength;
        }
    }

    Connections {
        target: form.draft
        function onLoaded() { form.fill(true); }
        function onListsChanged() { form.fill(false); }
    }

    FolderDialog {
        id: folderDialog
        title: i18n("Select the chat's working folder")
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.substring(7));
            cwdField.text = path;
            form.edited();
        }
    }

    // A chat keeps the mode it was started in: shown, not editable.
    PC3.Label {
        objectName: "modeLabel"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: i18n("Mode: %1 (set when the chat was started)", form.draft.mode === "opencode" ? "OpenCode"
              : form.draft.mode === "pi" ? "Pi" : i18n("direct provider"))
    }

    OwnModelCheck {
        id: ownModelCheck
        objectName: "ownModelCheck"
        visible: form.draft.perChat
        checked: form.draft.ownModel
        onToggled: form.draft.setOwnModel(checked)
    }


    // --- Provider ---

    Field {
        visible: form.draft.modelEditable && form.draft.mode === "provider"
        label: i18n("Provider")

        QQC2.ComboBox {
            id: providerCombo
            Layout.fillWidth: true
            textRole: "text"
            valueRole: "value"
            onActivated: {
                form.draft.provider = currentValue || "";
                form.draft.model = "";
                form.draft.modelCandidates = [];
                form.edited();
                form.draft.refreshModels(true);
            }
        }
    }

    Field {
        visible: form.draft.modelEditable && form.draft.mode === "provider"
        label: i18n("Model")

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: modelCombo
                Layout.fillWidth: true
                editable: true
                onActivated: {
                    form.draft.model = currentText;
                    form.edited();
                }
                onEditTextChanged: {
                    if (activeFocus) {
                        form.draft.model = editText;
                        form.edited();
                    }
                }
            }
            PC3.ToolButton {
                icon.name: "view-refresh"
                enabled: !form.draft.busy
                onClicked: form.draft.refreshModels(true)
                Accessible.name: i18n("Refresh models")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Refresh models")
            }
        }
    }

    // A model the provider was found to have retired (see the provider settings).
    PC3.Label {
        objectName: "deadModelNote"
        readonly property string reason: ProviderCheck.deadReason(form.draft.effectiveProvider(), form.draft.model)
        visible: form.draft.modelEditable && form.draft.mode === "provider" && reason !== ""
        Layout.fillWidth: true
        text: i18n("This model is not available from the provider: %1", reason) // qmllint disable unqualified
        color: Kirigami.Theme.neutralTextColor
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
    }

    // --- OpenCode ---

    Field {
        visible: form.draft.modelEditable && form.draft.mode === "opencode"
        label: i18n("Provider")

        QQC2.ComboBox {
            id: ocProviderCombo
            Layout.fillWidth: true
            editable: true
            onEditTextChanged: {
                form.draft.ocProvider = editText;
                form.edited();
            }
        }
    }

    Field {
        visible: form.draft.modelEditable && form.draft.mode === "opencode"
        label: i18n("Model")

        QQC2.ComboBox {
            id: ocModelCombo
            Layout.fillWidth: true
            editable: true
            onEditTextChanged: {
                form.draft.ocModel = editText;
                form.edited();
            }
        }
    }

    Field {
        visible: form.draft.modelEditable && form.draft.mode === "opencode"
        label: i18n("Agent")

        QQC2.ComboBox {
            id: agentCombo
            Layout.fillWidth: true
            editable: true
            onEditTextChanged: {
                form.draft.ocAgent = editText;
                form.edited();
            }
        }
    }

    PC3.Button {
        visible: form.draft.modelEditable && form.draft.mode === "opencode"
        icon.name: "view-refresh"
        text: i18n("Refresh providers and agents")
        enabled: !form.draft.busy
        onClicked: form.draft.refreshOpenCode(function() { form.draft.refreshAgents(); })
    }

    // --- Pi ---

    PiChatSettings {
        visible: form.draft.modelEditable && form.draft.mode === "pi"
        Layout.fillWidth: true
        providers: form.draft.piProviders
        providerModels: form.draft.piModelMap
        provider: form.draft.piProvider
        model: form.draft.piModel
        thinking: form.draft.piThinking
        busy: form.draft.busy
        onRefreshRequested: form.draft.refreshPi()
        onEdited: {
            form.draft.piProvider = provider;
            form.draft.piModel = model;
            form.draft.piThinking = thinking;
            form.draft.dirty = true;
        }
    }

    // --- The workspace (every mode) ---

    Field {
        label: i18n("Working folder")

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.TextField {
                id: cwdField
                Layout.fillWidth: true
                maximumLength: 4096
                placeholderText: i18n("No workspace")
                onTextChanged: {
                    form.draft.ocCwd = text;
                    form.edited();
                }
            }
            PC3.ToolButton {
                icon.name: "folder-open"
                onClicked: folderDialog.open()
                Accessible.name: i18n("Choose working folder")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose working folder")
            }
        }
    }

    PC3.Label {
        visible: form.draft.modelEditable && form.draft.status.length > 0
        Layout.fillWidth: true
        text: form.draft.status
        color: form.draft.statusError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
    }

    // --- Instructions and length (not for OpenCode, which has its own) ---

    Kirigami.Separator {
        visible: form.draft.mode !== "opencode"
        Layout.fillWidth: true
    }

    Field {
        visible: form.draft.mode !== "opencode"
        label: i18n("Instructions")

        PC3.CheckBox {
            id: systemCheck
            text: i18n("Give this chat system instructions")
            onCheckedChanged: {
                form.draft.systemEnabled = checked;
                form.edited();
            }
        }
        PC3.TextArea {
            id: systemArea
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6
            enabled: systemCheck.checked
            wrapMode: Text.Wrap
            placeholderText: i18n("Instructions for this chat")
            onTextChanged: {
                form.draft.system = text;
                form.edited();
            }
        }
    }

    Field {
        visible: form.draft.mode !== "opencode"
        label: i18n("Response length")

        QQC2.ComboBox {
            id: responseLengthCombo
            Layout.fillWidth: true
            model: [i18n("Default"), i18n("Short"), i18n("Balanced"), i18n("Detailed"), i18n("Comprehensive")]
            onActivated: {
                form.draft.responseLength = currentIndex;
                form.edited();
            }
        }
    }
}
