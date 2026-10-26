// Settings → Memory (ConfigMemory.qml): the global switch is a setting
// (cfg_memoryEnabled), the memories are not: every change goes to the helper
// (a stand-in here). Search, filter, add, edit, pin, on/off, delete with
// Undo, "Turn on all", and readable scopes.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami

Item {
    id: root
    width: 760
    height: 820

    property QtObject plasmoid: QtObject {
        property string id: ""
        property QtObject configuration: QtObject {
            property bool memoryEnabled: true
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(singular, plural, count) {
        var text = count === 1 ? singular : plural;
        for (var i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), arguments[i]);
        return text.replace("%1", count);
    }

    FakeMemoryHelper { id: helper }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    HarnessTestCase {
        id: tc
        name: "ConfigMemory"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        readonly property var saved: [
            {id: "m-0000000000000001", text: "Prefers metric units", scope: "all", projectId: "", chatId: "",
             pinned: false, enabled: true, created: 1, sourceChatId: ""},
            {id: "m-0000000000000002", text: "The widget targets Qt 6", scope: "project", projectId: "p-1", chatId: "",
             pinned: false, enabled: false, created: 2, sourceChatId: ""},
            {id: "m-0000000000000003", text: "Call me Sam", scope: "chat", projectId: "", chatId: "c-1",
             pinned: true, enabled: true, created: 3, sourceChatId: "c-1"},
            {id: "m-0000000000000004", text: "Likes green tea", scope: "chat", projectId: "", chatId: "c-gone",
             pinned: false, enabled: false, created: 4, sourceChatId: ""}
        ]

        function open(enabled) {
            var component = Qt.createComponent(uiDir + "ConfigMemory.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, {"width": root.width, "height": root.height, "cfg_memoryEnabled": enabled !== false,
                "helperRunner": helper, "chatTitles": {"c-1": "Trip planning"}, "projectNames": {"p-1": "KDE AI Chat"}});
            verify(page !== null);
            waitIdle();
            return page;
        }
        function waitIdle() {
            tryVerify(() => findChild(page, "memoryEmpty").text !== "Loading…"
                      && findChildren(page, "memoryText").length === page.shown.length, 3000);
            wait(20);
        }
        function texts() {
            return page.shown.map(function(m) { return m.text; });
        }
        function rowFor(text) {
            var labels = findChildren(page, "memoryText");
            for (var i = 0; i < labels.length; i++) {
                if (labels[i].text === text)
                    return labels[i].parent.parent.parent;   // label → column → row → MemoryRow
            }
            return null;
        }
        function button(row, name) {
            var b = findChild(row, name);
            verify(b, name);
            return b;
        }

        function init() {
            helper.reset();
            helper.memories = saved;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            wait(100);
        }

        function test_1_lists_pinned_first_with_readable_scopes() {
            open();
            compare(texts(), ["Call me Sam", "Likes green tea", "The widget targets Qt 6", "Prefers metric units"]);
            var scopes = findChildren(page, "memoryScope").map(function(l) { return l.text; });
            compare(scopes, ["Chat “Trip planning” · pinned", "One chat · off", "Project “KDE AI Chat” · off", "All chats"]);
            verify(findChild(page, "memoryEnabledSwitch").checked);
            var off = findChild(page, "memoryOffMessage");
            verify(off.visible, "turned-off memories are pointed out");
            verify(off.text.indexOf("2 memories are turned off") === 0);
            wait(300);
            screenshot(page, "config-memory");
        }

        function test_2_search_and_filter() {
            open();
            var search = findChild(page, "memorySearch");
            search.text = "TEA";
            compare(texts(), ["Likes green tea"]);
            search.text = "trip";
            compare(texts(), ["Call me Sam"], "the chat's title is searched too");
            search.text = "";
            var filter = findChild(page, "memoryFilter");
            filter.currentIndex = 4;
            filter.activated(4);
            compare(texts(), ["Likes green tea", "The widget targets Qt 6"]);
            filter.currentIndex = 2;
            filter.activated(2);
            compare(texts(), ["The widget targets Qt 6"]);
            search.text = "nothing like this";
            verify(findChild(page, "memoryEmpty").visible);
            compare(findChild(page, "memoryEmpty").text, "No memories match.");
        }

        function test_3_on_off_pin_and_turn_on_all() {
            open();
            mouseClick(button(rowFor("Prefers metric units"), "memoryOnBox"));
            tryVerify(() => helper.memories[0].enabled === false);
            mouseClick(button(rowFor("Prefers metric units"), "memoryPinButton"));
            tryVerify(() => helper.memories[0].pinned === true);
            tryVerify(() => texts().slice(0, 2).join("|") === "Call me Sam|Prefers metric units", 2000, "pinned ones first");
            var off = findChild(page, "memoryOffMessage");
            compare(page.offIds.length, 3);
            off.actions[0].trigger();
            tryVerify(() => helper.memories.every(function(m) { return m.enabled; }), 3000);
            tryVerify(() => !off.visible);
        }

        function test_4_edit_in_place() {
            open();
            var row = rowFor("Call me Sam");
            mouseClick(button(row, "memoryEditButton"));
            var editor = button(row, "memoryEditor");
            verify(editor.visible);
            compare(editor.text, "Call me Sam");
            editor.selectAll();
            keyClick(Qt.Key_Delete);
            var text = "Call me Sam, never Samuel";
            for (var i = 0; i < text.length; i++)
                keyClick(text.charAt(i));
            wait(500);
            screenshot(page, "config-memory-editing");
            mouseClick(button(row, "memorySaveButton"));
            tryVerify(() => helper.memories[2].text === "Call me Sam, never Samuel");
            var update = helper.calls.filter(function(c) { return c.command === "memory_update"; })[0];
            compare(update.payload.id, "m-0000000000000003");
            tryVerify(() => rowFor("Call me Sam, never Samuel") !== null);
        }

        function test_5_delete_and_undo() {
            open();
            mouseClick(button(rowFor("Prefers metric units"), "memoryDeleteButton"));
            tryVerify(() => helper.memories.length === 3);
            var deleted = findChild(page, "memoryDeletedMessage");
            verify(deleted.visible);
            deleted.actions[0].trigger();
            tryVerify(() => helper.memories.length === 4, 3000);
            compare(helper.memories[3].id, "m-0000000000000001", "back with the same id");
            verify(!deleted.visible);
        }

        function test_6_add_for_all_chats() {
            open();
            var field = findChild(page, "memoryAddField");
            field.text = "  Lives in Lisbon  ";
            mouseClick(findChild(page, "memoryAddButton"));
            tryVerify(() => helper.memories.length === 5);
            compare(helper.memories[4].text, "Lives in Lisbon");
            compare(helper.memories[4].scope, "all");
            tryCompare(field, "text", "");
        }

        function test_7_the_global_switch_is_a_setting_and_memories_are_not() {
            open(false);
            verify(!findChild(page, "memoryEnabledSwitch").checked);
            mouseClick(findChild(page, "memoryEnabledSwitch"));
            verify(page.cfg_memoryEnabled);
            // Nothing about the memories themselves is a cfg_ property.
            for (var key in page) {
                if (key.indexOf("cfg_") === 0)
                    verify(["cfg_memoryEnabled", "cfg_memoryBudget"].indexOf(key.replace(/(Default)?(Changed)?$/, "")) >= 0, key);
            }
        }

        function test_7b_the_size_per_message_is_the_users_call() {
            open();
            var spin = findChild(page, "memoryBudgetSpin");
            var noLimit = findChild(page, "memoryNoLimitCheck");
            compare(page.cfg_memoryBudget, 2000);
            verify(!noLimit.checked);
            mouseClick(noLimit);
            compare(page.cfg_memoryBudget, 0, "no limit");
            verify(!spin.enabled);
            mouseClick(noLimit);
            compare(page.cfg_memoryBudget, 2000, "back to the number shown");
            spin.forceActiveFocus();
            spin.increase();
            spin.valueModified();
            compare(page.cfg_memoryBudget, 2500);
        }

        function test_8_empty() {
            helper.memories = [];
            open();
            tryVerify(() => findChild(page, "memoryEmpty").text === "No memories yet.");
            verify(!findChild(page, "memoryOffMessage").visible);
        }
    }
}
