// Pictures in messages: the image block (enlarge, Copy image, Download, Regenerate,
// click-to-load links), and chat/ImageStore.qml (saving through the helper, keeping only
// paths in the message, removing files with the message). No network and no real helper.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 560
    height: 700

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

    // A stand-in for chat/ImageStore.qml that records what the buttons ask for.
    QtObject {
        id: fakeStore
        property var calls: []
        property bool copyWorks: true
        property var pending: null
        function urlFor(path) { return Qt.resolvedUrl("../../.github/assets/image1.png"); }
        function copyImage(path, done) {
            calls = calls.concat([{name: "copy", path: path}]);
            done(copyWorks, copyWorks ? "wl-copy" : "Copying an image needs wl-clipboard (Wayland) or xclip (X11). Install one of them, or use Download.");
        }
        function exportImage(path, dest, done) { calls = calls.concat([{name: "export", path: path, dest: dest}]); done(true, dest); }
        function loadLink(sessionId, messageId, linkIndex, link, done) {
            calls = calls.concat([{name: "loadLink", sessionId: sessionId, messageId: messageId, index: linkIndex, url: link.url}]);
            pending = done;
        }
        function regenerate(messageId, index) { calls = calls.concat([{name: "regenerate", messageId: messageId, index: index}]); }
        function hasImages(m) { return !!m && (m.images || []).length > 0; }
    }

    Chat.ChatView {
        id: view
        anchors.fill: parent
        chat: chat
    }

    HarnessTestCase {
        name: "MessageImages"

        readonly property var generated: {
            "path": "images/s-1/m-gen-0.webp", "mime": "image/webp", "bytes": 4100, "source": "generated", "prompt": "a red fox in the snow",
            "service": "AI Horde", "model": "Deliberate", "width": 512, "height": 512, "seed": "77"
        }
        readonly property var fromModel: {"path": "images/s-1/m-gen-1.png", "mime": "image/png", "bytes": 900, "source": "model", "model": "google/gemini-2.5-flash-image"}

        function init() {
            chat.calls = [];
            fakeStore.calls = [];
            fakeStore.copyWorks = true;
            chat.imageStore = fakeStore;
            chat.currentStreamIndex = -1;
            chat.messages = [];
            wait(20);
        }

        function show(message) {
            chat.messages = [{role: "user", content: "/image a red fox", time: "10:00"}, message];
            wait(80);
            var delegate = view.list.itemAtIndex(1);
            verify(delegate, "delegate");
            return delegate;
        }

        // The open viewer's item with this objectName (older, closed ones may still exist), or null.
        function inViewer(name) {
            var all = findChildren(QQC2.Overlay.overlay, name);
            for (var i = 0; i < all.length; i++) {
                if (all[i].visible)
                    return all[i];
            }
            return null;
        }

        function test_images_show_in_the_reply() {
            var delegate = show({id: "m-gen", role: "assistant", model: "Deliberate", content: "", time: "10:01", images: [generated, fromModel]});
            var pictures = findChildren(delegate, "messageImage");
            compare(pictures.length, 2);
            tryCompare(pictures[0], "status", Image.Ready);
            verify(pictures[0].source.toString().indexOf("image1.png") > 0);
            verify(findChild(delegate, "regenerateImageButton"), "a generated image can be regenerated");
            screenshot(root, "images-in-reply");
        }

        function test_regenerate_only_for_generated_images() {
            var delegate = show({id: "m-gen", role: "assistant", content: "", time: "10:01", images: [generated, fromModel]});
            var buttons = findChildren(delegate, "regenerateImageButton");
            compare(buttons.length, 2);
            compare(buttons[0].visible, true);
            compare(buttons[1].visible, false);
            buttons[0].clicked();
            compare(fakeStore.calls.length, 1);
            compare(fakeStore.calls[0].name, "regenerate");
            compare(fakeStore.calls[0].messageId, "m-gen");
            compare(fakeStore.calls[0].index, 0);
        }

        function test_click_enlarges_and_the_viewer_has_the_actions() {
            var delegate = show({id: "m-gen", role: "assistant", content: "", time: "10:01", images: [generated]});
            var enlarge = findChild(delegate, "enlargeButton");
            mouseClick(enlarge);
            var viewer = null;
            tryVerify(function() { viewer = inViewer("viewerImage"); return viewer !== null; }, 3000, "viewer opens");
            tryCompare(viewer, "status", Image.Ready);
            var caption = inViewer("viewerCaption");
            compare(caption.visible, true);
            verify(caption.text.indexOf("a red fox in the snow") >= 0 && caption.text.indexOf("AI Horde") >= 0 && caption.text.indexOf("512×512") >= 0 && caption.text.indexOf("seed 77") >= 0, caption.text);
            tryVerify(function() { return findChild(QQC2.Overlay.overlay, "viewerImage").opacity === 1; }, 3000);
            screenshot(viewer.parent, "images-enlarged");
            mouseClick(inViewer("viewerCopy"));
            compare(fakeStore.calls[0].name, "copy");
            compare(fakeStore.calls[0].path, "images/s-1/m-gen-0.webp");
            mouseClick(inViewer("viewerRegenerate"));
            compare(fakeStore.calls[1].name, "regenerate");
            tryVerify(function() { return inViewer("viewerImage") === null; }, 3000, "closes when regenerating");
        }

        function test_the_viewer_closes_with_its_button_and_on_escape() {
            var delegate = show({id: "m-gen", role: "assistant", content: "", time: "10:01", images: [fromModel]});
            mouseClick(findChild(delegate, "enlargeButton"));
            var viewer;
            tryVerify(function() { viewer = inViewer("viewerImage"); return viewer !== null; });
            compare(inViewer("viewerRegenerate"), null, "a model's own image has no Regenerate");
            var block = findChild(delegate, "messageImage");
            while (block && block.viewer === undefined) block = block.parent;
            // Escape and a click outside are the popup's own close policy (a key press can't reach a popup in the offscreen test window).
            verify((block.viewer.closePolicy & QQC2.Popup.CloseOnEscape) !== 0);
            verify((block.viewer.closePolicy & QQC2.Popup.CloseOnPressOutside) !== 0);
            tryVerify(function() { return block.viewer.opened; }, 3000, "viewer finished opening");
            mouseClick(inViewer("viewerClose"));
            tryVerify(function() { return !viewer.visible; });
        }

        function test_copy_says_what_happened() {
            var delegate = show({id: "m-gen", role: "assistant", content: "", time: "10:01", images: [fromModel]});
            mouseClick(findChild(delegate, "copyImageButton"));
            compare(findChild(delegate, "imageNote").text, "Image copied.");
            fakeStore.copyWorks = false;
            mouseClick(findChild(delegate, "copyImageButton"));
            verify(findChild(delegate, "imageNote").text.indexOf("wl-clipboard") >= 0);
        }

        function test_download_asks_where_to_save_and_exports_with_an_extension() {
            var delegate = show({id: "m-gen", role: "assistant", content: "", time: "10:01", images: [generated]});
            var item;
            // The image block is the nearest parent that has `download`.
            for (item = findChild(delegate, "messageImage"); item && typeof item.download !== "function"; item = item.parent) {}
            verify(item, "gallery");
            mouseClick(findChild(delegate, "downloadButton"));
            var dialog = item.saveDialog;
            verify(dialog, "dialog");
            compare(item.dialogImage, 0);
            verify(String(dialog.currentFile).indexOf("m-gen-0.webp") > 0, String(dialog.currentFile));
            dialog.close();
            // What the dialog hands back goes to the store; a name without an extension gets the picture's own.
            dialog.selectedFile = "file:///home/me/Pictures/fox";
            dialog.accepted();
            compare(fakeStore.calls[0].name, "export");
            compare(fakeStore.calls[0].dest, "/home/me/Pictures/fox.webp");
            compare(fakeStore.calls[0].path, "images/s-1/m-gen-0.webp");
        }

        function test_markdown_image_links_are_placeholders_until_clicked() {
            var content = "Here: ![a cat](https://img.example.com/cat.png) and ![x](http://insecure.example.com/x.png) and ![l](https://localhost/y.png)";
            var delegate = show({id: "m-link", role: "assistant", content: content, time: "10:01"});
            var tiles = findChildren(delegate, "imageLinkButton");
            compare(tiles.length, 1, "only the https link to a public host is offered");
            verify(tiles[0].text.indexOf("img.example.com") >= 0, tiles[0].text);
            // The text shows placeholders: the chat view never loads an image by itself.
            var body = findChild(delegate, "messageBody");
            verify(body, "body");
            var text = JSON.stringify(body.blocks);
            verify(text.indexOf("![a cat]") >= 0, "the stored text keeps the original link");
            screenshot(root, "images-link-tile");
            compare(fakeStore.calls.length, 0, "nothing is fetched before the click");
            mouseClick(tiles[0]);
            compare(fakeStore.calls.length, 1);
            compare(fakeStore.calls[0].name, "loadLink");
            compare(fakeStore.calls[0].url, "https://img.example.com/cat.png");
            compare(fakeStore.calls[0].index, 0);
            // A failure is said in words and the tile stays.
            fakeStore.pending(false, "That link is not a PNG, JPEG, WebP or GIF image.");
            compare(findChild(delegate, "imageNote").text, "That link is not a PNG, JPEG, WebP or GIF image.");
            compare(findChildren(delegate, "imageLinkButton").length, 1);
            // Once loaded (the store adds the image to the message) the tile goes.
            chat.messages = [chat.messages[0], Object.assign({}, chat.messages[1], {images: [{path: "images/s-1/m-link-0.png", source: "link", linkIndex: 0}]})];
            wait(80);
            compare(findChildren(view.list.itemAtIndex(1), "imageLinkButton").length, 0);
            compare(findChildren(view.list.itemAtIndex(1), "messageImage").length, 1);
        }
    }
}
