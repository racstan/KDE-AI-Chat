// A reply's text while it streams, as plain text.
//
// A TextEdit lays out and redraws all of its text on every change, so one
// TextEdit holding the whole reply gets slower with every update as the
// reply grows. Here the text is kept in pieces of about `pieceChars`,
// split at line breaks: finished pieces never change, and each update only
// sets the last one (with the simple Markdown markers hidden, see
// MessageBlocks.stripEmphasis). Stacked without spacing, the pieces look the same as
// one block of text.
pragma ComponentBehavior: Bound

import QtQuick
import "MessageBlocks.js" as MessageBlocks

Column {
    id: stream

    property var chat: null
    property int messageIndex: -1
    property string text: ""
    property int pieceChars: 1500

    // The text shown so far, and how much of it is in finished pieces.
    property string shown: ""
    property int frozenLength: 0

    function sync() {
        if (text === shown)
            return;
        if (!text.startsWith(shown)) {
            // Not a continuation (a new reply): start over.
            pieces.clear();
            frozenLength = 0;
        }
        var rest = text.substring(frozenLength);
        while (rest.length > pieceChars) {
            var cut = rest.lastIndexOf("\n", pieceChars);
            if (cut <= 0)
                cut = rest.indexOf("\n", pieceChars);
            if (cut < 0)
                break;
            pieces.append({"piece": MessageBlocks.stripEmphasis(rest.substring(0, cut))});
            frozenLength += cut + 1;
            rest = rest.substring(cut + 1);
        }
        tail.text = MessageBlocks.stripEmphasis(rest);
        shown = text;
    }

    onTextChanged: sync()
    Component.onCompleted: sync()

    ListModel {
        id: pieces
    }

    Repeater {
        model: pieces

        delegate: MessageText {
            required property string piece
            width: stream.width
            chat: stream.chat
            messageIndex: stream.messageIndex
            plain: true
            text: piece
        }
    }

    MessageText {
        id: tail
        width: stream.width
        chat: stream.chat
        messageIndex: stream.messageIndex
        plain: true
    }
}
