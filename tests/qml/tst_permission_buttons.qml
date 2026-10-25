// chat/PermissionButtons.qml: Allow / Always allow / Reject for an agent's permission request.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 480
    height: 80

    Chat.PermissionButtons {
        id: buttons
        message: ({"status": "pending", "canAlways": true})
    }

    SignalSpy {
        id: spy
        target: buttons
        signalName: "answered"
    }

    HarnessTestCase {
        name: "PermissionButtons"

        function init() {
            spy.clear();
        }

        function args(i) {
            return [spy.signalArguments[i][0], spy.signalArguments[i][1]];
        }

        function visibleTexts() {
            var texts = [];
            for (var i = 0; i < buttons.children.length; i++)
                if (buttons.children[i].visible) texts.push(buttons.children[i].text);
            return texts;
        }

        function test_1_opencode_offers_always_allow() {
            buttons.message = {"status": "pending", "canAlways": true};
            compare(visibleTexts(), ["Allow", "Always allow", "Reject"]);
            screenshot(root, "permission-buttons-pending");
            mouseClick(buttons.children[1]);
            compare(spy.count, 1);
            compare(args(0), [true, true]);
            mouseClick(buttons.children[2]);
            compare(args(1), [false, false]);
        }

        function test_2_pi_asks_yes_or_no() {
            buttons.message = {"status": "pending", "canAlways": false};
            compare(visibleTexts(), ["Allow", "Reject"]);
            mouseClick(buttons.children[0]);
            compare(args(0), [true, false]);
        }

        function test_3_answer_is_shown_instead_of_buttons() {
            buttons.message = {"status": "allowed", "canAlways": true};
            compare(visibleTexts(), ["Approved"]);
            var answer = buttons.children[buttons.children.length - 1];
            compare(String(answer.iconSource), "dialog-ok-apply");
            buttons.message = {"status": "denied", "canAlways": true};
            compare(visibleTexts(), ["Rejected"]);
            compare(String(answer.iconSource), "dialog-cancel");
            buttons.message = {"status": "answering...", "canAlways": true};
            compare(visibleTexts(), ["Answering…"]);
        }
    }
}
