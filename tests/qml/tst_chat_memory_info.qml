// Memory in the Chat info panel (chat/ChatMemoryInfo.qml in
// ChatSettingsDialog.qml): the memories the latest message went with, and
// the per-chat switch (the session property memoryOff, inverted), which
// chat/Memory.qml honours.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

Item {
    id: root
    width: 760
    height: 760

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeMemoryHelper { id: helper }

    QtObject {
        id: config
        property bool memoryEnabled: true
        property string provider: "openai"
        property bool perChatModelSettings: false
        property string providersJson: "[]"
    }

    Store.MemoryStore {
        id: store
        configuration: config
        runHelper: helper.run
    }

    FakeChat {
        id: chat
        memoryStore: store
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    Ui.ChatSettingsDialog {
        id: dialog
        rootRef: chat
        hostItem: root
    }

    HarnessTestCase {
        name: "ChatMemoryInfo"

        readonly property var saved: [
            {id: "m-0000000000000001", text: "Vegetarian: suggest no meat dishes.", scope: "all", projectId: "", chatId: "",
             pinned: true, enabled: true, created: 1, sourceChatId: ""},
            {id: "m-0000000000000002", text: "Prefers trains over planes, and window seats. " + "Likes long scenic routes. ".repeat(12),
             scope: "chat", projectId: "", chatId: "a", pinned: false, enabled: true, created: 2, sourceChatId: "a"},
            {id: "m-0000000000000003", text: "Uses metric units.", scope: "all", projectId: "", chatId: "",
             pinned: false, enabled: true, created: 3, sourceChatId: ""}
        ]

        function waitIdle() {
            tryVerify(function() { return !store._busy && store._queue.length === 0; }, 3000);
        }

        function init() {
            dialog.close();
            config.memoryEnabled = true;
            helper.reset();
            helper.memories = saved;
            store.load();
            waitIdle();
            chat.plasmoid = {configuration: config};
            chat.currentSessionId = "a";
            chat.currentSessionTitle = "Trip planning";
            chat.messages = [{role: "user", content: "Plan a trip by train to Porto", at: 1}];
            chat.sessions = [{value: "a", text: "Trip planning", source: "provider", projectId: "",
                              memoryUsedIds: ["m-0000000000000001", "m-0000000000000002", "m-gone000000000000"]}];
            dialog.toggleForSession("a");
            tryVerify(() => dialog.visible);
            wait(50);
        }

        function test_1_shows_the_memories_the_latest_message_used() {
            var used = findChildren(dialog, "usedMemory");
            compare(used.length, 2, "the deleted one is left out");
            compare(used[0].text, "Vegetarian: suggest no meat dishes.");
            verify(used[1].text.length <= 141, "a long one is shortened");
            verify(used[1].text.endsWith("…"));
            compare(findChild(dialog, "memoryUsedTitle").text, "The latest message was sent with 2 memories:");
            verify(findChild(dialog, "chatMemorySwitch").checked);
            verify(!findChild(dialog, "memoryGlobalOffNote").visible);
            wait(400);
            screenshot(dialog, "chat-info-memory");
        }

        function test_2_the_switch_turns_memory_off_for_this_chat() {
            var sw = findChild(dialog, "chatMemorySwitch");
            mouseClick(sw);
            compare(chat.sessions[0].memoryOff, true);
            verify(!sw.checked);
            compare(findChildren(dialog, "usedMemory").length, 0);
            compare(chat.memory.forRequest("a").ids.length, 0, "Memory.qml sends none");
            mouseClick(sw);
            compare(chat.sessions[0].memoryOff, false);
            verify(sw.checked);
            verify(chat.memory.forRequest("a").ids.length > 0, "and some again");
        }

        function test_3_none_used() {
            chat.setSessionProperty("a", "memoryUsedIds", []);
            compare(findChildren(dialog, "usedMemory").length, 0);
            compare(findChild(dialog, "memoryUsedTitle").text, "The latest message was sent with no memories.");
        }

        function test_4_memory_off_everywhere() {
            config.memoryEnabled = false;
            verify(findChild(dialog, "memoryGlobalOffNote").visible);
            verify(!findChild(dialog, "memoryUsedTitle").visible);
            compare(findChildren(dialog, "usedMemory").length, 0);
        }

        function test_5_another_chat_has_its_own_switch() {
            chat.sessions = chat.sessions.concat([{value: "b", text: "Other", source: "provider", memoryOff: true}]);
            chat.currentSessionId = "b";
            tryVerify(() => !findChild(dialog, "chatMemorySwitch").checked);
            chat.currentSessionId = "a";
            tryVerify(() => findChild(dialog, "chatMemorySwitch").checked);
        }
    }
}
