// chat/MessageModel.qml: rows follow root.messages by id, touching only what changed.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: host
    width: 300
    height: 400

    property int created: 0
    property int destroyedCount: 0

    Chat.MessageModel { id: model }

    ListView {
        id: view
        anchors.fill: parent
        model: model
        delegate: Text {
            required property string msgKey
            required property int rev
            property var modelData: { rev; return model.messageFor(msgKey); }
            text: modelData ? modelData.content : ""
            Component.onCompleted: host.created++
            Component.onDestruction: host.destroyedCount++
        }
    }

    HarnessTestCase {
        name: "MessageModel"

        function keys() {
            var out = [];
            for (var i = 0; i < model.count; i++) out.push(model.get(i).msgKey);
            return out;
        }

        function init() {
            model.sync([]);
            host.created = 0;
            host.destroyedCount = 0;
        }

        function test_1_ids_are_given_and_kept() {
            var msgs = [{role: "user", content: "a"}, {role: "assistant", content: "b", id: "keep"}];
            model.sync(msgs);
            verify(msgs[0].id && msgs[0].id.indexOf("m-") === 0);
            compare(keys(), [msgs[0].id, "keep"]);
            var dup = {role: "user", content: "c", id: "keep"};
            model.sync(msgs.concat([dup]));
            verify(dup.id !== "keep", "a duplicate id gets a new one");
            compare(model.count, 3);
        }

        function test_2_append_update_delete_touch_one_row() {
            var msgs = [];
            for (var i = 0; i < 20; i++) msgs.push({role: "user", content: "m" + i});
            model.sync(msgs);
            wait(20);
            var made = host.created;
            msgs = msgs.concat([{role: "assistant", content: "new"}]);
            model.sync(msgs);
            var copy = msgs.slice();
            copy[3] = Object.assign({}, copy[3], {content: "edited"});
            model.sync(copy);
            compare(model.messageFor(copy[3].id).content, "edited");
            compare(model.get(3).rev, 1);
            compare(model.get(4).rev, 0, "untouched rows keep their revision");
            copy.splice(5, 1);
            model.sync(copy);
            compare(model.count, 20);
            compare(keys(), copy.map(function(m) { return m.id; }));
            wait(20);
            compare(host.destroyedCount, 1, "only the deleted message's delegate went away");
            verify(host.created - made <= 1, "at most the appended row was created");
        }

        function test_3_insert_in_the_middle_and_switch_chat() {
            var msgs = [{content: "a"}, {content: "b"}, {content: "c"}];
            model.sync(msgs);
            var withMiddle = [msgs[0], {content: "x"}, msgs[1], msgs[2]];
            model.sync(withMiddle);
            compare(keys(), withMiddle.map(function(m) { return m.id; }));
            var other = [{content: "other"}];
            model.sync(other);
            compare(keys(), [other[0].id]);
            verify(model.messageFor(msgs[0].id) === undefined, "old chat's messages are forgotten");
        }

        function test_4_reorder_still_matches() {
            var msgs = [{content: "a"}, {content: "b"}, {content: "c"}];
            model.sync(msgs);
            var swapped = [msgs[2], msgs[0], msgs[1]];
            model.sync(swapped);
            compare(keys(), swapped.map(function(m) { return m.id; }));
        }
    }
}
