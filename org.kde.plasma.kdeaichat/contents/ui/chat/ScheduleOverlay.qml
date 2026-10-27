// "Schedule a message…" from the chat's ⋮ menu: the schedule editor
// (ScheduleDialog.qml) over the chat, with this chat already chosen. It
// covers the chat view until saved or cancelled. `chat` is the widget root.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import ".." as Ui
import "../config" as Config

Rectangle {
    id: overlay

    property var chat: null
    // Tests replace the helper and the network.
    property var runHelper: null
    property var xhrFactory: null
    readonly property alias dialog: editorDialog
    readonly property alias service: scheduleService

    function openForChat(chatId) {
        if (runHelper)
            scheduleService.run = runHelper;
        editorDialog.openNew(chatId);
        visible = true;
        editorDialog.editor.forceActiveFocus();
    }

    visible: false
    color: Kirigami.Theme.backgroundColor
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    // Keeps clicks and wheel events away from the chat underneath.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    Config.ScheduleService {
        id: scheduleService
    }

    QQC2.ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        contentWidth: availableWidth

        Ui.ScheduleDialog {
            id: editorDialog
            width: scroll.availableWidth
            service: scheduleService
            // No schedule can target an incognito chat (chat/Incognito.qml).
            sessions: overlay.chat ? overlay.chat.sessions.filter(function(s) { return s.incognito !== true; }) : []
            configuration: overlay.chat && overlay.chat.plasmoid ? overlay.chat.plasmoid.configuration : null
            wallet: overlay.chat ? overlay.chat.wallet : null
            xhrFactory: overlay.xhrFactory
            onClosed: overlay.visible = false
        }
    }
}
