// The chat view's scrolling and the labels it shows: follow new content,
// jump between user messages, day dividers, times and token usage.
// `chat` is the widget root (main.qml); chat.msgListViewRef is the ListView.
import QtQuick
import "TimeFormat.js" as TimeFormat

QtObject {
    id: nav

    property var chat: null

    // The one scroll rule: the chat view follows new content while
    // userScrolledUp is false (see FullRepresentationContent's msgList).
    // force: jump to the latest message even if the user scrolled up.
    function scrollToBottom(force) {
        if (chat.userScrolledUp && !force)
            return;
        chat.userScrolledUp = false;
        if (chat.msgListViewRef)
            chat.msgListViewRef.positionViewAtEnd();
    }

    function messageTimestampAt(index) {
        if (index < 0 || index >= chat.messages.length)
            return Date.now();

        var m = chat.messages[index] || {
        };
        return m.at || Date.now();
    }

    function messageDayKeyAt(index) {
        var d = new Date(nav.messageTimestampAt(index));
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }

    function countMessagesForDayKey(dayKey) {
        var count = 0;
        for (var i = 0; i < chat.messages.length; i++) {
            if (nav.messageDayKeyAt(i) === dayKey)
                count++;

        }
        return count;
    }

    function dayDividerLabelForIndex(index) {
        var key = nav.messageDayKeyAt(index);
        return TimeFormat.dayBucketLabel(nav.messageTimestampAt(index)) + " (" + nav.countMessagesForDayKey(key) + ")";
    }

    function formatMessageTime(message, index) {
        // 12-hour or the region's format (Settings → Chat); "" keeps the
        // time as the message has it (24-hour, the default).
        var chosen = chat.prefs && message && message.at ? chat.prefs.formatTime(message.at) : "";
        if (chosen)
            return chosen;
        if (message && message.time)
            return message.time;

        return TimeFormat.nowTime(nav.messageTimestampAt(index));
    }

    function jumpOneMessageAbove() {
        if (!chat.msgListViewRef || chat.messages.length === 0)
            return ;

        var currentTop = -1;
        for (var offset = 15; offset <= 100; offset += 20) {
            currentTop = chat.msgListViewRef.indexAt(30, chat.msgListViewRef.contentY + offset);
            if (currentTop >= 0)
                break;

        }
        if (currentTop < 0)
            currentTop = chat.messages.length;

        var target = -1;
        for (var i = currentTop - 1; i >= 0; i--) {
            var msg = chat.messages[i];
            if (msg && msg.role === "user") {
                target = i;
                break;
            }
        }
        if (target >= 0) {
            chat.userScrolledUp = true;
            chat.msgListViewRef.positionViewAtIndex(target, ListView.Beginning);
        } else {
            chat.userScrolledUp = true;
            chat.msgListViewRef.positionViewAtBeginning();
        }
    }

    function jumpOneMessageBelow() {
        if (!chat.msgListViewRef || chat.messages.length === 0)
            return ;

        var currentTop = -1;
        for (var offset = 15; offset <= 100; offset += 20) {
            currentTop = chat.msgListViewRef.indexAt(30, chat.msgListViewRef.contentY + offset);
            if (currentTop >= 0)
                break;

        }
        if (currentTop < 0)
            currentTop = -1;

        var target = -1;
        for (var i = currentTop + 1; i < chat.messages.length; i++) {
            var msg = chat.messages[i];
            if (msg && msg.role === "user") {
                target = i;
                break;
            }
        }
        if (target >= 0) {
            var isLastUser = true;
            for (var j = target + 1; j < chat.messages.length; j++) {
                if (chat.messages[j] && chat.messages[j].role === "user") {
                    isLastUser = false;
                    break;
                }
            }
            if (isLastUser) {
                if (chat.userScrolledUp) {
                    chat.userScrolledUp = false;
                    nav.scrollToBottom();
                }
            } else {
                chat.userScrolledUp = true;
                chat.msgListViewRef.positionViewAtIndex(target, ListView.Beginning);
            }
        } else {
            if (chat.userScrolledUp) {
                chat.userScrolledUp = false;
                nav.scrollToBottom();
            }
        }
    }

    function formatTokensUsage(tokens, cost) {
        if (!tokens)
            return "";

        var parts = [];
        if (tokens.input !== undefined)
            parts.push("Input: " + tokens.input);

        if (tokens.output !== undefined)
            parts.push("Output: " + tokens.output);

        if (tokens.reasoning !== undefined && tokens.reasoning > 0)
            parts.push("Reasoning: " + tokens.reasoning);

        if (tokens.cache && (tokens.cache.read > 0 || tokens.cache.write > 0))
            parts.push("Cache R/W: " + tokens.cache.read + "/" + tokens.cache.write);

        var res = parts.join(" | ");
        if (cost !== undefined && cost > 0)
            res += " | Cost: $" + cost.toFixed(5);

        return res;
    }
}
