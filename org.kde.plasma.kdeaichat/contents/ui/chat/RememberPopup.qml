// "Remember" on a message (MessageActions.qml): a small editor with the
// message's text (or the part the user selected), cut to the memory limit,
// and where the memory applies: every chat (the default), this chat's
// project (only when the chat is in one) or this chat only. Save goes
// through chat.memory.remember(), and the Undo notice confirms it.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QQC2.Popup {
    id: popup
    objectName: "rememberPopup"

    property var chat: null
    property string sessionId: ""
    // The text the editor starts with.
    property string initialText: ""

    readonly property var memory: chat ? chat.memory || null : null
    readonly property int maxChars: memory ? memory.maxChars : 4000
    readonly property var project: memory ? memory.projectOf(sessionId) : null
    readonly property bool memoryOff: !!chat && !!chat.memoryStore && !chat.memoryStore.enabled
    property string scope: "all"

    function save() {
        if (memory && memory.remember(editor.text, scope, sessionId, null))
            close();
    }

    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(Kirigami.Units.gridUnit * 22, (parent ? parent.width : Kirigami.Units.gridUnit * 24) - Kirigami.Units.largeSpacing * 2)
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    padding: Kirigami.Units.largeSpacing
    onOpened: editor.forceActiveFocus()
    onClosed: destroy()

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 4
            text: i18n("Remember")
        }

        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            text: i18n("Memories go with your messages when they are relevant. Change them in Settings → Memory.")
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6
            Layout.topMargin: Kirigami.Units.smallSpacing

            PC3.TextArea {
                id: editor
                objectName: "rememberText"
                text: popup.memory ? popup.memory.clip(popup.initialText) : popup.initialText
                wrapMode: TextEdit.Wrap
                placeholderText: i18n("What should the assistant remember?")
            }
        }

        PC3.Label {
            objectName: "rememberCount"
            Layout.alignment: Qt.AlignRight
            visible: editor.length > popup.maxChars * 0.8
            text: i18n("%1 / %2", editor.length, popup.maxChars)
            font: Kirigami.Theme.smallFont
            color: editor.length > popup.maxChars ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
        }

        PC3.Label {
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: i18n("Use it in:")
        }

        PC3.RadioButton {
            objectName: "scopeAll"
            text: i18n("All chats")
            checked: popup.scope === "all"
            onToggled: popup.scope = "all"
        }
        PC3.RadioButton {
            objectName: "scopeProject"
            visible: popup.project !== null
            text: popup.project ? i18n("Chats in the project “%1”", popup.project.name) : ""
            checked: popup.scope === "project"
            onToggled: popup.scope = "project"
        }
        PC3.RadioButton {
            objectName: "scopeChat"
            text: i18n("This chat only")
            checked: popup.scope === "chat"
            onToggled: popup.scope = "chat"
        }

        PC3.Label {
            Layout.fillWidth: true
            visible: popup.memoryOff
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.neutralTextColor
            text: i18n("Memory is turned off in Settings → Memory, so it will be saved but not used yet.")
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            PC3.Button {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onClicked: popup.close()
            }
            PrimaryButton {
                objectName: "rememberSave"
                text: i18n("Save")
                icon.name: "document-save"
                enabled: editor.text.trim() !== ""
                onClicked: popup.save()
            }
        }
    }
}
