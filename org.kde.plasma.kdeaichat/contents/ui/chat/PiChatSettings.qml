// Pi settings for one chat (in ChatSettingsDialog): provider, model and
// thinking level. Empty values use Pi's own defaults. The thinking picker is
// only there for a model that thinks (`variants` is empty otherwise).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../components" as Components

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: pi

    property var providers: []          // [{text, value}]
    property var providerModels: ({})   // provider id -> [model id]
    property string provider: ""
    property string model: ""
    property string thinking: ""
    // Pi's thinking levels for the model, [{id, label}] (Variants.fromPi); empty: no picker.
    property var variants: []
    property bool busy: false

    signal edited()
    signal refreshRequested()

    spacing: Kirigami.Units.largeSpacing
    onModelChanged: if (!modelCombo.activeFocus) modelCombo.editText = pi.model

    RowLayout {
        Layout.fillWidth: true
        PC3.Label { text: "Pi Agent"; font.bold: true; Layout.fillWidth: true }
        PC3.ToolButton {
            icon.name: "view-refresh"
            enabled: !pi.busy
            onClicked: pi.refreshRequested()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Refresh Pi providers and models")
            Accessible.name: i18n("Refresh Pi providers and models")
        }
    }
    SettingField {
        label: i18n("Provider")
        help: i18n("The AI service Pi uses for this chat. Empty: Pi's default.")
        QQC2.ComboBox {
            Accessible.name: i18n("Provider")
            Layout.fillWidth: true
            model: pi.providers
            textRole: "text"
            valueRole: "value"
            currentIndex: {
                for (var i = 0; i < pi.providers.length; i++) if (pi.providers[i].value === pi.provider) return i;
                return -1;
            }
            onActivated: {
                pi.provider = currentValue || currentText;
                var models = pi.providerModels[pi.provider] || [];
                pi.model = models.length > 0 ? models[0] : "";
                pi.edited();
            }
        }
    }
    SettingField {
        label: i18n("Model")
        help: i18n("The AI model Pi uses for this chat. Empty: Pi's default.")
        QQC2.ComboBox {
            Accessible.name: i18n("Model")
            id: modelCombo
            Layout.fillWidth: true
            editable: true
            model: pi.providerModels[pi.provider] || []
            // Shows the chat's model; also picks its row, so the list loading later can't replace it.
            function showChatModel() {
                if (activeFocus)
                    return;
                var row = find(pi.model);
                if (currentIndex !== row)
                    currentIndex = row;
                if (editText !== pi.model)
                    editText = pi.model;
            }
            onModelChanged: Qt.callLater(showChatModel)
            onCountChanged: Qt.callLater(showChatModel)
            Component.onCompleted: Qt.callLater(showChatModel)
            onActivated: { pi.model = currentText; pi.edited(); }
            onEditTextChanged: { if (activeFocus) { pi.model = editText; pi.edited(); } }
        }
    }
    SettingField {
        visible: pi.variants.length > 0
        label: i18n("Thinking")
        help: i18n("How hard the model thinks before answering: more is slower and costs more, but helps with hard tasks.")
        Components.VariantPicker {
            id: thinkingPicker
            objectName: "thinkingPicker"
            Layout.fillWidth: true
            variants: pi.variants
            value: pi.thinking
            onPicked: function(id) { pi.thinking = id; pi.edited(); }
        }
    }
}
