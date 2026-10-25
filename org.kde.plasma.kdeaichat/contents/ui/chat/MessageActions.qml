// The buttons under a message: edit (apply/cancel while editing), read
// aloud, regenerate (with longer/shorter), retry, copy, delete.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

RowLayout {
    id: actions

    property var chat: null
    property var message: ({})
    property int messageIndex: -1
    property bool streaming: false
    property bool editing: false
    // Text the user selected in this message, read aloud instead of all of it.
    property string selectedText: ""
    // True while the pointer is on the read-aloud button (clicking it clears the selection).
    readonly property bool keepSelection: (readAloud.item as PC3.ToolButton)?.hovered ?? false

    readonly property string role: message.role || ""
    readonly property bool isReply: role === "assistant" || role === "opencode_assistant"
    readonly property var voice: chat ? chat.voiceManagerRef : null
    readonly property bool speakingThis: !!voice && voice.isPlaying && chat.playingMessageIndex === messageIndex

    spacing: 0

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
    readonly property int buttonCount: 8

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

    Component {
        id: regenerateMenu
        QQC2.Menu {
            QQC2.MenuItem {
                text: i18n("Regenerate")
                icon.name: "view-refresh"
                onTriggered: actions.chat.regenerateResponse(actions.messageIndex, "")
            }
            QQC2.MenuItem {
                text: i18n("Longer")
                icon.name: "format-list-ordered"
                onTriggered: actions.chat.regenerateResponse(actions.messageIndex, "Please provide a longer, more detailed and comprehensive response.")
            }
            QQC2.MenuItem {
                text: i18n("Shorter")
                icon.name: "format-list-unordered"
                onTriggered: actions.chat.regenerateResponse(actions.messageIndex, "Please provide a shorter, more concise and brief response.")
            }
        }
    }

    Optional {
        order: 5
        shown: actions.role === "error"
        sourceComponent: Action {
            icon.name: "view-refresh"
            text: i18n("Try again")
            onClicked: actions.chat.retryFailedMessage(actions.messageIndex)
        }
    }

    Optional {
        order: 6
        sourceComponent: Action {
            enabled: !actions.streaming
            icon.name: "edit-copy"
            text: i18n("Copy")
            onClicked: actions.chat.copyTextToClipboard(actions.message.content || "")
        }
    }

    Optional {
        order: 7
        sourceComponent: Action {
            enabled: !actions.streaming
            icon.name: "edit-delete"
            text: i18n("Delete")
            onClicked: actions.chat.deleteMessage(actions.messageIndex)
        }
    }
}
