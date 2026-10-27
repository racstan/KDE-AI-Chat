// Settings → Storage (ConfigStorage.qml): the data folder, sizes per item with
// a total, Open folder, Remove (backups, caches, old voice engines only, after
// asking) and the Speech Note line. The helper is a stand-in.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami

Item {
    id: root
    width: 760
    height: 900

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    QtObject {
        id: helper
        property var calls: []
        property var removed: []
        property bool voiceLeft: true
        property bool speechNote: true
        property bool fail: false

        function usage() {
            return {"type": "storage_usage", "root": "/home/u/.local/share/kdeaichat", "root_exists": true, "partial": false,
                    "total": 1802240 + 4300000000 + (removed.indexOf("backups") >= 0 ? 0 : 52000000),
                    "speech_note": {"folder": helper.speechNote ? "/home/u/.var/app/net.mkiol.SpeechNote/cache/net.mkiol/dsnote/speech-models" : "",
                                    "exists": helper.speechNote},
                    "items": [
                        {"id": "chats", "size": 1699840, "folder": "/home/u/.local/share/kdeaichat/chats", "removable": false, "exists": true},
                        {"id": "pictures", "size": 32768000, "folder": "/home/u/.local/share/kdeaichat/chats", "removable": false, "exists": true},
                        {"id": "memories", "size": 4096, "folder": "/home/u/.local/share/kdeaichat", "removable": false, "exists": true},
                        {"id": "schedules", "size": 16384, "folder": "/home/u/.local/share/kdeaichat", "removable": false, "exists": true},
                        {"id": "backups", "size": removed.indexOf("backups") >= 0 ? 0 : 52000000, "folder": "/home/u/.local/share/kdeaichat/backups", "removable": true, "exists": true},
                        {"id": "caches", "size": 8192, "folder": "/run/user/1000/kdeaichat", "removable": true, "exists": true},
                        {"id": "voice_old", "size": helper.voiceLeft && removed.indexOf("voice_old") < 0 ? 4300000000 : 0, "folder": "/home/u/.local/share/kdeaichat", "removable": true, "exists": true},
                        {"id": "other", "size": 8192, "folder": "/home/u/.local/share/kdeaichat", "removable": false, "exists": true}
                    ]};
        }

        function run(command, payload, onDone) {
            calls = calls.concat([{command: command, payload: payload}]);
            if (command === "storage_usage") {
                Qt.callLater(function() { onDone(fail ? "Error" : JSON.stringify(helper.usage()), fail ? 1 : 0, ""); });
            } else if (command === "storage_remove") {
                removed = removed.concat([payload.item]);
                Qt.callLater(function() { onDone(JSON.stringify({"type": "storage_removed", "item": payload.item, "freed": 52000000, "warnings": []}), 0, ""); });
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    HarnessTestCase {
        id: tc
        name: "ConfigStorage"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null
        property var opened: []

        function open(width) {
            var component = Qt.createComponent(uiDir + "ConfigStorage.qml");
            verify(component.status === Component.Ready, component.errorString());
            root.width = width || 760;
            page = component.createObject(root, {"width": root.width, "height": root.height, "helperRunner": helper,
                                                 "openUrl": function(url) { tc.opened = tc.opened.concat([url]); }});
            verify(page !== null);
            tryVerify(() => page.usage !== null, 3000);
            wait(50);
            return page;
        }
        function row(id) {
            var r = findChild(page, "storageRow-" + id);
            verify(r, id);
            return r;
        }

        function init() {
            helper.calls = [];
            helper.removed = [];
            helper.voiceLeft = true;
            helper.speechNote = true;
            helper.fail = false;
            opened = [];
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            wait(100);
        }

        function test_1_shows_folder_total_and_every_item() {
            open();
            compare(findChild(page, "storageRoot").text, "/home/u/.local/share/kdeaichat");
            compare(findChild(page, "storageTotal").text, "In total: 4.4 GB");
            compare(findChild(row("chats"), "storageSize").text, "1.7 MB");
            compare(findChild(row("backups"), "storageSize").text, "52 MB");
            compare(findChild(row("voice_old"), "storageTitle").text, "Old voice engines (no longer used)");
            compare(findChild(row("voice_old"), "storageSize").text, "4.3 GB");
            verify(findChild(page, "storageSpeechNote").visible);
            // Remove only where it is safe.
            ["chats", "pictures", "memories", "schedules", "other"].forEach(function(id) {
                verify(!findChild(row(id), "storageRemove").visible, id + " has no Remove");
            });
            ["backups", "caches", "voice_old"].forEach(function(id) {
                verify(findChild(row(id), "storageRemove").visible, id + " has Remove");
            });
            wait(300);
            screenshot(page, "config-storage-wide");
        }

        function test_2_open_folder_buttons() {
            open();
            findChild(page, "storageOpenRoot").clicked();
            findChild(row("backups"), "storageOpen").clicked();
            findChild(page, "storageOpenSpeechNote").clicked();
            compare(opened, ["file:///home/u/.local/share/kdeaichat", "file:///home/u/.local/share/kdeaichat/backups",
                             "file:///home/u/.var/app/net.mkiol.SpeechNote/cache/net.mkiol/dsnote/speech-models"]);
        }

        function test_3_remove_asks_with_the_size_then_removes_and_refreshes() {
            open();
            findChild(row("backups"), "storageRemove").clicked();
            var dialog = page.confirmDialog;
            verify(dialog, "dialog");
            tryVerify(() => dialog.visible, 2000);
            compare(dialog.title, "Remove Backups?");
            compare(dialog.subtitle, "This frees 52 MB and can't be undone.");
            compare(helper.calls.filter(c => c.command === "storage_remove").length, 0, "nothing removed before the answer");
            dialog.accept();
            tryVerify(() => findChild(page, "storageDone").visible, 3000);
            compare(findChild(page, "storageDone").text, "Removed. 52 MB freed.");
            var rm = helper.calls.filter(c => c.command === "storage_remove");
            compare(rm.length, 1);
            compare(rm[0].payload, {"item": "backups", "confirm": true});
            tryVerify(() => findChild(row("backups"), "storageSize").text === "0 B", 3000);
            verify(!findChild(row("backups"), "storageRemove").enabled, "nothing left to remove");
        }

        function test_4_cancel_removes_nothing() {
            open();
            findChild(row("caches"), "storageRemove").clicked();
            var dialog = page.confirmDialog;
            tryVerify(() => dialog.visible, 2000);
            dialog.reject();
            wait(100);
            compare(helper.calls.filter(c => c.command === "storage_remove").length, 0);
        }

        function test_5_no_old_voice_engines_or_speech_note_hides_them() {
            helper.voiceLeft = false;
            helper.speechNote = false;
            open();
            verify(!row("voice_old").visible);
            verify(!findChild(page, "storageSpeechNote").visible);
        }

        function test_6_failure_is_shown() {
            helper.fail = true;
            var component = Qt.createComponent(uiDir + "ConfigStorage.qml");
            page = component.createObject(root, {"width": root.width, "height": root.height, "helperRunner": helper});
            tryVerify(() => findChild(page, "storageError").visible, 3000);
        }

        function test_7_narrow() {
            open(480);
            wait(300);
            screenshot(page, "config-storage-narrow");
            var r = row("voice_old");
            verify(r.width <= 480);
            verify(findChild(r, "storageRemove").x + findChild(r, "storageRemove").width <= 480, "buttons fit");
        }
    }
}
