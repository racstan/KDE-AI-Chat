// Notifier decides when to notify. The real sender (a desktop notification)
// and the sound command are replaced by recorders: nothing leaves the test.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 200
    height: 100

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property var sent: []
    property int sounds: 0

    Chat.Notifier {
        id: notifier
        sender: function(title, text, chatId, isError) { root.sent.push({"title": title, "text": text, "chatId": chatId, "isError": isError}); }
        soundPlayer: function() { root.sounds++; }
    }

    TestCase {
        name: "Notifier"
        when: windowShown

        function init() {
            root.sent = [];
            root.sounds = 0;
            notifier.popupOpen = false;
            notifier.replyEnabled = true;
            notifier.errorEnabled = true;
            notifier.scheduledEnabled = true;
            notifier.soundEnabled = true;
        }

        function test_reply_notifies_only_when_popup_closed() {
            verify(notifier.replyFinished("c1", "Trip plan", "Here is **the plan**."));
            compare(root.sent.length, 1);
            compare(root.sent[0].title, "Trip plan");
            compare(root.sent[0].text, "Here is the plan.");
            compare(root.sent[0].chatId, "c1");
            compare(root.sent[0].isError, false);
            notifier.popupOpen = true;
            verify(!notifier.replyFinished("c1", "Trip plan", "again"));
            compare(root.sent.length, 1);
        }

        function test_reply_setting_off() {
            notifier.replyEnabled = false;
            verify(!notifier.replyFinished("c1", "T", "x"));
            compare(root.sent.length, 0);
            notifier.errorEnabled = false;
            notifier.replyEnabled = true;
            verify(notifier.replyFinished("c1", "T", "x"), "error setting does not affect replies");
        }

        function test_error_notifies_only_when_popup_closed_and_enabled() {
            verify(notifier.failed("c2", "Debugging", "HTTP 401: bad key"));
            compare(root.sent.length, 1);
            compare(root.sent[0].title, "Debugging: request failed");
            compare(root.sent[0].text, "HTTP 401: bad key");
            compare(root.sent[0].isError, true);
            notifier.popupOpen = true;
            verify(!notifier.failed("c2", "Debugging", "boom"));
            notifier.popupOpen = false;
            notifier.errorEnabled = false;
            verify(!notifier.failed("c2", "Debugging", "boom"));
            compare(root.sent.length, 1);
        }

        function test_scheduled_notifies_even_with_popup_open() {
            notifier.popupOpen = true;
            verify(notifier.scheduledRan("c3", "Morning news", "Summarise the headlines"));
            compare(root.sent.length, 1);
            compare(root.sent[0].title, "Morning news");
            compare(root.sent[0].chatId, "c3");
            notifier.scheduledEnabled = false;
            verify(!notifier.scheduledRan("c3", "Morning news", "x"));
            compare(root.sent.length, 1);
        }

        function test_sound_is_its_own_setting() {
            verify(notifier.playSound());
            compare(root.sounds, 1);
            notifier.soundEnabled = false;
            verify(!notifier.playSound());
            compare(root.sounds, 1);
            notifier.soundEnabled = true;
            notifier.popupOpen = true;
            notifier.replyEnabled = false;
            verify(notifier.playSound(), "sound does not depend on notifications");
        }

        function test_fallback_texts_and_untitled_chat() {
            notifier.replyFinished("c1", "  ", "");
            compare(root.sent[0].title, "KDE AI Chat");
            compare(root.sent[0].text, "The reply is ready.");
        }

        function test_preview_strips_markup_and_trims() {
            compare(notifier.preview("# Title\n\n- one\n- two"), "Title one two");
            compare(notifier.preview("See [docs](http://x.y) and `code`"), "See docs and code");
            compare(notifier.preview("a ```js\nlet x\n``` b"), "a b");
            var long = notifier.preview(new Array(100).join("word "), 40);
            verify(long.length <= 40, long);
            verify(long.indexOf("…") === long.length - 1);
        }
    }
}
