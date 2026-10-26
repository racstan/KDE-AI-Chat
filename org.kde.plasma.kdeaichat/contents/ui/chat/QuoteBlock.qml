// The messages a message quoted, as small blocks above its text: who said it
// and the start of what was said (at most three lines). Clicking one jumps to
// the original message and picks it (ChatView.jumpToMessage), if it is still
// in the chat; the tip says when it is gone.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "Personality.js" as Personality
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: block
    objectName: "quoteBlock"

    property var chat: null
    // Speaker names from Settings → Personality (Personality.js); empty = You / Assistant.
    readonly property var _cfg: chat && chat.plasmoid ? chat.plasmoid.configuration : ({})
    readonly property string userName: Personality.userLabel(_cfg) || i18n("You")
    readonly property string aiName: Personality.aiLabel(_cfg) || i18n("Assistant")
    // [{id, role, text}] (MessageContent.js).
    property var quotes: []

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: block.quotes

        delegate: Rectangle {
            id: quote

            required property var modelData

            objectName: "quote"
            // Whether the quoted message is still in the chat; looked up when the
            // pointer arrives (not for every quote of a chat that is opening).
            property bool original: false
            function stillThere() {
                return !!block.chat && quote.modelData.id !== ""
                    && block.chat.messageModel.indexOfKey(String(quote.modelData.id)) >= 0;
            }

            Layout.fillWidth: true
            implicitHeight: quoteColumn.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, mouse.containsMouse && quote.original ? 0.1 : 0.05)

            Rectangle {
                width: Kirigami.Units.smallSpacing / 2 + 1
                height: parent.height - Kirigami.Units.smallSpacing
                anchors.left: parent.left
                anchors.leftMargin: 1
                anchors.verticalCenter: parent.verticalCenter
                radius: width / 2
                color: Kirigami.Theme.highlightColor
            }

            ColumnLayout {
                id: quoteColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Kirigami.Units.smallSpacing * 2 + 2
                anchors.rightMargin: Kirigami.Units.smallSpacing
                anchors.topMargin: Kirigami.Units.smallSpacing
                spacing: 0

                PC3.Label {
                    objectName: "quoteSpeaker"
                    Layout.fillWidth: true
                    text: quote.modelData.role === "assistant" ? block.aiName : block.userName
                    font.bold: true
                    elide: Text.ElideRight
                    opacity: 0.8
                }

                PC3.Label {
                    objectName: "quoteText"
                    Layout.fillWidth: true
                    text: quote.modelData.text
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    opacity: 0.75
                }
            }

            MouseArea {
                id: mouse
                objectName: "quoteArea"
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: quote.original ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: quote.original = quote.stillThere()
                onClicked: {
                    var list = block.chat ? block.chat.msgListViewRef : null;
                    if (list && list.jumpToMessage)
                        list.jumpToMessage(quote.modelData.id);
                }

                QQC2.ToolTip {
                    visible: mouse.containsMouse
                    delay: Kirigami.Units.toolTipDelay
                    text: quote.original ? i18n("Go to the original message") : i18n("The original message is no longer in this chat")
                }
            }
        }
    }
}
