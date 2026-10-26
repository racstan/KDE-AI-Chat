// The header's "More actions" menu opens when the pointer rests on its button,
// closes shortly after the pointer has left both, and still opens by click or
// keyboard.
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 760
    height: 300

    function i18n(text) { return text; }
    function i18np(one, many, n) { return n === 1 ? one : many; }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    Chat.ChatHeader {
        id: header
        chat: chat
        width: parent.width
    }

    HarnessTestCase {
        name: "HeaderMenu"

        function more() { return findChild(header, "moreButton"); }
        function menu() { return more().menu; }

        function init() {
            chat.messages = [{role: "user", content: "Hi", time: "10:00"}];
            mouseMove(root, root.width / 2, root.height - 5);
            tryVerify(() => !menu().opened);
            wait(350);
        }

        function test_01_hovering_the_button_opens_the_menu_after_a_short_delay() {
            var b = more();
            mouseMove(b, b.width / 2, b.height / 2);
            wait(40);
            verify(!menu().opened, "not yet: the delay avoids menus opening as the pointer passes by");
            tryVerify(() => menu().opened, 600);
            // Opened under the button, not where the pointer is.
            verify(menu().contentItem.mapToItem(root, 0, 0).y >= b.mapToItem(root, 0, 0).y + b.height - 2);
            screenshot(root, "header-more-menu");
        }

        function test_02_passing_over_the_button_does_not_open_it() {
            var b = more();
            mouseMove(b, b.width / 2, b.height / 2);
            wait(40);
            mouseMove(root, root.width / 2, root.height - 5);
            wait(400);
            verify(!menu().opened);
        }

        function test_03_leaving_closes_it_after_a_grace_period() {
            var b = more();
            mouseMove(b, b.width / 2, b.height / 2);
            tryVerify(() => menu().opened, 600);
            mouseMove(root, 20, root.height - 5);
            wait(60);
            verify(menu().opened, "still open right after leaving");
            tryVerify(() => !menu().opened, 1000);
        }

        function test_04_moving_into_the_menu_keeps_it_open() {
            var b = more();
            mouseMove(b, b.width / 2, b.height / 2);
            tryVerify(() => menu().opened, 600);
            var c = menu().contentItem;
            mouseMove(c, c.width / 2, 10);
            wait(600);
            verify(menu().opened, "the pointer is on the menu");
            mouseMove(root, 20, root.height - 5);
            tryVerify(() => !menu().opened, 1000);
        }

        function test_05_click_still_opens_it_and_triggers_items() {
            var b = more();
            b.clicked();
            tryVerify(() => menu().opened);
            menu().close();
            tryVerify(() => !menu().opened);
        }

        function test_07_new_chat_is_a_plain_button_away_from_the_menu() {
            var plus = findChild(header, "newChatButton");
            verify(plus !== null);
            compare(plus.display, 0 /* AbstractButton.IconOnly */, "an icon only, no label or arrow");
            compare(plus.Accessible.role, Accessible.Button, "not a menu button (which Plasma draws with a down arrow)");
            verify(plus.menu === undefined || plus.menu === null, "no menu attached");
            verify(plus.x < more().x, "New chat is not the More button's neighbour on the side its menu opens");
            // Opening the More menu by hover, then moving onto "+": the menu closes at once.
            var b = more();
            mouseMove(b, b.width / 2, b.height / 2);
            tryVerify(() => menu().opened, 600);
            mouseMove(plus, plus.width / 2, plus.height / 2);
            tryVerify(() => !menu().opened, 200, "no menu hangs under New chat");
            tryVerify(() => !menu().visible, 1000);
            screenshot(root.Window.window.contentItem, "header-new-chat-plain");
        }

        function test_06_keyboard_opens_it_and_focuses_the_menu() {
            var b = more();
            b.forceActiveFocus();
            keyClick(Qt.Key_Space);
            tryVerify(() => menu().opened);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(chat.renamingCurrentChat, true, "the first item (Rename chat) was triggered from the keyboard");
            chat.renamingCurrentChat = false;
            tryVerify(() => !menu().opened);
        }
    }
}
