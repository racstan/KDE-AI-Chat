// LINKAGE RELATIONSHIPS:
// - ConfigOpenCodeSection.qml: Contains UI fields and controls for OpenCode local agent integration.
// - Parent: Instantiated inside ConfigGeneral.qml (the main KCM settings page).
// - Linked via properties:
//   - Exposes child fields via aliases (e.g. openCodeUrlField, openCodeModelValueField, etc.) to the parent for configuration bindings (cfg_).
//   - Accesses parent helper functions (e.g., page.refreshOpenCodeDiscovery, page.killRunningOpenCodeSession) and properties (e.g., page.cfg_useOpenCode, page.openCodeBusy) via the `page` reference.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: openCodeSection

    property var page: null

    // Expose fields via alias for configuration bindings in the parent KCM
    property alias openCodeUrlField: openCodeUrlField
    property alias autoStartOpenCodeToggle: autoStartOpenCodeToggle
    property alias openCodeStartCommandField: openCodeStartCommandField
    property alias openCodeStopCommandField: openCodeStopCommandField
    property alias openCodeAutoKillToggle: openCodeAutoKillToggle
    property alias openCodeAutoKillMinutesSpin: openCodeAutoKillMinutesSpin
    property alias openCodeProviderValueField: openCodeProviderValueField
    property alias openCodeModelValueField: openCodeModelValueField

    Kirigami.Separator {
        visible: page ? page.cfg_useOpenCode : false
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: page ? page.translate("OpenCode") : "OpenCode"
    }

    QQC2.TextField {
        id: openCodeUrlField
        visible: page ? page.cfg_useOpenCode : false
        Kirigami.FormData.label: page ? page.translate("OpenCode URL:") : "OpenCode URL:"
        Layout.fillWidth: true
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        placeholderText: "http://127.0.0.1:4096/v1"
    }

    QQC2.Label {
        visible: page ? page.cfg_useOpenCode : false
        Layout.fillWidth: true
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        wrapMode: Text.Wrap
        opacity: 0.72
        font: Kirigami.Theme.smallFont
        text: page ? page.translate("The base URL of your local offline OpenCode agent service endpoint (default: <code>http://127.0.0.1:4096/v1</code>).") : ""
    }

    QQC2.CheckBox {
        id: autoStartOpenCodeToggle
        visible: page ? page.cfg_useOpenCode : false
        Kirigami.FormData.label: page ? page.translate("Auto-start server:") : "Auto-start server:"
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        text: page ? page.translate("Automatically start OpenCode server when plasmoid loads") : ""
    }

    QQC2.CheckBox {
        id: openCodeAutoKillToggle
        visible: page ? page.cfg_useOpenCode : false
        Kirigami.FormData.label: page ? page.translate("Auto-kill session:") : "Auto-kill session:"
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        text: page ? page.translate("Automatically stop OpenCode server to save memory when inactive") : ""
    }

    RowLayout {
        visible: page ? (page.cfg_useOpenCode && openCodeAutoKillToggle.checked) : false
        Kirigami.FormData.label: page ? page.translate("Kill inactivity delay:") : "Kill inactivity delay:"
        Layout.fillWidth: true
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        spacing: Kirigami.Units.smallSpacing

        QQC2.SpinBox {
            id: openCodeAutoKillMinutesSpin
            from: 1
            to: 1440
            stepSize: 1
            editable: true
        }

        QQC2.Label {
            text: page ? page.translate("minute(s) of inactivity") : "minute(s) of inactivity"
            Layout.alignment: Qt.AlignVCenter
        }
    }

    RowLayout {
        visible: page ? page.cfg_useOpenCode : false
        Kirigami.FormData.label: page ? page.translate("OpenCode server:") : "OpenCode server:"
        Layout.fillWidth: true

        QQC2.Button {
            text: page ? page.translate("Start server") : "Start server"
            enabled: page ? !page.openCodeBusy : true
            onClicked: { if (page) page.startOpenCodeServer(); }
        }

        QQC2.Button {
            text: page ? page.translate("Stop server") : "Stop server"
            enabled: page ? !page.openCodeBusy : true
            onClicked: { if (page) page.stopOpenCodeServer(); }
        }

        QQC2.Button {
            text: page ? page.translate("Check server") : "Check server"
            enabled: page ? !page.openCodeBusy : true
            onClicked: { if (page) page.refreshOpenCodeDiscovery(); }
        }
    }

    QQC2.BusyIndicator {
        visible: page ? (page.cfg_useOpenCode && page.openCodeBusy) : false
        running: visible
        Kirigami.FormData.label: page ? page.translate("Loading:") : "Loading:"
    }

    QQC2.ComboBox {
        id: openCodeProviderBox
        visible: page ? (page.cfg_useOpenCode && page.openCodeProviderCandidates.length > 0) : false
        Kirigami.FormData.label: page ? page.translate("Providers:") : "Providers:"
        Layout.fillWidth: true
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        model: page ? page.openCodeProviderCandidates : []
        currentIndex: page ? page.openCodeProviderCandidates.indexOf(openCodeProviderValueField.text) : -1
        onActivated: {
            let pName = currentText;
            if (page) {
                page.setOpenCodeProviderValue(pName);
                page.setOpenCodeModelValue("");
                page.openCodeModelCandidates = page.openCodeProviderModelMap[pName] || [];
                page.updateFilteredOpenCodeModels("");
            }
        }
    }

    QQC2.Label {
        visible: page ? (page.cfg_useOpenCode && page.openCodeProviderCandidates.length > 0) : false
        Kirigami.FormData.label: page ? page.translate("OpenCode models:") : "OpenCode models:"
        Layout.fillWidth: true
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        text: page ? (page.openCodeModelCandidates.length > 0 ? page.openCodeModelCandidates.join(", ") : page.translate("None")) : ""
        wrapMode: Text.Wrap
        opacity: 0.8
    }

    QQC2.TextField {
        id: openCodeModelTextField
        visible: page ? (page.cfg_useOpenCode && page.openCodeModelCandidates.length > 0) : false
        Kirigami.FormData.label: page ? page.translate("Model:") : "Model:"
        Layout.fillWidth: true
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        placeholderText: page ? page.translate("Enter or search model...") : "Enter or search model..."
        rightPadding: openCodeDropdownButton.width + Kirigami.Units.smallSpacing

        Binding {
            target: openCodeModelTextField
            property: "text"
            value: openCodeModelValueField.text
            when: !openCodeModelTextField.activeFocus && !openCodeModelPopup.visible
        }

        onTextChanged: {
            if (activeFocus) {
                if (page) {
                    page.setOpenCodeModelValue(text);
                    page.openCodeModelSearch = text;
                    page.updateFilteredOpenCodeModels(text);
                }
                if (page && page.filteredOpenCodeModels.length > 0) {
                    if (!openCodeModelPopup.visible) {
                        openCodeModelPopup.open();
                    }
                } else {
                    openCodeModelPopup.close();
                }
            }
        }

        onActiveFocusChanged: {
            if (!activeFocus) {
                openCodeModelPopup.close();
            }
        }

        onAccepted: {
            openCodeModelPopup.close();
        }

        QQC2.ToolButton {
            id: openCodeDropdownButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon.name: "go-down"
            flat: true
            onClicked: {
                if (openCodeModelPopup.visible) {
                    openCodeModelPopup.close();
                } else {
                    if (page) page.updateFilteredOpenCodeModels("");
                    openCodeModelPopup.open();
                }
            }
        }

        QQC2.Popup {
            id: openCodeModelPopup
            x: 0
            y: parent.height + Kirigami.Units.smallSpacing / 2
            width: parent.width
            height: Math.min(250, openCodeModelListView.contentHeight + Kirigami.Units.smallSpacing * 2)
            padding: 0
            closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

            background: Rectangle {
                color: Kirigami.Theme.backgroundColor
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                border.width: 1
                radius: 4
            }

            contentItem: QQC2.ScrollView {
                clip: true
                ListView {
                    id: openCodeModelListView
                    model: page ? page.filteredOpenCodeModels : []
                    delegate: QQC2.ItemDelegate {
                        width: openCodeModelListView.width
                        text: modelData
                        highlighted: ListView.isCurrentItem
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize
                        onClicked: {
                            openCodeModelTextField.text = modelData;
                            if (page) {
                                page.setOpenCodeModelValue(modelData);
                                page.updateFilteredOpenCodeModels("");
                            }
                            openCodeModelPopup.close();
                        }
                    }
                }
            }
        }
    }

    QQC2.Label {
        visible: page ? (page.cfg_useOpenCode && page.discoveryStatus !== "") : false
        Kirigami.FormData.label: page ? page.translate("Status:") : "Status:"
        Layout.fillWidth: true
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        text: page ? page.discoveryStatus : ""
        wrapMode: Text.Wrap
        opacity: 0.8
        color: page ? ((page.discoveryStatus.indexOf("check failed") >= 0 || page.discoveryStatus.indexOf("error") >= 0 || page.discoveryStatus.indexOf("Network error") >= 0) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor) : Kirigami.Theme.textColor
    }

    QQC2.Label {
        visible: page ? (page.cfg_useOpenCode && page.runningOpenCodeSessionsVisible) : false
        Kirigami.FormData.label: page ? page.translate("Active sessions:") : "Active sessions:"
        Layout.fillWidth: true
        Layout.maximumWidth: openCodeSection.fieldMaxWidth
        wrapMode: Text.Wrap
        text: page ? page.openCodeSessionsStatus : ""
        opacity: 0.8
    }

    QQC2.ScrollView {
        id: openCodeSessionsScrollView
        visible: page ? (page.cfg_useOpenCode && page.runningOpenCodeSessionsVisible && page.runningOpenCodeSessions.length > 0) : false
        implicitHeight: Math.min(Kirigami.Units.gridUnit * 6, openCodeSessionsListView.contentHeight)
        Layout.fillWidth: true
        Layout.maximumWidth: openCodeSection.fieldMaxWidth

        background: Rectangle {
            color: Kirigami.Theme.alternateBackgroundColor
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
            border.width: 1
            radius: 4
        }

        ListView {
            id: openCodeSessionsListView
            clip: true
            model: page ? page.runningOpenCodeSessions : []
            delegate: QQC2.ItemDelegate {
                width: openCodeSessionsListView.width
                padding: Kirigami.Units.smallSpacing

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "utilities-terminal"
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                    }

                    QQC2.Label {
                        text: "ID: " + modelData.id.slice(0, 8) + "..."
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        elide: Text.ElideRight
                    }

                    QQC2.Label {
                        text: "Age: " + modelData.age
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        elide: Text.ElideRight
                    }

                    QQC2.Label {
                        text: {
                            if (!page) return "";
                            let sId = modelData.id;
                            let localSessions = page.getDatabaseSessions ? page.getDatabaseSessions() : [];
                            for (let i = 0; i < localSessions.length; i++) {
                                if (localSessions[i] && localSessions[i].openCodeSessionId === sId) {
                                    return localSessions[i].name || localSessions[i].id || "Matched";
                                }
                            }
                            return page.translate("None/External");
                        }
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                        elide: Text.ElideRight
                    }

                    QQC2.Button {
                        text: page ? page.translate("Kill") : "Kill"
                        icon.name: "edit-delete"
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                        onClicked: {
                            if (page) page.killRunningOpenCodeSession(modelData.id);
                        }
                    }
                }
            }
        }
    }

    QQC2.TextField {
        id: openCodeStartCommandField
        visible: false
    }

    QQC2.TextField {
        id: openCodeStopCommandField
        visible: false
    }

    QQC2.TextField {
        id: openCodeProviderValueField
        visible: false
        text: ""
    }

    QQC2.TextField {
        id: openCodeModelValueField
        visible: false
        text: ""
    }

    // Reference dimensions from parent/page
    readonly property real fieldMaxWidth: page ? page.fieldMaxWidth : Kirigami.Units.gridUnit * 28
}
