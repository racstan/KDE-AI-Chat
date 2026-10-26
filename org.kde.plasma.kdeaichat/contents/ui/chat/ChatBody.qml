// Everything under the header: the conversation with its composer, and the
// history. `chat.historyOnlyMode` is the history toggle. In a wide popup the
// history slides in beside the chat; in a narrow one it takes the whole view
// until a chat is chosen.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: body

    property var chat: null
    // Room to keep free in the bottom corners for the popup's resize grip
    // (chat/ResizeHandle.qml): the composer and the history end short of it.
    property real roomBottomLeft: 0
    property real roomBottomRight: 0

    // From this width the history sits beside the chat.
    readonly property real sideThreshold: Kirigami.Units.gridUnit * 40
    // The side panel: wider in a wide popup, so titles fit, but never more
    // than about a third of it (at least 15 grid units).
    readonly property real panelWidth: Math.round(Math.max(Kirigami.Units.gridUnit * 15, Math.min(Kirigami.Units.gridUnit * 20, width * 0.28)))
    readonly property bool sideHistory: width >= sideThreshold
    readonly property bool historyOpen: chat.historyOnlyMode
    // The history replaces the chat (narrow popup).
    readonly property bool historyFull: historyOpen && !sideHistory
    readonly property alias chatView: view
    readonly property alias composerItem: composer
    readonly property alias historyPane: pane
    // The SessionList, while it exists.
    readonly property var sessionList: historyLoader.item

    signal attachRequested()
    signal chatInfoRequested()

    readonly property alias projectEditor: editor

    // Creating and editing projects, from the history or any chat's menu.
    ProjectEditor {
        id: editor
        chat: body.chat
    }

    // Tells the chat that the history sits beside it, so New chat leaves it open.
    Binding {
        target: body.chat
        property: "historySidePanel"
        value: body.sideHistory
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            id: pane

            // The width the history is shown at: nothing, the side panel, or all of it.
            readonly property real shownWidth: !body.historyOpen ? 0 : (body.sideHistory ? body.panelWidth + Kirigami.Units.smallSpacing : body.width)

            Layout.fillHeight: true
            Layout.preferredWidth: shownWidth
            visible: shownWidth > 0 || width > 0
            clip: true

            Behavior on Layout.preferredWidth {
                enabled: body.sideHistory
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }

            Loader {
                id: historyLoader

                // Stays until the slide-out has finished.
                active: body.historyOpen || pane.width > 0
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: body.historyFull ? pane.width : body.panelWidth

                sourceComponent: Component {
                    SessionList {
                        chat: body.chat
                        closeOnSelect: body.historyFull
                        bottomRoom: body.historyFull ? Math.max(body.roomBottomLeft, body.roomBottomRight) : body.roomBottomLeft
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !body.historyFull
            spacing: Kirigami.Units.smallSpacing

            // The chat's mode (OpenCode / Pi) can't be used right now; the chat stays in it.
            NoticeBanner {
                objectName: "modeNotice"
                isError: true
                dismissible: true
                text: body.chat.modeNotice || ""
                onDismissed: body.chat.modeNotice = ""
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Kirigami.Units.cornerRadius
                color: Kirigami.Theme.alternateBackgroundColor
                clip: true

                ChatView {
                    id: view
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    visible: !body.historyFull
                    chat: body.chat
                }
            }

            Composer {
                id: composer
                Layout.leftMargin: pane.shownWidth > 0 ? 0 : body.roomBottomLeft
                Layout.rightMargin: body.roomBottomRight
                chat: body.chat
                onAttachRequested: body.attachRequested()
                onChatInfoRequested: body.chatInfoRequested()
            }
        }
    }
}
