// The chat's messages as a ListModel, so the chat view updates row by row
// instead of rebuilding every message whenever root.messages is reassigned.
//
// Each row is {msgKey, rev}: the message's id and a revision that goes up
// when that message object is replaced. The message itself stays a plain JS
// object (messageFor(key)); messages without an id get one here, which then
// also goes into the saved chat.
//
// sync(messages) compares by id and by object identity, so the usual edits
// (append, update one message, delete one) touch only the rows involved,
// and a whole new list (switching chats) replaces the rows in one go.
import QtQuick

ListModel {
    id: list

    property var byKey: ({})
    property int counter: 0

    function messageFor(key) {
        return list.byKey[key];
    }

    // Gives msg an id unless it has one that's unused in this sync.
    function _key(msg, seen) {
        var key = msg.id !== undefined && msg.id !== null && msg.id !== "" ? String(msg.id) : "";
        if (!key || seen[key]) {
            key = "m-" + Date.now().toString(36) + "-" + (++list.counter);
            msg.id = key;
        }
        seen[key] = true;
        return key;
    }

    function sync(messages) {
        messages = messages || [];
        var seen = {};
        var keys = [];
        var wanted = {};
        for (var n = 0; n < messages.length; n++) {
            var msg = messages[n] || {};
            if (typeof msg !== "object") msg = {"role": "error", "content": String(msg)};
            keys.push(list._key(msg, seen));
            wanted[keys[n]] = messages[n];
        }

        var present = {};
        for (var r = 0; r < list.count; r++)
            present[list.get(r).msgKey] = true;
        var overlap = false;
        for (var k = 0; k < keys.length && !overlap; k++)
            overlap = present[keys[k]] === true;
        if (!overlap) {
            // A different chat: replace everything at once.
            list.clear();
            list.byKey = {};
            for (var a = 0; a < keys.length; a++) {
                list.byKey[keys[a]] = messages[a];
                list.append({"msgKey": keys[a], "rev": 0});
            }
            return;
        }

        var i = 0;
        var j = 0;
        while (j < keys.length) {
            if (i >= list.count) {
                list.byKey[keys[j]] = messages[j];
                list.append({"msgKey": keys[j], "rev": 0});
                i++;
                j++;
                continue;
            }
            var rowKey = list.get(i).msgKey;
            if (rowKey === keys[j]) {
                if (list.byKey[rowKey] !== messages[j]) {
                    list.byKey[rowKey] = messages[j];
                    list.setProperty(i, "rev", list.get(i).rev + 1);
                }
                i++;
                j++;
            } else if (wanted[rowKey] === undefined) {
                delete list.byKey[rowKey];
                list.remove(i);
            } else {
                // keys[j] is new here (or moved): put it in this place.
                for (var m = i + 1; m < list.count; m++) {
                    if (list.get(m).msgKey === keys[j]) {
                        list.remove(m);
                        break;
                    }
                }
                list.byKey[keys[j]] = messages[j];
                list.insert(i, {"msgKey": keys[j], "rev": 0});
                i++;
                j++;
            }
        }
        while (list.count > keys.length) {
            delete list.byKey[list.get(list.count - 1).msgKey];
            list.remove(list.count - 1);
        }
    }
}
