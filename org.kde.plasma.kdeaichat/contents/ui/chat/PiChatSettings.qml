// Pi settings for one chat (in ChatSettingsDialog): provider, model and
// thinking level. Empty values use Pi's own defaults.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PC3

ColumnLayout {
    id: pi

    property var providers: []          // [{text, value}]
    property var providerModels: ({})   // provider id -> [model id]
    property string provider: ""
    property string model: ""
    property string thinking: ""
    property bool busy: false

    signal edited()
    signal refreshRequested()

    readonly property var thinkingLevels: ["", "off", "minimal", "low", "medium", "high", "xhigh", "max"]

    spacing: 8
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
    QQC2.Label { text: "Thinking"; opacity: 0.7 }
    QQC2.ComboBox {
        Layout.fillWidth: true
        model: pi.thinkingLevels.map(function(level) { return level || "(model default)"; })
        currentIndex: Math.max(0, pi.thinkingLevels.indexOf(pi.thinking))
        onActivated: { pi.thinking = pi.thinkingLevels[currentIndex]; pi.edited(); }
    }
}
