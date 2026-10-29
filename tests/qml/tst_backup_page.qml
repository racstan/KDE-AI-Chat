// The Backup group of Settings → Storage (config/BackupSection.qml): Back up…,
// Restore… (with the "Also restore settings" choice) and Import… . The helper is
// a stand-in; the file dialogs are replaced by the section's `pick` hook.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami

Item {
    id: root
    width: 700
    height: 600

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    QtObject {
        id: helper
        property var calls: []
        property var answers: ({})

        function run(command, payload, onDone) {
            calls = calls.concat([{command: command, payload: payload}]);
            var answer = answers[command];
            Qt.callLater(function() { onDone(JSON.stringify(answer || {ok: false, error: "no answer"}), 0, ""); });
        }
    }

    // Stands in for plasmoid.configuration (a property map with keys()).
    QtObject {
        id: fakeConfig
        property string provider: ""
        property string model: ""
        property string sendKey: "enter"
        property string apiKey: ""
        property string openRouterApiKey: ""
        property int walletKeysRevision: 2
        property string chatSessionsJson: "[]"
        property int chatsReloadRevision: 0
        property int fontSize: 10
        function keys() {
            return ["provider", "model", "sendKey", "apiKey", "openRouterApiKey", "walletKeysRevision", "chatSessionsJson",
                    "chatsReloadRevision", "fontSize"];
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    HarnessTestCase {
        id: tc
        name: "BackupPage"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var section: null
        property var picked: []

        function open() {
            var component = Qt.createComponent(uiDir + "config/BackupSection.qml");
            verify(component.status === Component.Ready, component.errorString());
            fakeConfig.provider = "openrouter";
            fakeConfig.model = "auto";
            fakeConfig.apiKey = "sk-secret";
            fakeConfig.openRouterApiKey = "or-secret";
            fakeConfig.chatsReloadRevision = 0;
            section = component.createObject(root, {"width": 600, "helperRunner": helper, "configuration": fakeConfig,
                                                    "directory": "/home/u/.local/share/kdeaichat/chats/applet-9",
                                                    "widgetVersion": "1.5.0",
                                                    "pick": function(kind) { tc.picked = tc.picked.concat([kind]); }});
            verify(section !== null);
            return section;
        }

        function init() {
            helper.calls = [];
            helper.answers = {};
            picked = [];
        }
        function cleanup() {
            if (section)
                section.destroy();
            section = null;
            wait(50);
        }
        function visibleText(name) {
            var item = findChild(section, name);
            verify(item, name);
            return item.visible ? item.text : "";
        }

        function test_1_three_buttons_ask_for_a_file() {
            open();
            findChild(section, "backupCreate").clicked();
            findChild(section, "backupRestore").clicked();
            findChild(section, "backupImport").clicked();
            compare(picked, ["backup", "restore", "import"]);
            compare(findChild(section, "backupCreate").text, "Back up…");
            compare(findChild(section, "backupImport").text, "Import from ChatGPT or Claude…");
            wait(200);
            screenshot(section, "backup-section");
        }

        function test_2_back_up_sends_only_non_secret_settings_and_reports() {
            open();
            helper.answers = {backup_create: {ok: true, path: "/x/b.zip", bytes: 10, contents: {chats: 12, memories: 5, schedules: 2}}};
            section.accepted("backup", "/home/u/Documents/b.zip");
            tryVerify(() => visibleText("backupDone") !== "", 2000);
            compare(visibleText("backupDone"), "Backup saved: 12 chats, 5 memories, 2 schedules.");
            var call = helper.calls[0];
            compare(call.command, "backup_create");
            compare(call.payload.dest, "/home/u/Documents/b.zip");
            compare(call.payload.directory, "/home/u/.local/share/kdeaichat/chats/applet-9");
            compare(call.payload.widgetVersion, "1.5.0");
            var names = Object.keys(call.payload.settings).sort();
            compare(names, ["chatsReloadRevision", "fontSize", "model", "provider", "sendKey"]);
            verify(JSON.stringify(call.payload).indexOf("secret") < 0, "no secret in the payload");
        }

        function test_3_restore_asks_first_settings_off_by_default() {
            open();
            helper.answers = {backup_inspect: {ok: true, manifest: {format: 1}, hasSettings: true, counts: {chats: 7, memories: 3, schedules: 1, mcpServers: 0}},
                              backup_restore: {ok: true, chatsAdded: 6, chatsSkipped: 1, chatsDamaged: 0, memoriesAdded: 3, schedulesAdded: 1,
                                               settings: {provider: "anthropic", apiKey: "sk-evil", nonsense: 1}}};
            section.accepted("restore", "/home/u/b.zip");
            tryVerify(() => findChild(section, "backupFound").visible, 2000);
            compare(findChild(section, "backupFoundText").text, "This backup has 7 chats, 3 memories and 1 schedules.");
            var box = findChild(section, "restoreSettings");
            verify(box.visible);
            compare(box.checked, false);
            compare(helper.calls.length, 1);  // nothing restored yet
            findChild(section, "restoreConfirm").clicked();
            tryVerify(() => visibleText("backupDone") !== "", 2000);
            compare(helper.calls[1].command, "backup_restore");
            compare(helper.calls[1].payload.withSettings, false);
            compare(helper.calls[1].payload.mode, "merge");
            compare(visibleText("backupDone"), "Restored 6 chats (1 already there), 3 memories and 1 schedules (switched off).");
            compare(fakeConfig.provider, "openrouter");           // settings not applied
            compare(fakeConfig.chatsReloadRevision, 1);           // the widget reloads its chats
            verify(!findChild(section, "backupFound").visible);
        }

        function test_4_restore_with_settings_applies_only_known_non_secret_keys() {
            open();
            helper.answers = {backup_inspect: {ok: true, manifest: {format: 1}, hasSettings: true, counts: {chats: 1, memories: 0, schedules: 0, mcpServers: 0}},
                              backup_restore: {ok: true, chatsAdded: 1, chatsSkipped: 0, chatsDamaged: 0, memoriesAdded: 0, schedulesAdded: 0,
                                               settings: {provider: "anthropic", apiKey: "sk-evil", nonsense: 1}}};
            section.accepted("restore", "/home/u/b.zip");
            tryVerify(() => findChild(section, "backupFound").visible, 2000);
            findChild(section, "restoreSettings").checked = true;
            findChild(section, "restoreConfirm").clicked();
            tryVerify(() => visibleText("backupDone") !== "", 2000);
            compare(helper.calls[1].payload.withSettings, true);
            compare(fakeConfig.provider, "anthropic");
            compare(fakeConfig.apiKey, "sk-secret");
            compare(fakeConfig.nonsense, undefined);
            verify(visibleText("backupDone").indexOf("1 settings restored.") > 0);
        }

        function test_5_restore_can_be_cancelled_and_no_settings_box_without_settings() {
            open();
            helper.answers = {backup_inspect: {ok: true, manifest: {format: 1}, hasSettings: false, counts: {chats: 1, memories: 0, schedules: 0, mcpServers: 0}}};
            section.accepted("restore", "/home/u/b.zip");
            tryVerify(() => findChild(section, "backupFound").visible, 2000);
            verify(!findChild(section, "restoreSettings").visible);
            findChild(section, "restoreCancel").clicked();
            verify(!findChild(section, "backupFound").visible);
            compare(helper.calls.length, 1);
        }

        function test_6_import_result_line_and_reload() {
            open();
            helper.answers = {import_run: {ok: true, format: "chatgpt", imported: 42, existing: 3, empty: 0}};
            section.accepted("import", "/home/u/export.zip");
            tryVerify(() => visibleText("backupDone") !== "", 2000);
            compare(visibleText("backupDone"), "Imported 42 chats, 3 already there");
            compare(helper.calls[0].command, "import_run");
            compare(helper.calls[0].payload.path, "/home/u/export.zip");
            compare(fakeConfig.chatsReloadRevision, 1);
        }

        function test_7_errors_are_shown_and_nothing_reloads() {
            open();
            helper.answers = {import_run: {ok: false, error: "This isn't a ChatGPT or Claude conversations.json."},
                              backup_inspect: {ok: false, error: "This isn't a backup file."}};
            section.accepted("import", "/home/u/x.zip");
            tryVerify(() => visibleText("backupError") !== "", 2000);
            compare(visibleText("backupError"), "This isn't a ChatGPT or Claude conversations.json.");
            compare(fakeConfig.chatsReloadRevision, 0);
            section.accepted("restore", "/home/u/x.zip");
            tryVerify(() => visibleText("backupError") === "This isn't a backup file.", 2000);
            verify(!findChild(section, "backupFound").visible);
            verify(visibleText("backupDone") === "");
        }
    }
}
