// A memory added in the settings page must reach the chats: store/MemoryWatch.qml
// tells when memory.json is created or replaced on disk. The test writes the
// watched file with QtCore Settings, which (like the helper) saves to a new file
// and renames it into place.
import QtQuick
import QtCore
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

Item {
    id: root

    readonly property string dir: decodeURIComponent(String(StandardPaths.writableLocation(StandardPaths.TempLocation)).replace(/^file:\/\//, ""))
        + "/kdeaichat-memory-watch-" + Date.now()
    property int changes: 0

    Store.MemoryWatch {
        id: watch
        fileName: "watched.ini"
        onChanged: root.changes++
    }

    Component {
        id: writer
        Settings {}
    }

    function write(value, name) {
        var file = writer.createObject(null, {"location": "file://" + root.dir + "/" + (name || "watched.ini")});
        file.setValue("memory", value);
        file.sync();
        file.destroy();
    }

    HarnessTestCase {
        name: "MemoryWatch"

        function test_1_creating_then_replacing_the_file_is_seen() {
            // The data folder exists (as ~/.local/share/kdeaichat does), the memory file not yet.
            root.write("x", "other.ini");
            watch.directory = root.dir;
            wait(400);   // the watcher has looked at the (missing) file
            compare(root.changes, 0, "nothing changed yet");
            root.write("on saturday I'll visit my sister");
            tryVerify(function() { return root.changes === 1; }, 5000, "the new file is seen");
            wait(1100);  // a later modification time (some file systems keep whole seconds)
            root.write("on saturday I'll visit my sister, and on sunday I rest");
            tryVerify(function() { return root.changes === 2; }, 5000, "the replaced file is seen");
            wait(600);
            compare(root.changes, 2, "one signal per change, nothing while it stays the same");
        }

        function test_2_off_without_a_directory() {
            watch.directory = "";
            var before = root.changes;
            wait(600);
            compare(root.changes, before);
        }
    }
}
