// Second screen of the first-run setup: the key (online services and servers
// that ask for one), then a model from the provider's own list.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: keyStep

    // The FirstRun.qml that owns the state.
    property var ctl: null

    spacing: Kirigami.Units.smallSpacing

    Kirigami.Heading {
        level: 4
        text: i18n("Connect to %1", keyStep.ctl.choice ? keyStep.ctl.choice.name : "")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: keyStep.ctl.choice && keyStep.ctl.choice.server
            ? i18n("This program asks for a key. Paste it here; it is kept in KWallet, not in a file.")
            : i18n("Paste your key here. It is kept in KWallet, not in a file, and only sent to %1.", keyStep.ctl.choice ? keyStep.ctl.choice.name : "")
    }

    QQC2.Label {
        objectName: "getKeyLink"
        visible: !!keyStep.ctl.choice && keyStep.ctl.choice.keyUrl !== ""
        Layout.fillWidth: true
        linkColor: Kirigami.Theme.linkColor
        textFormat: Text.StyledText
        text: keyStep.ctl.choice ? "<a href=\"" + keyStep.ctl.choice.keyUrl + "\">" + i18n("Get a key") + "</a>" : ""
        onLinkActivated: link => Qt.openUrlExternally(link)
        Accessible.role: Accessible.Link
        Accessible.name: i18n("Get a key")
    }

    Kirigami.PasswordField {
        id: keyField
        objectName: "firstRunKey"
        Layout.fillWidth: true
        placeholderText: i18n("API key")
        enabled: !keyStep.ctl.busy
        onTextChanged: keyStep.ctl.keyText = text
        onAccepted: keyStep.ctl.modelsReady ? keyStep.ctl.saveModel() : keyStep.ctl.checkKey()
        Accessible.name: i18n("API key")
        Component.onCompleted: forceActiveFocus()
    }

    QQC2.ComboBox {
        id: modelBox
        objectName: "firstRunModel"
        visible: keyStep.ctl.modelsReady
        Layout.fillWidth: true
        model: keyStep.ctl.models
        enabled: !keyStep.ctl.busy
        onActivated: keyStep.ctl.model = currentText
        Accessible.name: i18n("Model")
        Connections {
            target: keyStep.ctl
            function onModelsChanged() { modelBox.currentIndex = modelBox.find(keyStep.ctl.model); }
            function onModelChanged() { modelBox.currentIndex = modelBox.find(keyStep.ctl.model); }
        }
    }

    QQC2.Label {
        objectName: "firstRunStatus"
        visible: keyStep.ctl.status !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: keyStep.ctl.statusKind === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        text: keyStep.ctl.status
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            objectName: "firstRunBack"
            text: i18n("Back")
            icon.name: "go-previous"
            enabled: !keyStep.ctl.busy
            onClicked: keyStep.ctl.back()
        }

        Item {
            Layout.fillWidth: true
        }

        QQC2.BusyIndicator {
            visible: keyStep.ctl.busy
            running: keyStep.ctl.busy
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
        }

        QQC2.Button {
            objectName: "firstRunContinue"
            highlighted: true
            text: keyStep.ctl.modelsReady ? i18n("Save and continue") : i18n("Check key")
            enabled: !keyStep.ctl.busy && keyStep.ctl.keyText.trim() !== ""
            onClicked: keyStep.ctl.modelsReady ? keyStep.ctl.saveModel() : keyStep.ctl.checkKey()
        }
    }
}
