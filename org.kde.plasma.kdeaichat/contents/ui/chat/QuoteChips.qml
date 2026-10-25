// The messages quoted for the next message ("Quote" on a message, or Ctrl+Q on
// a picked one), as removable chips above the message box: the speaker and the
// first line, cut with "…". They are kept in the order they were quoted. Not
// shown while there are none. The quotes are chat-specific, so switching to
// another chat drops them.
//
// Composer.qml owns one: add() and take() are used through it (take() when the
// message is sent: SendController.qml stores the quotes on the message, and
// MessageContent.js puts them in front of the text in every request).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "MessageContent.js" as MessageContent
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Flow {
    id: chips
    objectName: "quoteChips"

    property var chat: null
    // [{id, role, text}] (MessageContent.js), oldest first.
    property var quotes: []

    // Quotes `message`; false when it has nothing to quote, is already
    // quoted, or there are as many quotes as one message takes.
    function add(message) {
        var quote = MessageContent.makeQuote(message);
        if (!quote || chips.quotes.length >= MessageContent.MAX_QUOTES)
            return false;
        for (var i = 0; i < chips.quotes.length; i++) {
            if (quote.id !== "" && chips.quotes[i].id === quote.id)
                return false;
        }
        chips.quotes = chips.quotes.concat([quote]);
        return true;
    }

    function remove(index) {
        var copy = chips.quotes.slice();
        copy.splice(index, 1);
        chips.quotes = copy;
    }

    // The quotes, for the message being sent; the chips go away.
    function take() {
        var taken = chips.quotes;
        chips.quotes = [];
        return taken;
    }

    visible: quotes.length > 0
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Connections {
        target: chips.chat
        function onCurrentSessionIdChanged() {
            chips.quotes = [];
        }
    }

    Repeater {
        model: chips.quotes

        delegate: Rectangle {
            id: chip

            required property var modelData
            required property int index

            objectName: "quoteChip"
            readonly property string speaker: modelData.role === "assistant" ? i18n("Assistant") : i18n("You")
            readonly property string firstLine: MessageContent.quoteFirstLine(modelData.text)

            width: Math.min(chips.width, label.implicitWidth + closeButton.width + Kirigami.Units.smallSpacing * 4)
            height: Kirigami.Units.gridUnit * 1.6
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)

            Rectangle {
                width: Kirigami.Units.smallSpacing / 2 + 1
                height: parent.height - Kirigami.Units.smallSpacing
                anchors.left: parent.left
                anchors.leftMargin: 1
                anchors.verticalCenter: parent.verticalCenter
                radius: width / 2
                color: Kirigami.Theme.highlightColor
            }

            PC3.Label {
                id: label
                objectName: "quoteChipText"
                anchors.left: parent.left
                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                anchors.right: closeButton.left
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
                text: chip.speaker + " · " + chip.firstLine
                Accessible.name: i18n("Quoted from %1: %2", chip.speaker, chip.firstLine)
            }

            PC3.ToolButton {
                id: closeButton
                objectName: "quoteChipRemove"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.smallMedium
                height: Kirigami.Units.iconSizes.smallMedium
                icon.name: "dialog-close"
                display: PC3.AbstractButton.IconOnly
                Accessible.name: i18n("Remove quote")
                onClicked: chips.remove(chip.index)
            }
        }
    }
}
