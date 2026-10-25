// The buttons under a message: edit (apply/cancel while editing), read
// aloud, regenerate (with longer/shorter), copy, delete.
//
// They show while the message is hovered (`hovered`, from its delegate) or
// has keyboard focus, and never while it streams. They stay in the layout
// (opacity, not visible), so they take no room twice and can be reached by
// Tab; the delegate keeps their height free so nothing moves.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

RowLayout {
    id: actions
    objectName: "messageActions"

    property var chat: null
    property var message: ({})
    property int messageIndex: -1
    property bool streaming: false
    property bool editing: false
    // Text the user selected in this message, read aloud instead of all of it.
    property string selectedText: ""
    // The pointer is over the message.
    property bool hovered: false
    // Keyboard focus is on one of the buttons.
    readonly property Item focusItem: Window.window ? Window.window.activeFocusItem : null
    readonly property bool focusWithin: {
        var item = focusItem;
        while (item) {
            if (item === actions)
                return true;
            item = item.parent;
        }
        return false;
    }
    readonly property bool shown: !streaming && (hovered || focusWithin || editing)
    // True while the pointer is on the read-aloud button (clicking it clears the selection).
    readonly property bool keepSelection: (readAloud.item as PC3.ToolButton)?.hovered ?? false

    readonly property string role: message.role || ""
    readonly property bool isReply: role === "assistant" || role === "opencode_assistant"
    readonly property var voice: chat ? chat.voiceManagerRef : null
    readonly property bool speakingThis: !!voice && voice.isPlaying && chat.playingMessageIndex === messageIndex

    spacing: 0
    opacity: shown ? 1 : 0
    enabled: !streaming

    Behavior on opacity {
        NumberAnimation {
            duration: Kirigami.Units.shortDuration
        }
    }

    component Action: PC3.ToolButton {
        display: PC3.AbstractButton.IconOnly
        Accessible.name: text
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: text
    }

    // A Plasma ToolButton takes a few ms to build and every message has a
    // row of them, so each button is built only if the message shows it,
    // and, with a `builder` (chat/DeferredBuilder.qml), one at a time after
    // the first frame instead of all while the chat opens.
    property var builder: null
    property int built: builder ? 0 : buttonCount
    readonly property int buttonCount: 7

    // Builds the next button; false once all are built.
    function buildStep() {
        built++;
        return built < buttonCount;
    }
    Component.onCompleted: if (builder) builder.add(actions)
    Component.onDestruction: if (builder) builder.remove(actions)

    component Optional: Loader {
        property int order: 0
        property bool shown: true
        active: shown && actions.built > order
        visible: active
    }

    Optional {
        order: 0
        shown: !actions.editing && actions.role !== "error"
        sourceComponent: Action {
            enabled: !actions.streaming
            icon.name: "document-edit"
            text: i18n("Edit")
            onClicked: {
                actions.chat.editingMessageIndex = actions.messageIndex;
                actions.chat.editingDraft = actions.message.content || "";
            }
        }
    }

    Optional {
        order: 1
        shown: actions.editing
        sourceComponent: Action {
            icon.name: "dialog-ok-apply"
            text: i18n("Save edit")
            onClicked: actions.chat.saveEditedMessage()
        }
    }

    Optional {
        order: 2
        shown: actions.editing
        sourceComponent: Action {
            icon.name: "dialog-cancel"
            text: i18n("Cancel edit")
            onClicked: {
                actions.chat.editingMessageIndex = -1;
                actions.chat.editingDraft = "";
            }
        }
    }

    Optional {
        id: readAloud
        order: 3
        shown: !!actions.chat && actions.chat.voiceEnabled && actions.chat.voiceTtsEnabled && actions.role !== "error"
        sourceComponent: Action {
            enabled: !actions.streaming
            icon.name: actions.speakingThis ? "media-playback-stop" : "audio-speakers"
            text: actions.speakingThis ? i18n("Stop reading") : actions.selectedText.trim() ? i18n("Read selection aloud") : i18n("Read aloud")
            onClicked: {
                if (!actions.voice)
                    return;
                var wasThis = actions.speakingThis;
                if (actions.voice.isPlaying)
                    actions.voice.stopTTS();
                if (wasThis) {
                    actions.chat.playingMessageIndex = -1;
                    return;
                }
                actions.chat.playingMessageIndex = actions.messageIndex;
                actions.voice.playTTS(actions.selectedText.trim() ? actions.selectedText : actions.message.content);
            }
        }
    }

    Optional {
        order: 4
        shown: actions.isReply
        sourceComponent: Action {
            id: regenerate
            enabled: !actions.streaming
            icon.name: "view-refresh"
            text: i18n("Regenerate")
            onClicked: {
                var menu = regenerateMenu.createObject(regenerate) as QQC2.Menu;
                menu.closed.connect(menu.destroy);
                menu.popup(regenerate, 0, regenerate.height);
            }
        }
    }

    // Regenerating drops this reply and every message after it.
    readonly property int laterMessages: chat && chat.messages ? Math.max(0, chat.messages.length - messageIndex - 1) : 0

    function regenerate(modifier) {
        if (laterMessages > 0)
            confirmDrop.createObject(actions, {"modifier": modifier}).open();
        else
            chat.regenerateResponse(messageIndex, modifier);
    }

    Component {
        id: confirmDrop
        QQC2.Popup {
            id: confirm
            property string modifier: ""
            objectName: "regenerateConfirm"
            parent: QQC2.Overlay.overlay
            anchors.centerIn: parent
            modal: true
            focus: true
            closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
            padding: Kirigami.Units.largeSpacing
            onClosed: destroy()

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.largeSpacing

                PC3.Label {
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                    wrapMode: Text.Wrap
                    text: i18np("Regenerating removes this reply and the %1 message after it.", "Regenerating removes this reply and the %1 messages after it.", actions.laterMessages)
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: Kirigami.Units.smallSpacing

                    PC3.Button {
                        text: i18n("Cancel")
                        icon.name: "dialog-cancel"
                        onClicked: confirm.close()
                    }

                    PrimaryButton {
                        objectName: "regenerateConfirmButton"
                        text: i18n("Regenerate")
                        icon.name: "view-refresh"
                        onClicked: {
                            confirm.close();
                            actions.chat.regenerateResponse(actions.messageIndex, confirm.modifier);
                        }
                    }
                }
            }
        }
    }

    Component {
        id: regenerateMenu
        QQC2.Menu {
            QQC2.MenuItem {
                text: i18n("Regenerate")
                icon.name: "view-refresh"
                onTriggered: actions.regenerate("")
            }
            QQC2.MenuItem {
                text: i18n("Longer")
                icon.name: "format-list-ordered"
                onTriggered: actions.regenerate("Please provide a longer, more detailed and comprehensive response.")
            }
            QQC2.MenuItem {
                text: i18n("Shorter")
                icon.name: "format-list-unordered"
                onTriggered: actions.regenerate("Please provide a shorter, more concise and brief response.")
            }
        }
    }

    Optional {
        order: 5
        sourceComponent: Action {
            enabled: !actions.streaming
            icon.name: "edit-copy"
            text: i18n("Copy")
            onClicked: actions.chat.copyTextToClipboard(actions.message.content || "")
        }
    }

    Optional {
        order: 6
        sourceComponent: Action {
            enabled: !actions.streaming
            icon.name: "trash-empty"
            text: i18n("Delete")
            onClicked: actions.chat.deleteMessage(actions.messageIndex)
        }
    }
}
