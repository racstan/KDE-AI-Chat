// One block of message text, rendered as Markdown (or plain while a reply
// streams). Selectable; links open only after Security.js validates them.
// While this message is read aloud, the words being spoken are selected.
// Right-click opens Copy / Read aloud.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../Security.js" as Sec
import "ReadAloudAction.js" as ReadAloudAction
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

TextEdit {
    id: block
    objectName: "messageText"

    property var chat: null
    property int messageIndex: -1
    property bool plain: false
    // Your messages are right-aligned.
    property bool alignRight: false

    // The user's selection, for "Read selected text".
    signal selectionMade(string text)

    readOnly: true
    cursorVisible: false
    selectByMouse: true
    persistentSelection: true
    wrapMode: Text.Wrap
    horizontalAlignment: alignRight ? Text.AlignRight : Text.AlignLeft
    textFormat: plain ? Text.PlainText : Text.MarkdownText
    // Links take the colour scheme's link colour: TextEdit has no linkColor,
    // its Markdown importer uses the application palette, which Plasma sets
    // from the colour scheme.
    color: Kirigami.Theme.textColor
    selectedTextColor: Kirigami.Theme.highlightedTextColor
    selectionColor: Kirigami.Theme.highlightColor
    // The theme's font, at the text size from Settings → Appearance.
    font: chat && chat.prefs ? chat.prefs.scaledFont(Kirigami.Theme.defaultFont) : Kirigami.Theme.defaultFont

    onLinkActivated: function(link) {
        var safe = Sec.validateUrl(link);
        if (safe)
            Qt.openUrlExternally(safe);
    }
    // The selection is the user's, unless _spoken: the words being read
    // aloud, selected by highlightSpoken(), which is not reported.
    property bool _spoken: false
    property bool _highlighting: false
    onSelectedTextChanged: {
        if (_highlighting)
            return;
        _spoken = false;
        selectionMade(selectedText);
    }

    function _selectQuietly(start, end) {
        _highlighting = true;
        if (end > start)
            block.select(start, end);
        else
            block.deselect();
        _highlighting = false;
    }

    // Finds the spoken words in the text as displayed (not the Markdown
    // source, whose positions differ) and selects them. A selection of the
    // user's stays as it is (it is what's being read).
    function highlightSpoken(chunk) {
        if (block.selectedText !== "" && !_spoken)
            return;
        var shown = block.getText(0, block.length);
        var words = String(chunk || "").replace(/[^\w\s]/g, " ").trim().split(/\s+/).filter(function(w) { return w.length > 0; });
        if (words.length === 0)
            return;
        var pattern = words.map(function(w) { return w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }).join("[^A-Za-z0-9]*?");
        var match = new RegExp(pattern, "i").exec(shown);
        if (match) {
            _selectQuietly(match.index, match.index + match[0].length);
            _spoken = true;
        }
    }

    // Right-click: Copy and Read aloud (the selection, or the whole message).
    property QQC2.Menu openMenu: null
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: function(eventPoint) {
            var menu = contextMenu.createObject(block) as QQC2.Menu;
            block.openMenu = menu;
            menu.closed.connect(function() { block.openMenu = null; menu.destroy(); });
            menu.popup(block, eventPoint.position.x, eventPoint.position.y);
        }
    }

    Component {
        id: contextMenu
        QQC2.Menu {
            id: textMenu
            objectName: "messageTextMenu"
            readonly property var voice: block.chat ? block.chat.voiceManagerRef : null
            readonly property bool readingThis: !!voice && voice.isPlaying && block.chat.playingMessageIndex === block.messageIndex
            QQC2.MenuItem {
                text: i18n("Copy")
                icon.name: "edit-copy"
                enabled: block.selectedText !== ""
                onTriggered: block.copy()
            }
            QQC2.MenuItem {
                objectName: "readAloudItem"
                visible: !!block.chat && block.chat.voiceTtsEnabled === true
                height: visible ? implicitHeight : 0
                text: textMenu.readingThis ? i18n("Stop reading")
                    : block.selectedText.trim() ? i18n("Read selection aloud") : i18n("Read aloud")
                icon.name: textMenu.readingThis ? "media-playback-stop" : "audio-speakers"
                onTriggered: block.readAloud()
            }
        }
    }

    function readAloud() {
        var message = block.chat && block.chat.messages ? block.chat.messages[block.messageIndex] : null;
        ReadAloudAction.toggle(block.chat, block.messageIndex,
                               block.selectedText.trim() ? block.selectedText : (message ? message.content : block.text));
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
            if (!block.chat.voiceManagerRef.isPlaying && block._spoken) {
                block._selectQuietly(0, 0);
                block._spoken = false;
            }
        }
    }
}
