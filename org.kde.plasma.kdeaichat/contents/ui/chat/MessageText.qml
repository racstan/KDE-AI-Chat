// One block of message text, rendered as Markdown (or plain while a reply
// streams). Selectable; links open only after Security.js validates them.
// While this message is read aloud, the words being spoken are selected.
import QtQuick
import org.kde.kirigami as Kirigami
import "../Security.js" as Sec

TextEdit {
    id: block

    property var chat: null
    property int messageIndex: -1
    property bool plain: false
    property bool isError: false

    // The user's selection, for "Read selected text".
    signal selectionMade(string text)

    readOnly: true
    cursorVisible: false
    selectByMouse: true
    persistentSelection: true
    wrapMode: Text.Wrap
    textFormat: plain ? Text.PlainText : Text.MarkdownText
    color: isError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
    selectedTextColor: Kirigami.Theme.highlightedTextColor
    selectionColor: Kirigami.Theme.highlightColor
    font: Kirigami.Theme.defaultFont

    onLinkActivated: function(link) {
        var safe = Sec.validateUrl(link);
        if (safe)
            Qt.openUrlExternally(safe);
    }
    onSelectedTextChanged: selectionMade(selectedText)

    // Finds the spoken words in the text as displayed (not the Markdown
    // source, whose positions differ) and selects them.
    function highlightSpoken(chunk) {
        var shown = block.getText(0, block.length);
        var words = String(chunk || "").replace(/[^\w\s]/g, " ").trim().split(/\s+/).filter(function(w) { return w.length > 0; });
        if (words.length === 0)
            return;
        var pattern = words.map(function(w) { return w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }).join("[^A-Za-z0-9]*?");
        var match = new RegExp(pattern, "i").exec(shown);
        if (match)
            block.select(match.index, match.index + match[0].length);
    }

    Connections {
        target: block.chat ? block.chat.voiceManagerRef : null
        ignoreUnknownSignals: true

        function onCurrentPlayingChunkChanged() {
            var voice = block.chat.voiceManagerRef;
            if (voice.isPlaying && block.chat.playingMessageIndex === block.messageIndex)
                block.highlightSpoken(voice.currentPlayingChunk);
        }

        function onIsPlayingChanged() {
            if (!block.chat.voiceManagerRef.isPlaying)
                block.deselect();
        }
    }
}
