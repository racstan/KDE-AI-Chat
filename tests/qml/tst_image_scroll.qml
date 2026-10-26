// The chat follows a picture that finishes loading (it grows the message)
// while the user is at the end, and keeps the user's place when they scrolled up.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 500

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    // The picture's file "arrives" only when ready is set, like a job that
    // has just saved it. (The image's source binding reads `ready`.)
    QtObject {
        id: slowStore
        property bool ready: false
        property bool tall: false
        function urlFor(path) {
            return !ready ? "" : tall ? "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='300' height='600'><rect width='300' height='600' fill='%23c84'/></svg>"
                                      : Qt.resolvedUrl("../../.github/assets/image2.png");
        }
        function hasImages(m) { return !!m && (m.images || []).length > 0; }
    }

    Chat.ChatView {
        id: view
        anchors.fill: parent
        chat: chat
    }

    HarnessTestCase {
        name: "ImageScroll"

        function conversation(n) {
            var msgs = [];
            for (var i = 0; i < n; i++) {
                msgs.push({role: "user", content: "Question " + i, time: "10:00"});
                msgs.push({role: "assistant", content: "Answer " + i + "\n\nwith a second paragraph", time: "10:00"});
            }
            return msgs;
        }

        function init() {
            slowStore.ready = false;
            slowStore.tall = false;
            chat.imageStore = slowStore;
            chat.currentStreamIndex = -1;
            chat.userScrolledUp = false;
            chat.messages = [];
            wait(20);
        }

        function showImageReply() {
            chat.messages = conversation(6).concat([
                {role: "user", content: "/image a fox", time: "10:01"},
                {id: "m-img", role: "assistant", content: "", time: "10:01",
                 images: [{path: "images/s/m-img-0.png", source: "generated", prompt: "a fox", service: "AI Horde"}]}]);
            wait(80);
            chat.scrollToBottom(true);
            tryVerify(() => !view.list.builder.running, 2000, "the buttons are built");
            wait(50);
        }

        function picture() {
            var delegate = view.list.itemAtIndex(view.list.count - 1);
            verify(delegate, "the image reply is built");
            return findChild(delegate, "messageImage");
        }

        function test_follows_the_picture_at_the_end() {
            showImageReply();
            verify(view.list.atYEnd, "at the end before the picture loads");
            var before = view.list.contentHeight;
            slowStore.ready = true;
            var pic = picture();
            tryCompare(pic, "status", Image.Ready, 3000);
            wait(100);
            verify(view.list.contentHeight > before, "the picture grew the message");
            verify(view.list.atYEnd, "the chat followed the picture");
            verify(!chat.userScrolledUp);
            screenshot(root, "image-scroll-follows");
        }

        // As a real /image reply goes: the job card, then the picture is
        // attached to the reply, then the reply ends (the card goes away).
        function test_follows_a_real_reply_sequence_data() {
            return [{tag: "together", slowOrder: false}, {tag: "picture first", slowOrder: true}];
        }
        function test_follows_a_real_reply_sequence(data) {
            var slowOrder = data.slowOrder;
            chat.messages = conversation(30).concat([{role: "user", content: "/image a fox", time: "10:01"}]);
            wait(80);
            chat.scrollToBottom(true);
            wait(50);
            chat.messages = chat.messages.concat([{id: "m-img", role: "assistant", content: "", time: "10:01",
                imageJob: {service: "aihorde", name: "AI Horde", phase: "queued", queuePosition: 3, waitTime: 20}}]);
            chat.currentStreamIndex = chat.messages.length - 1;
            chat.loading = true;
            wait(100);
            verify(view.list.atYEnd, "follows the job card");
            slowStore.ready = true;
            var withPicture = chat.messages.slice();
            withPicture[withPicture.length - 1] = Object.assign({}, withPicture[withPicture.length - 1],
                {images: [{path: "images/s/m-img-0.png", source: "generated", prompt: "a fox", service: "AI Horde"}]});
            chat.messages = withPicture;
            if (slowOrder) {
                tryCompare(picture(), "status", Image.Ready, 3000);
                wait(200);
                verify(view.list.atYEnd, "followed the picture with the card still there");
            } else {
                wait(1);
            }
            var done = chat.messages.slice();
            var reply = Object.assign({}, done[done.length - 1]);
            delete reply.imageJob;
            done[done.length - 1] = reply;
            chat.currentStreamIndex = -1;
            chat.loading = false;
            chat.messages = done;
            tryCompare(picture(), "status", Image.Ready, 3000);
            wait(300);
            verify(view.list.atYEnd, "the chat followed the picture");
            verify(!chat.userScrolledUp);
        }

        // A touchpad flick down at the end, and the picture loads while the
        // list still moves (follow() waits then): the list must not decide
        // the user scrolled up when it stops short of the new end.
        function test_follows_a_picture_that_loads_during_a_flick() {
            showImageReply();
            slowStore.tall = true;
            view.list.flick(0, -4000);
            wait(30);
            verify(view.list.moving, "the flick runs");
            slowStore.ready = true;
            tryCompare(picture(), "status", Image.Ready, 3000);
            tryVerify(() => !view.list.moving, 3000, "the flick ends");
            wait(100);
            verify(!chat.userScrolledUp, "still following");
            verify(view.list.atYEnd, "at the new end");
        }

        // A flick up (away from the end) while the picture loads: the user scrolled up.
        function test_flick_up_while_the_picture_loads_stops_following() {
            showImageReply();
            slowStore.tall = true;
            view.list.flick(0, 1500);
            wait(30);
            slowStore.ready = true;
            tryCompare(picture(), "status", Image.Ready, 3000);
            tryVerify(() => !view.list.moving, 3000, "the flick ends");
            wait(100);
            verify(chat.userScrolledUp, "scrolled up");
            verify(!view.list.atYEnd);
        }

        // A new chat whose first reply is a picture: it outgrows the view.
        function test_follows_in_a_new_chat() {
            root.height = 330;
            chat.messages = [{role: "user", content: "/image a fox", time: "10:01"}];
            wait(50);
            chat.messages = chat.messages.concat([{id: "m-img", role: "assistant", content: "", time: "10:01",
                imageJob: {service: "aihorde", name: "AI Horde", phase: "queued", queuePosition: 3, waitTime: 20}}]);
            chat.currentStreamIndex = 1;
            wait(100);
            slowStore.ready = true;
            var withPicture = chat.messages.slice();
            withPicture[1] = Object.assign({}, withPicture[1], {images: [{path: "images/s/m-img-0.png", source: "generated", prompt: "a fox", service: "AI Horde"}]});
            chat.messages = withPicture;
            tryCompare(picture(), "status", Image.Ready, 3000);
            wait(200);
            verify(view.list.atYEnd, "followed the picture");
            var done = chat.messages.slice();
            var reply = Object.assign({}, done[1]);
            delete reply.imageJob;
            done[1] = reply;
            chat.currentStreamIndex = -1;
            chat.messages = done;
            wait(200);
            var atEnd = view.list.atYEnd;
            root.height = 500;
            verify(atEnd, "still at the end when the job card goes");
            verify(!chat.userScrolledUp);
        }

        function test_keeps_place_when_scrolled_up() {
            showImageReply();
            mouseWheel(view.list, 100, 100, 0, 300);
            wait(30);
            verify(chat.userScrolledUp, "scrolled up");
            var y = view.list.contentY;
            slowStore.ready = true;
            var pic = picture();
            tryCompare(pic, "status", Image.Ready, 3000);
            wait(100);
            fuzzyCompare(view.list.contentY, y, 1, "the user's place is kept");
            verify(chat.userScrolledUp);
        }
    }
}
