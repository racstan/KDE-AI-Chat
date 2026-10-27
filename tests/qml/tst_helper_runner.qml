// store/HelperRunner.qml: every payload goes to the helper in a private file (never on the
// command line) except for a short list of tiny commands; the helper deletes the file; and
// chat/HelperCommands.qml sends a large chat export that way, reporting success or failure.
// Runs a stand-in helper (fake_helper.py) and the real one (export_chat).
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/Security.js" as Sec

Item {
    id: root
    width: 200
    height: 200

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    function fileOf(relative) {
        return decodeURIComponent(String(Qt.resolvedUrl(relative)).replace(/^file:\/\//, ""));
    }

    readonly property string fake: fileOf("fake_helper.py")
    readonly property string real: fileOf("../../org.kde.plasma.kdeaichat/contents/ui/kde_ai_helper.py")

    Store.HelperRunner { id: runner; helperPath: root.fake }
    Store.HelperRunner { id: blocked; helperPath: root.fake; privateDir: "" }

    QtObject {
        id: chat
        property var errors: []
        function getHelperPath() { return root.real; }
        function pushErrorMessage(text) { errors = errors.concat([text]); }
    }

    Chat.HelperCommands {
        id: commands
        chat: chat
        property var notified: []
        exportNotifier: function(path) { notified = notified.concat([path]); }
    }

    TestCase {
        name: "HelperRunner"
        when: windowShown

        function ask(runnerObject, command, payload) {
            var out = null;
            runnerObject.run(command, payload, function(stdout, code, stderr) { out = {"stdout": stdout, "code": code, "stderr": stderr}; });
            tryVerify(function() { return out !== null; }, 15000);
            return out;
        }

        function init() {
            chat.errors = [];
            commands.notified = [];
        }

        function test_default_is_private_and_not_on_the_command_line() {
            var secret = "my secret memory 4f9c1d";
            var out = ask(runner, "memory_add", {"text": secret});
            compare(out.code, 0, out.stderr);
            var report = JSON.parse(out.stdout);
            verify(report.argv[1].indexOf("@kdeaichat-payload-") === 0, "payload argument is a file name: " + report.argv[1]);
            compare(report.argv.join(" ").indexOf(secret), -1);
            compare(report.argv.join(" ").indexOf(Sec.base64Encode(secret)), -1);
            compare(report.payload.text, secret);
            verify(report.existed, "the file existed when the helper started");
        }

        function test_payload_file_is_removed() {
            var report = JSON.parse(ask(runner, "schedule_save", {"schedule": {"prompt": "x"}}).stdout);
            verify(report.existed);
            verify(report.gone, "the helper deleted the payload file");
        }

        function test_listed_tiny_commands_stay_on_argv() {
            var names = ["prepare_chat_dir", "storage_usage", "desktop_status"];
            for (var i = 0; i < names.length; i++) {
                var report = JSON.parse(ask(runner, names[i], {"directory": "/x"}).stdout);
                verify(report.argv[1].indexOf("@") !== 0, names[i] + " uses argv");
                compare(report.payload.directory, "/x");
            }
            verify(runner.argvCommands.indexOf("tts_synthesize") < 0);
            verify(runner.argvCommands.indexOf("memory_add") < 0);
        }

        function test_no_private_folder_fails_cleanly() {
            var out = ask(blocked, "memory_add", {"text": "a"});
            compare(out.code, 1);
            var tiny = ask(blocked, "storage_usage", {});
            compare(tiny.code, 0);
        }

        function test_large_export_goes_through() {
            var path = "/tmp/kdeaichat-test-export-" + Date.now() + ".md";
            var line = "A long line of chat text with ünïcödé and some more words to fill it.\n";
            var text = "";
            while (text.length < 300000)
                text += line;
            commands.writeExportFile(path, text);
            tryVerify(function() { return commands.notified.length + chat.errors.length > 0; }, 20000);
            compare(chat.errors.length, 0, chat.errors.join("; "));
            compare(commands.notified, [path]);
            var stat = JSON.parse(ask(runner, "stat_file", {"path": path}).stdout);
            verify(stat.size >= 300000, "the file was written: " + stat.size);
            ask(runner, "unlink_file", {"path": path});
        }

        function test_failed_export_shows_an_error_and_no_notification() {
            commands.writeExportFile("/proc/kdeaichat-no/such/folder/out.md", "text");
            tryVerify(function() { return chat.errors.length > 0; }, 20000);
            verify(chat.errors[0].indexOf("Export failed") === 0, chat.errors[0]);
            compare(commands.notified.length, 0);
        }

        function test_too_big_export_is_refused_with_an_error() {
            var big = "x".repeat(20000001);
            commands.writeExportFile("/tmp/kdeaichat-never.md", big);
            compare(chat.errors.length, 1);
            verify(chat.errors[0].indexOf("too large") >= 0);
            compare(commands.notified.length, 0);
        }

        function test_bad_destination_is_refused() {
            commands.writeExportFile("../x", "text");
            compare(chat.errors.length, 1);
        }
    }
}
