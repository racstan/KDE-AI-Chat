// Read aloud in the chat, through the real VoiceManager with Qt's mock speech
// engine as System voices: a partial selection reads only that part (button,
// right-click menu and Ctrl+Shift+S), the selection survives clicking the
// button, the shortcut reads the composer's selection or the picked message
// and stops when reading, the button is hidden while read aloud is off, and
// an engine failure is reported through errorOccurred. The words being read
// glow (chat/SpokenGlow.qml) and move along, without touching the selection.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 560
    height: 640

    property QtObject plasmoid: QtObject {
        property QtObject configuration: QtObject {
            // Dictation "on" here only so the manager doesn't run its
            // stop-the-dictation-service command at start.
            property bool sttEnabled: true
            property bool voiceTtsEnabled: true
            property bool voiceTtsAuto: false
            property bool voiceAutoSend: true
            property string voiceTtsEngine: "system"
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    Ui.VoiceManager {
        id: voice
        ttsPluginOverride: ({"system": "mock"})
    }

    FakeChat {
        id: chat
        voiceManagerRef: voice
        voiceTtsEnabled: true
    }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    Chat.ChatView {
        id: view
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 440
        chat: chat
    }

    Chat.Composer {
        id: composer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        chat: chat
    }

    Chat.ChatShortcuts {
        chat: chat
    }

    SignalSpy {
        id: errors
        target: voice
        signalName: "errorOccurred"
    }

    HarnessTestCase {
        name: "ReadAloudChat"

        readonly property string reply: "The first sentence is here. The second sentence is longer and comes after it."

        function init() {
            voice.stopTTS();
            voice.ttsPluginOverride = {"system": "mock"};
            chat.voiceTtsEnabled = true;
            chat.playingMessageIndex = -1;
            chat.messages = [{role: "user", content: "Read this?", time: "10:00"},
                             {role: "assistant", model: "m", content: reply, time: "10:00"}];
            view.list.clearSelection();
            errors.clear();
            wait(100);
        }

        function textBlockOf(index) {
            var delegate = view.list.itemAtIndex(index);
            verify(delegate, "delegate " + index);
            var block = null;
            tryVerify(function() {
                (function walk(item) {
                    if (block || !item) return;
                    if (item.objectName === "messageText" && item.length > 0) { block = item; return; }
                    for (var i = 0; i < item.children.length; i++) walk(item.children[i]);
                })(delegate);
                return block !== null;
            }, 3000, "message text of " + index);
            return block;
        }
        function readButtonOf(index) {
            var actions = findChild(view.list.itemAtIndex(index), "messageActions");
            tryCompare(actions, "built", actions.buttonCount, 3000);
            var button = null;
            (function walk(item) {
                if (button || !item) return;
                if (item.text === "Read aloud" || item.text === "Read selection aloud" || item.text === "Stop reading") { button = item; return; }
                for (var i = 0; i < item.children.length; i++) walk(item.children[i]);
            })(actions);
            return button;
        }
        function selectWords(block, words) {
            var shown = block.getText(0, block.length);
            var at = shown.indexOf(words);
            verify(at >= 0, words + " in " + shown);
            block.forceActiveFocus();
            block.select(at, at + words.length);
            compare(block.selectedText, words);
        }

        function test_partial_selection_reads_only_that_part() {
            var block = textBlockOf(1);
            selectWords(block, "second sentence is longer");
            var delegate = view.list.itemAtIndex(1);
            mouseMove(delegate, delegate.width / 2, 10);
            var button = readButtonOf(1);
            compare(button.text, "Read selection aloud");
            mouseMove(button, button.width / 2, button.height / 2);
            mouseClick(button);
            verify(voice.isPlaying);
            compare(voice.playingText, "second sentence is longer");
            tryCompare(voice, "currentPlayingChunk", "second sentence is longer", 3000);
            compare(chat.playingMessageIndex, 1);
            compare(block.selectedText, "second sentence is longer", "the selection survives the click");
            compare(button.text, "Stop reading");
            mouseClick(button);
            verify(!voice.isPlaying);
            compare(block.selectedText, "second sentence is longer");
        }

        function test_whole_message_without_a_selection() {
            var delegate = view.list.itemAtIndex(1);
            mouseMove(delegate, delegate.width / 2, 10);
            var button = readButtonOf(1);
            compare(button.text, "Read aloud");
            mouseClick(button);
            compare(voice.playingText, reply);
            tryVerify(function() { return !voice.isPlaying; }, 15000, "finishes by itself");
            compare(voice.playingText, "");
        }

        function test_context_menu_reads_the_selection() {
            var block = textBlockOf(1);
            selectWords(block, "first sentence");
            mouseClick(block, 20, 5, Qt.RightButton);
            var menu = null;
            tryVerify(function() { return (menu = block.openMenu) !== null; }, 2000, "the menu opens");
            var item = null;
            for (var i = 0; i < menu.count; i++)
                if (menu.itemAt(i).objectName === "readAloudItem") item = menu.itemAt(i);
            verify(item, "Read aloud is in the menu");
            compare(item.text, "Read selection aloud");
            wait(300);
            screenshot(root.Window.window.contentItem, "read-aloud-context-menu");
            item.triggered();
            menu.close();
            compare(voice.playingText, "first sentence");
            compare(block.selectedText, "first sentence");
            voice.stopTTS();
        }

        function test_shortcut_reads_composer_selection_then_stops() {
            composer.input.text = "Typed words to hear";
            composer.input.forceActiveFocus();
            composer.input.select(6, 11);
            keyClick(Qt.Key_S, Qt.ControlModifier | Qt.ShiftModifier);
            verify(voice.isPlaying);
            compare(voice.playingText, "words");
            keyClick(Qt.Key_S, Qt.ControlModifier | Qt.ShiftModifier);
            verify(!voice.isPlaying, "the shortcut stops reading");
        }

        function test_shortcut_reads_message_selection_or_picked_message() {
            var block = textBlockOf(1);
            selectWords(block, "comes after it");
            keyClick(Qt.Key_S, Qt.ControlModifier | Qt.ShiftModifier);
            compare(voice.playingText, "comes after it");
            compare(chat.playingMessageIndex, 1);
            keyClick(Qt.Key_S, Qt.ControlModifier | Qt.ShiftModifier);
            block.deselect();
            view.list.select(0);
            view.list.forceActiveFocus();
            keyClick(Qt.Key_S, Qt.ControlModifier | Qt.ShiftModifier);
            compare(voice.playingText, "Read this?");
            compare(chat.playingMessageIndex, 0);
            voice.stopTTS();
        }

        function test_hidden_when_read_aloud_is_off() {
            chat.voiceTtsEnabled = false;
            wait(50);
            compare(readButtonOf(1), null);
            keyClick(Qt.Key_S, Qt.ControlModifier | Qt.ShiftModifier);
            verify(!voice.isPlaying);
        }

        function test_engine_failure_is_reported() {
            voice.ttsPluginOverride = {"system": "no-such-engine"};
            voice.playTTS("Hello");
            tryCompare(errors, "count", 1, 3000);
            verify(!voice.isPlaying);
        }

        function test_the_words_being_read_glow_and_move_along() {
            var block = textBlockOf(1);
            var glow = findChild(block, "spokenGlow");
            verify(glow !== null);
            verify(!glow.shown, "nothing glows before reading");
            chat.playingMessageIndex = 1;
            voice.playTTS(reply);
            var sentences = {};
            var words = {};
            tryVerify(function() {
                if (glow._sentence)
                    sentences[block.getText(glow._sentence.start, glow._sentence.end)] = true;
                if (glow.wordRects.length > 0)
                    words[voice.currentPlayingWordStart] = true;
                if (glow.shown && Object.keys(words).length === 3)
                    screenshot(root, "read-aloud-glow");
                return !voice.isPlaying;
            }, 15000, "reads to the end");
            verify(sentences["The first sentence is here."], JSON.stringify(sentences));
            verify(sentences["The second sentence is longer and comes after it."], JSON.stringify(sentences));
            verify(Object.keys(words).length > 5, "the word being said moves along: " + JSON.stringify(words));
            compare(block.selectedText, "", "the glow is not a selection");
            tryVerify(function() { return !glow.shown; }, 1000, "gone when reading ends");
        }
    }
}
