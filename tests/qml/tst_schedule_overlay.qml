// "Schedule a message…" in the chat's ⋮ menu opens the schedule editor over
// the chat with that chat chosen; saving goes through the (fake) helper.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 460
    height: 700

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat {
        id: chat
        sessions: [{"value": "a", "text": "Morning briefing"}, {"value": "b", "text": "Recipes"}]
        currentSessionId: "b"
        plasmoid: ({"configuration": {"provider": ""}})
        property var wallet: ({"keys": {}, "status": "ready"})
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    Chat.ChatHeader {
        id: header
        chat: chat
        width: parent.width
        onScheduleRequested: overlay.openForChat(chat.currentSessionId)
    }

    Chat.ScheduleOverlay {
        id: overlay
        anchors.fill: parent
        chat: chat
        runHelper: function(command, payload, onDone) {
            calls.push({"command": command, "payload": payload});
            var reply = command === "schedule_preview"
                ? {"ok": true, "summary": "Mon–Fri 09:00", "rules": ["Mon–Fri 09:00"], "nextRuns": ["2099-10-27T09:00:00"], "warnings": []}
                : {"ok": true, "schedule": payload.schedule, "schedules": []};
            Qt.callLater(function() { onDone(JSON.stringify(reply), 0, ""); });
        }
        property var calls: []
    }

    Chat.SenderName {
        id: scheduledSender
        chat: chat
        role: "user"
        scheduleName: "Daily news"
    }

    HarnessTestCase {
        name: "ScheduleOverlay"

        function test_a_scheduled_message_says_so() {
            compare(findChild(scheduledSender, "senderScheduled").text, "Scheduled: Daily news");
            verify(findChild(scheduledSender, "senderScheduled").visible);
            scheduledSender.scheduleName = "";
            verify(!findChild(scheduledSender, "senderScheduled").visible);
        }

        function test_menu_opens_the_editor_for_this_chat() {
            var menu = findChild(header, "moreButton").menu;
            var item = null;
            for (var i = 0; i < menu.count; i++)
                if (menu.itemAt(i) && menu.itemAt(i).objectName === "scheduleMessageItem")
                    item = menu.itemAt(i);
            verify(item !== null, "the ⋮ menu has Schedule a message…");
            compare(item.text, "Schedule a message…");
            item.triggered();
            verify(overlay.visible);
            var editor = overlay.dialog.editor;
            compare(editor.draft.chatId, "b");
            compare(findChild(editor, "scheduleChat").displayText, "Recipes");
            verify(findChild(editor, "describeHint").visible, "no direct provider: the describe box explains why");
            findChild(editor, "scheduleMessage").text = "Suggest a dinner recipe";
            tryCompare(findChild(editor, "previewSummary"), "text", "Mon–Fri 09:00");
            screenshot(root, "schedule-overlay");
            mouseClick(findChild(overlay, "saveSchedule"));
            tryVerify(function() { return !overlay.visible; });
            var saved = overlay.calls.filter(function(c) { return c.command === "schedule_save"; })[0].payload.schedule;
            compare(saved.chatId, "b");
            compare(saved.message, "Suggest a dinner recipe");
        }
    }
}
