// Saving memories from a chat: "Remember" under a message (RememberPopup.qml)
// with its scope choice, the /remember command (CommandRunner.qml), and the
// Undo notice that confirms both (UndoNotice.qml). Nothing is sent to the
// model, and only the user saves memories.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Window
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/store" as Store

Item {
    id: root
    width: 560
    height: 640

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
        color: "white"
    }

    Chat.ChatView {
        id: view
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: composer.top
        chat: chat
    }

    Chat.Composer {
        id: composer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        chat: chat
    }

    Chat.UndoNotice {
        id: notice
        chat: chat
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: composer.top
        anchors.bottomMargin: 8
    }

    Component {
        id: popupComponent
        Chat.RememberPopup {}
    }

    HarnessTestCase {
        id: tc
        name: "Remember"

        function waitIdle() {
            tryVerify(function() { return !store._busy && store._queue.length === 0; }, 3000);
        }
        function sends() {
            return chat.calls.filter(function(c) { return c.name === "send"; });
        }
        function actionsOf(index) {
            var delegate = view.list.itemAtIndex(index);
            verify(delegate, "delegate " + index);
            return findChild(delegate, "messageActions");
        }
        function rememberButton(index) {
            var actions = actionsOf(index);
            tryCompare(actions, "built", actions.buttonCount, 3000);
            var button = findChild(actions, "rememberButton");
            verify(button, "Remember button on message " + index);
            return button;
        }
        function openPopup(index) {
            var delegate = view.list.itemAtIndex(index);
            mouseMove(root, 5, 5);
            wait(50);
            mouseMove(delegate, delegate.width / 2, delegate.height / 2);
            tryCompare(actionsOf(index), "opacity", 1, 2000);
            mouseClick(rememberButton(index));
            // The popup's items are under the window's overlay.
            var popup = QQC2.Overlay.overlay;
            tryVerify(() => findChild(popup, "rememberSave") !== null && findChild(popup, "rememberSave").visible, 2000);
            wait(200);
            return popup;
        }
        function type(text) {
            for (var i = 0; i < text.length; i++)
                keyClick(text.charAt(i));
        }
        function enter(line) {
            composer.input.text = line;
            composer.input.cursorPosition = line.length;
            chat.focusInput();
            tryVerify(() => composer.input.activeFocus);
            keyClick(Qt.Key_Return);
        }

        function init() {
            helper.reset();
            store.list = [];
            config.memoryEnabled = true;
            notice.dismiss();
            chat.calls = [];
            chat.loading = false;
            chat.projects.list = [];
            chat.sessions = [{value: "a", text: "Trip planning", source: "provider", projectId: ""}];
            chat.currentSessionId = "a";
            chat.messages = [
                {role: "user", content: "I am vegetarian, keep that in mind.", time: "10:00"},
                {role: "assistant", model: "m", content: "Noted: vegetarian suggestions only.", time: "10:00"}
            ];
            composer.input.text = "";
            wait(50);
            mouseMove(root, 5, 5);
        }

        function closePopup() {
            if (findChild(QQC2.Overlay.overlay, "rememberSave"))
                keyClick(Qt.Key_Escape);
            tryVerify(() => findChild(QQC2.Overlay.overlay, "rememberSave") === null, 2000);
        }

        function cleanup() {
            closePopup();
        }

        function test_1_remember_saves_for_all_chats_by_default_and_undo_removes_it() {
            var popup = openPopup(0);
            compare(findChild(popup, "rememberText").text, "I am vegetarian, keep that in mind.");
            verify(findChild(popup, "scopeAll").checked, "all chats by default");
            verify(!findChild(popup, "scopeProject").visible, "no project choice: the chat is in none");
            screenshot(QQC2.Overlay.overlay.parent, "remember-popup");
            mouseClick(findChild(popup, "rememberSave"));
            waitIdle();
            compare(helper.memories.length, 1);
            var m = helper.memories[0];
            compare(m.text, "I am vegetarian, keep that in mind.");
            compare(m.scope, "all");
            compare(m.sourceChatId, "a");
            tryCompare(notice, "text", "Saved to memory");
            verify(findChild(notice, "undoButton").visible);
            compare(sends().length, 0, "nothing is sent to the model");
            tryVerify(() => findChild(QQC2.Overlay.overlay, "rememberSave") === null, 2000);
            screenshot(root, "remember-saved");
            mouseClick(findChild(notice, "undoButton"));
            waitIdle();
            compare(helper.memories.length, 0, "Undo removes it");
        }

        function test_2_this_chat_only_and_edited_text() {
            var popup = openPopup(1);
            var text = findChild(popup, "rememberText");
            text.text = "Vegetarian suggestions only";
            mouseClick(findChild(popup, "scopeChat"));
            mouseClick(findChild(popup, "rememberSave"));
            waitIdle();
            compare(helper.memories.length, 1);
            compare(helper.memories[0].text, "Vegetarian suggestions only");
            compare(helper.memories[0].scope, "chat");
            compare(helper.memories[0].chatId, "a");
        }

        function test_3_project_scope_only_for_a_chat_in_a_project() {
            chat.projects.list = [{id: "p-food", name: "Food", color: "#1cdc9a", instructions: "", folder: "", provider: "", model: ""}];
            chat.sessions = [{value: "a", text: "Trip planning", source: "provider", projectId: "p-food"}];
            var popup = openPopup(0);
            var project = findChild(popup, "scopeProject");
            verify(project.visible);
            compare(project.text, "Chats in the project “Food”");
            mouseClick(project);
            mouseClick(findChild(popup, "rememberSave"));
            waitIdle();
            compare(helper.memories[0].scope, "project");
            compare(helper.memories[0].projectId, "p-food");
        }

        function test_4_selection_and_the_length_cap() {
            var actions = actionsOf(1);
            actions.selectedText = "vegetarian suggestions";
            var popup = openPopup(1);
            compare(findChild(popup, "rememberText").text, "vegetarian suggestions");
            closePopup();
            actions.selectedText = "";
            // A long message is cut to the memory limit.
            var long = popupComponent.createObject(root, {"chat": chat, "sessionId": "a", "initialText": "x".repeat(5000)});
            long.open();
            tryVerify(() => long.opened, 2000);
            compare(findChild(long.contentItem, "rememberText").text.length, 4000);
            long.close();
            closePopup();
        }

        function test_5_saving_an_existing_memory_again_turns_it_on_and_has_no_undo() {
            helper.memories = [{id: "m-0000000000000009", text: "Likes tea", scope: "all", projectId: "", chatId: "",
                                pinned: false, enabled: false, created: 1, sourceChatId: ""}];
            store.load();
            waitIdle();
            enter("/remember likes tea");
            waitIdle();
            compare(helper.memories.length, 1, "not added twice");
            compare(helper.memories[0].enabled, true, "turned on");
            tryCompare(notice, "text", "Already in memory");
            verify(!findChild(notice, "undoButton").visible);
        }

        function test_6_remember_command_saves_and_sends_nothing() {
            enter("/remember I prefer metric units");
            waitIdle();
            compare(helper.memories.length, 1);
            compare(helper.memories[0].text, "I prefer metric units");
            compare(helper.memories[0].scope, "all");
            compare(composer.input.text, "", "the box is cleared");
            compare(sends().length, 0);
            tryCompare(notice, "text", "Saved to memory");
        }

        function test_7_remember_command_scopes() {
            enter("/remember chat: call me Sam");
            waitIdle();
            compare(helper.memories[0].scope, "chat");
            compare(helper.memories[0].chatId, "a");
            compare(helper.memories[0].text, "call me Sam");
            enter("/remember project: uses Qt 6");
            compare(composer.input.text, "/remember project: uses Qt 6", "kept: the chat is in no project");
            compare(findChild(composer, "statusText").text, "This chat is in no project. Use /remember or /remember chat:.");
            compare(helper.memories.length, 1);
        }

        function test_8_empty_remember_shows_a_hint() {
            enter("/remember");
            compare(helper.calls.length, 0);
            compare(sends().length, 0);
            verify(findChild(composer, "statusText").text.indexOf("Write what to remember") === 0);
        }

        function test_9_unknown_commands_are_still_messages() {
            enter("/rememberx something");
            compare(sends().length, 1);
            compare(sends()[0].args[0], "/rememberx something");
            compare(helper.calls.length, 0);
        }

        function test_a_a_failed_save_says_so() {
            helper.fail = true;
            enter("/remember anything");
            waitIdle();
            tryCompare(notice, "text", "Could not save the memory.");
            verify(!findChild(notice, "undoButton").visible);
        }
    }
}
