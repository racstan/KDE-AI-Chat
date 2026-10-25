// Pi settings for one chat (in ChatSettingsDialog): provider, model and
// thinking level. Empty values use Pi's own defaults. The thinking picker is
// only there for a model that thinks (`variants` is empty otherwise).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../components" as Components

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
            QQC2.ToolTip.text: "Refresh Pi providers and models"
        }
    }
    QQC2.Label { text: "Provider"; opacity: 0.7 }
    QQC2.ComboBox {
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
    QQC2.Label { text: "Model"; opacity: 0.7 }
    QQC2.ComboBox {
        id: modelCombo
        Layout.fillWidth: true
        editable: true
        model: pi.providerModels[pi.provider] || []
        // Loading the list would otherwise replace the chat's model with the first one.
        onModelChanged: Qt.callLater(function() { modelCombo.editText = pi.model; })
        Component.onCompleted: editText = pi.model
        onActivated: { pi.model = currentText; pi.edited(); }
        onEditTextChanged: { if (activeFocus) { pi.model = editText; pi.edited(); } }
    }
    QQC2.Label { visible: thinkingPicker.visible; text: "Thinking"; opacity: 0.7 }
    Components.VariantPicker {
        id: thinkingPicker
        objectName: "thinkingPicker"
        Layout.fillWidth: true
        variants: pi.variants
        value: pi.thinking
        onPicked: function(id) { pi.thinking = id; pi.edited(); }
    }
}
