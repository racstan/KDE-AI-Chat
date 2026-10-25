// chat/ImageStore.qml: images become files through the helper, the message keeps only
// relative paths and notes, and files go when their message or chat goes (after the undo wait).
// The helper and the staging file are stand-ins.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 200
    height: 200

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    FakeChat { id: chat }

    Chat.ImageStore {
        id: store
        chat: chat
        directory: "/data/kdeaichat/chats/applet-7"
        deleteDelay: 60
        sweepInterval: 20
        // What the helper answers per command; commands are recorded with their payload.
        property var log: []
        property var staged: ({})
        property var answers: ({})
        runHelper: function(command, payload, onDone) {
            log = log.concat([{command: command, payload: payload}]);
            var answer = answers[command];
            var out = typeof answer === "function" ? answer(payload) : (answer || {});
            onDone(JSON.stringify(out), out.exit === undefined ? 0 : out.exit, "");
        }
        stage: function(fileName, text) {
            var next = Object.assign({}, staged);
            next[fileName] = text;
            staged = next;
        }
    }

    HarnessTestCase {
        name: "ImageStore"

        readonly property string b64: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=="

        function savedAs(payload) {
            return {"path": "images/" + payload.chat + "/" + payload.message + "-" + payload.n + ".png", "mime": "image/png", "bytes": 70};
        }

        function init() {
            store.log = [];
            store.staged = ({});
            store.answers = ({"image_save": savedAs, "image_delete": {"deleted": 1}});
            store._doomed = [];
            store._known = ({});
            store._trackedSession = "";
            store._pending = ({});
            store._used = ({});
            store._seen = ({});
            chat.calls = [];
            chat.sessions = [{value: "a", text: "A", messages: []}];
            chat.currentSessionId = "a";
            chat.messages = [{id: "m-1", role: "user", content: "hi"}, {id: "m-2", role: "assistant", content: "ok"}];
            wait(20);
            store.log = [];
        }

        function commands(name) {
            return store.log.filter(function(e) { return e.command === name; });
        }

        function test_base64_goes_through_a_staging_file_never_the_command_line() {
            store.saveItems("a", "m-2", [{kind: "data", b64: b64}], {source: "model", model: "gemini"}, null);
            var saves = commands("image_save");
            compare(saves.length, 1);
            var payload = saves[0].payload;
            compare(payload.directory, "/data/kdeaichat/chats/applet-7");
            compare(payload.chat, "a");
            compare(payload.message, "m-2");
            compare(payload.n, 0);
            verify(/^staging-[a-z0-9-]+\.ini$/.test(payload.staging), payload.staging);
            compare(store.staged[payload.staging], b64);
            verify(JSON.stringify(payload).indexOf(b64.substring(0, 20)) < 0, "no image data in the payload");
        }

        function test_the_message_keeps_only_paths_and_notes() {
            store.saveItems("a", "m-2", [{kind: "data", b64: b64, width: 512, height: 512}, {kind: "data", b64: b64 + "AAAA"}],
                            {source: "generated", prompt: "a fox", service: "AI Horde", model: "Deliberate", seed: "5"}, null);
            var images = chat.messages[1].images;
            compare(images.length, 2);
            compare(images[0].path, "images/a/m-2-0.png");
            compare(images[1].path, "images/a/m-2-1.png");
            compare(images[0].prompt, "a fox");
            compare(images[0].width, 512);
            compare(images[0].mime, "image/png");
            var json = JSON.stringify(chat.messages);
            verify(json.indexOf(b64.substring(0, 20)) < 0, "no base64 in the message");
            verify(json.indexOf("http") < 0, "no link in the message");
            // The next image of the same message gets the next number.
            store.saveItems("a", "m-2", [{kind: "data", b64: b64 + "BBBB"}], {}, null);
            compare(chat.messages[1].images[2].path, "images/a/m-2-2.png");
        }

        function test_a_link_is_fetched_by_the_helper_and_only_if_it_is_allowed() {
            var result = null;
            store.saveItem("a", "m-2", 0, {kind: "url", url: "https://img.example.com/a.png"}, function(r) { result = r; });
            compare(result.ok, true);
            compare(commands("image_save")[0].payload.url, "https://img.example.com/a.png");
            store.log = [];
            store.saveItem("a", "m-2", 0, {kind: "url", url: "http://img.example.com/a.png"}, function(r) { result = r; });
            store.saveItem("a", "m-2", 0, {kind: "url", url: "https://localhost/a.png"}, function(r) { result = r; });
            compare(result.ok, false);
            compare(result.code, "bad_url");
            compare(commands("image_save").length, 0, "the helper is not even asked");
        }

        function test_helper_refusals_are_reported() {
            store.answers = {"image_save": {"error": "That is not a PNG, JPEG, WebP or GIF image.", "code": "not_image"}};
            var got = null;
            store.saveItems("a", "m-2", [{kind: "data", b64: b64}], {}, function(entries, errors) { got = {entries: entries, errors: errors}; });
            compare(got.entries.length, 0);
            compare(got.errors[0].code, "not_image");
            verify(chat.messages[1].images === undefined, "nothing attached");
        }

        function test_reply_images_are_saved_once_and_failures_say_why() {
            var item = {kind: "data", b64: b64};
            store.addFromReply("a", "m-2", [item], {model: "gemini"});
            store.addFromReply("a", "m-2", [item], {model: "gemini"});   // the same image again in the stream
            compare(commands("image_save").length, 1);
            compare(chat.messages[1].images.length, 1);
            compare(chat.messages[1].images[0].source, "model");
            compare(chat.messages[1].images[0].model, "gemini");
            store.answers = {"image_save": {"error": "x", "code": "too_large"}};
            store.addFromReply("a", "m-2", [{kind: "data", b64: b64 + "CCCC"}], {});
            compare(chat.calls[chat.calls.length - 1].name, "error");
            verify(chat.calls[chat.calls.length - 1].args[0].indexOf("too large") >= 0);
        }

        function test_hasImages_counts_pictures_still_being_saved() {
            var release = null;
            store.answers = {"image_save": function(payload) { return savedAs(payload); }};
            var original = store.runHelper;
            store.runHelper = function(command, payload, onDone) { release = function() { original(command, payload, onDone); }; };
            store.saveItems("a", "m-2", [{kind: "data", b64: b64}], {}, null);
            compare(store.hasPending("m-2"), true);
            compare(store.hasImages({id: "m-2"}), true);
            compare(store.hasImages({id: "m-1"}), false);
            store.runHelper = original;
            release();
            compare(store.hasPending("m-2"), false);
            compare(store.hasImages(chat.messages[1]), true);
        }

        function test_markdown_data_images_move_out_of_the_text() {
            var reply = {id: "m-2", role: "assistant", content: "Here ![fox](data:image/png;base64," + b64 + ") is it."};
            var kept = store.takeInlineImages("a", reply);
            compare(kept.content, "Here [image: fox] is it.");
            compare(commands("image_save").length, 1);
            compare(chat.messages[1].images.length, 1);
            var plain = {id: "m-2", role: "assistant", content: "no pictures ![x](https://img.example.com/x.png)"};
            compare(store.takeInlineImages("a", plain), plain, "https links stay in the text for click-to-load");
        }

        function test_copy_and_export_use_the_helper() {
            store.answers = {"image_copy": {"tool": "wl-copy"}, "image_export": {"saved": "/x/y.png"}};
            var copied = null, exported = null;
            store.copyImage("images/a/m-2-0.png", function(ok, text) { copied = [ok, text]; });
            compare(copied[0], true);
            compare(copied[1], "wl-copy");
            compare(commands("image_copy")[0].payload.path, "images/a/m-2-0.png");
            store.answers = {"image_copy": {"error": "no tool", "code": "no_tool", "exit": 0}};
            store.copyImage("images/a/m-2-0.png", function(ok, text) { copied = [ok, text]; });
            compare(copied[0], false);
            verify(copied[1].indexOf("wl-clipboard") >= 0 && copied[1].indexOf("xclip") >= 0, copied[1]);
            store.exportImage("images/a/m-2-0.png", "/x/y.png", function(ok, text) { exported = [ok, text]; });
            compare(exported[0], true);
            compare(commands("image_export")[0].payload.dest, "/x/y.png");
        }

        function test_link_loading_attaches_the_picture_with_its_link_number() {
            var done = null;
            store.loadLink("a", "m-2", 1, {url: "https://img.example.com/b.png", alt: "b"}, function(ok, text) { done = [ok, text]; });
            compare(done[0], true);
            var image = chat.messages[1].images[0];
            compare(image.source, "link");
            compare(image.linkIndex, 1);
            compare(image.alt, "b");
            verify(JSON.stringify(image).indexOf("http") < 0, "the link is not kept in the image");
        }

        function test_files_of_a_deleted_message_go_after_the_undo_wait() {
            chat.messages = [chat.messages[0], Object.assign({}, chat.messages[1], {images: [{path: "images/a/m-2-0.png"}]})];
            wait(30);
            store.log = [];
            chat.messages = [chat.messages[0]];     // the message is deleted
            wait(20);
            compare(commands("image_delete").length, 0, "kept for now, so Undo can bring them back");
            tryVerify(function() { return commands("image_delete").length === 1; }, 2000);
            compare(commands("image_delete")[0].payload.chat, "a");
            compare(commands("image_delete")[0].payload.message, "m-2");
        }

        function test_undo_keeps_the_files() {
            var withImage = Object.assign({}, chat.messages[1], {images: [{path: "images/a/m-2-0.png"}]});
            chat.messages = [chat.messages[0], withImage];
            wait(30);
            store.log = [];
            chat.messages = [chat.messages[0]];
            wait(20);
            chat.messages = [chat.messages[0], withImage];   // Undo
            wait(250);
            compare(commands("image_delete").length, 0);
        }

        function test_deleting_a_chat_removes_its_image_folder_unless_undone() {
            chat.sessions = [{value: "a", text: "A", messages: []}, {value: "b", text: "B", messages: []}];
            var removed = chat.sessions[1];
            chat.sessions = [chat.sessions[0]];
            chat.sessionDeleted(removed, 1);
            tryVerify(function() { return commands("image_delete").length === 1; }, 2000);
            compare(commands("image_delete")[0].payload.chat, "b");
            compare(commands("image_delete")[0].payload.message, undefined, "the whole chat folder");
            // Undone in time: the chat is back, so nothing goes.
            store.log = [];
            chat.sessions = [chat.sessions[0]];
            chat.sessionDeleted({value: "c", text: "C", messages: []}, 1);
            chat.sessions = [chat.sessions[0], {value: "c", text: "C", messages: []}];
            wait(250);
            compare(commands("image_delete").length, 0);
        }

        function test_switching_chats_never_deletes_anything() {
            chat.sessions = [{value: "a", text: "A", messages: [{id: "m-1"}]}, {value: "b", text: "B", messages: [{id: "m-9", images: [{path: "images/b/m-9-0.png"}]}]}];
            chat.messages = [{id: "m-9", images: [{path: "images/b/m-9-0.png"}]}];
            chat.currentSessionId = "b";
            wait(30);
            store.log = [];
            // The messages change before the id does, as they may when a chat is opened.
            chat.messages = [{id: "m-1"}];
            chat.currentSessionId = "a";
            wait(250);
            compare(commands("image_delete").length, 0);
        }

        function test_urls_are_file_addresses_inside_the_chat_folder() {
            compare(store.urlFor("images/a/m-2-0.png"), "file:///data/kdeaichat/chats/applet-7/images/a/m-2-0.png");
            compare(store.urlFor(""), "");
        }
    }
}
