// This chat's own settings, for the Chat info panel: where replies come from
// (provider, OpenCode or Pi), the model, the working folder, instructions and
// response length. It edits a ChatSettingsDraft; nothing is saved until Apply
// in ChatSettingsDialog.qml.
//
// The drop-downs are QQC2.ComboBox, not PC3.ComboBox: with libplasma 6.8 the
// PC3 one reports "Binding loop detected for property implicitWidth/Height"
// when created after another window already showed one (as in the tests).
import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../ProviderCheck.js" as ProviderCheck
import "DisplayPath.js" as Paths
import "../components" as Components
import "../config" as Config

// Each setting is a SettingField: a small grey label, the input(s) and help.
ColumnLayout {
    id: form

    spacing: Kirigami.Units.largeSpacing

    // The ChatSettingsDraft being edited.
    property var draft: null

    // The inputs, for tests.
    property alias providerCombo: providerCombo
    property alias modelCombo: modelCombo
    property alias variantPicker: variantPicker
    property alias cwdField: cwdField
    readonly property string home: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    property alias systemCheck: systemCheck
    property alias systemArea: systemArea
    property alias responseLengthCombo: responseLengthCombo
    property alias personalityCheck: personalityCheck

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
            cwdField.text = Paths.tilde(draft.ocCwd, form.home);
            systemCheck.checked = draft.systemEnabled;
            systemArea.text = draft.system;
            responseLengthCombo.currentIndex = draft.responseLength;
            personalityCheck.checked = draft.personalityOn;
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
            cwdField.text = Paths.tilde(Paths.plainPath(selectedFolder), form.home);
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
    Config.SettingHelp {
        visible: ownModelCheck.visible
        text: i18n("On: this chat can use a different provider or model than the main settings. Off: it follows the main settings.") // qmllint disable unqualified
    }

    // --- Provider ---

    SettingField {
        visible: form.draft.modelEditable && form.draft.mode === "provider"
        label: i18n("Provider")
        help: i18n("The AI service this chat talks to.") // qmllint disable unqualified

        QQC2.ComboBox {
            Accessible.name: i18n("Provider") // qmllint disable unqualified
            id: providerCombo
            Layout.fillWidth: true
            textRole: "text"
            valueRole: "value"
            onActivated: {
                form.draft.provider = currentValue || "";
                form.draft.model = "";
                form.draft.variant = "";
                form.draft.directVariants = [];
                form.draft.modelCandidates = [];
                form.edited();
                form.draft.refreshModels(true);
            }
        }
    }

    SettingField {
        visible: form.draft.modelEditable && form.draft.mode === "provider"
        label: i18n("Model")
        help: i18n("The AI model that answers in this chat. Refresh asks the provider which ones it has.") // qmllint disable unqualified

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                Accessible.name: i18n("Model") // qmllint disable unqualified
                id: modelCombo
                Layout.fillWidth: true
                editable: true
                onActivated: {
                    form.draft.changeModel(currentText, true);
                    form.edited();
                }
                onEditTextChanged: {
                    if (activeFocus) {
                        form.draft.changeModel(editText, true);
                        form.edited();
                    }
                }
            }
            PC3.ToolButton {
                icon.name: "view-refresh"
                enabled: !form.draft.busy
                onClicked: form.draft.refreshModels(true)
                Accessible.name: i18n("Refresh models") // qmllint disable unqualified
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Refresh models")
            }
        }
    }

    // A model the provider was found to have retired (see the provider settings).
    PC3.Label { textFormat: Text.PlainText
        objectName: "deadModelNote"
        readonly property string reason: ProviderCheck.deadReason(form.draft.effectiveProvider(), form.draft.model)
        visible: form.draft.modelEditable && form.draft.mode === "provider" && reason !== ""
        Layout.fillWidth: true
        text: i18n("This model is not available from the provider: %1", reason) // qmllint disable unqualified
        color: Kirigami.Theme.neutralTextColor
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
    }

    // The model's variant (reasoning level): only when its source reports any
    // (direct providers, OpenCode). Pi's thinking level is in PiChatSettings.
    SettingField {
        visible: form.draft.modelEditable && form.draft.mode !== "pi" && form.draft.variantList.length > 0
        label: i18n("Variant") // qmllint disable unqualified
        help: i18n("How hard the model thinks before answering: more is slower and costs more, but helps with hard questions.") // qmllint disable unqualified

        Components.VariantPicker {
            id: variantPicker
            objectName: "variantPicker"
            Layout.fillWidth: true
            variants: form.draft.variantList
            value: form.draft.variantId
            onPicked: function(id) { form.draft.setVariantId(id); form.edited(); }
        }
    }

    // --- OpenCode ---

    SettingField {
        visible: form.draft.modelEditable && form.draft.mode === "opencode"
        label: i18n("Provider")
        help: i18n("The AI service OpenCode uses for this chat. Empty: OpenCode's default.") // qmllint disable unqualified

        QQC2.ComboBox {
            Accessible.name: i18n("Provider") // qmllint disable unqualified
            id: ocProviderCombo
            Layout.fillWidth: true
            editable: true
            onEditTextChanged: {
                form.draft.ocProvider = editText;
                form.edited();
            }
        }
    }

    SettingField {
        visible: form.draft.modelEditable && form.draft.mode === "opencode"
        label: i18n("Model")
        help: i18n("The AI model OpenCode uses for this chat. Empty: OpenCode's default.") // qmllint disable unqualified

        QQC2.ComboBox {
            Accessible.name: i18n("Model") // qmllint disable unqualified
            id: ocModelCombo
            Layout.fillWidth: true
            editable: true
            onEditTextChanged: {
                form.draft.changeModel(editText, activeFocus);
                form.edited();
            }
        }
    }

    SettingField {
        visible: form.draft.modelEditable && form.draft.mode === "opencode"
        label: i18n("Agent")
        help: i18n("OpenCode's way of working, for example \"build\" to make changes or \"plan\" to only suggest them.") // qmllint disable unqualified

        QQC2.ComboBox {
            Accessible.name: i18n("Agent") // qmllint disable unqualified
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
        variants: form.draft.variantList
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

    SettingField {
        label: i18n("Working folder")
        help: i18n("The folder on your computer this chat works in: the agents read and change files there.") // qmllint disable unqualified

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.TextField {
                Accessible.name: placeholderText
                id: cwdField
                Layout.fillWidth: true
                maximumLength: 4096
                // Empty: the project's folder, when the chat is in a project that has one.
                // qmllint disable unqualified
                readonly property var projectFolder: form.draft.rootRef && form.draft.rootRef.projects
                    ? form.draft.rootRef.projects.workspaceFor(form.draft.sessionId) : null
                placeholderText: projectFolder && projectFolder.from === "project" ? i18n("The project's folder: %1", Paths.tilde(projectFolder.path, form.home))
                                                                                 : i18n("No workspace")
                // qmllint enable unqualified
                onTextChanged: {
                    form.draft.ocCwd = Paths.expand(text, form.home);
                    form.edited();
                }
            }
            PC3.ToolButton {
                icon.name: "folder-open"
                onClicked: folderDialog.open()
                Accessible.name: i18n("Choose working folder") // qmllint disable unqualified
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose working folder")
            }
        }
    }

    PC3.Label { textFormat: Text.PlainText
        visible: form.draft.modelEditable && form.draft.status.length > 0
        Layout.fillWidth: true
        text: form.draft.status
        color: form.draft.statusError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        wrapMode: Text.Wrap
        font: Kirigami.Theme.smallFont
    }

    // --- Instructions (OpenCode has its own: Personality only) and length ---

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    SettingField {
        label: i18n("Instructions")
        help: i18n("Extra instructions only for this chat, for example \"Answer in French\" or \"You are a patient maths tutor\". \"Use my Personality settings\" adds what you filled in on the Personality settings page.") // qmllint disable unqualified

        PC3.CheckBox {
            id: systemCheck
            visible: form.draft.mode !== "opencode"
            text: i18n("Give this chat system instructions")
            onCheckedChanged: {
                form.draft.systemEnabled = checked;
                form.edited();
            }
        }
        PC3.TextArea {
            Keys.onTabPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
            Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
            Accessible.name: placeholderText
            id: systemArea
            visible: form.draft.mode !== "opencode"
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
        // Settings → Personality; on its own switch, so it stays when the chat's instructions are off.
        PC3.CheckBox {
            id: personalityCheck
            objectName: "personalityCheck"
            text: i18n("Use my Personality settings") // qmllint disable unqualified
            onToggled: {
                form.draft.personalityOn = personalityCheck.checked;
                form.edited();
            }
        }
    }

    SettingField {
        visible: form.draft.mode !== "opencode"
        label: i18n("Response length")
        help: i18n("How long the answers in this chat should be. \"Default\" lets the model decide.") // qmllint disable unqualified

        QQC2.ComboBox {
            Accessible.name: i18n("Response length") // qmllint disable unqualified
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
