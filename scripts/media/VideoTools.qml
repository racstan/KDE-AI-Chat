// Shared helpers of the video's chat chapters (VideoChat*.qml): starting a flow in a scratch chat,
// typing and sending, waiting for replies, pressing the buttons of a message and putting everything
// away again. Nothing here fakes widget behaviour: it calls the same functions the widget's own
// buttons and keys call (main.qml's API, the chat's list and composer).
import QtQuick
import QtQuick.Controls as QQC2

Item {
    id: tools

    property var tour: null
    property var kit: null
    property var app: null
    property var body: null
    property var grabItem: null

    readonly property var list: body && body.chatView ? body.chatView.list : null
    readonly property var composer: body ? body.composerItem : null

    function type(text, every, then) { tour.typeInto(text, every, then); }

    // The first item under `item` for which pred(item) is true, or null.
    function walk(item, pred) {
        if (!item)
            return null;
        try { if (pred(item)) return item; } catch (e) {}
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = tools.walk(kids[i], pred);
            if (found)
                return found;
        }
        return null;
    }

    function delegateAt(i) { return list ? list.itemAtIndex(i) : null; }

    // The visible button with this text (a message action, see chat/MessageActions.qml) on message i.
    function button(i, label) {
        return tools.walk(tools.delegateAt(i), function(it) { return it.icon !== undefined && it.text === label && it.visible && it.enabled; });
    }

    // Picks message i (the keyboard's Up/Down do the same), waits for its button and presses it.
    function press(i, label, then, settle) {
        list.select(i);
        kit.waitFor("the " + label + " button of message " + i, function() { return tools.button(i, label) !== null; }, 8000, function() {
            kit.later(700, function() {
                tools.button(i, label).clicked();
                kit.later(settle === undefined ? 900 : settle, then);
            });
        });
    }

    // A Popup created inside `owner` (an object among its data), by objectName; pull() moves its visual
    // item into the widget's tree so the frames show it (the trick of MediaExtras.pull).
    function popupIn(owner, name) {
        var data = owner ? owner.data || [] : [];
        for (var i = 0; i < data.length; i++)
            if (data[i].objectName === name) return data[i];
        return null;
    }
    function pull(popup) {
        var item = popup.contentItem ? popup.contentItem.parent : null;
        if (item) { item.parent = tools.grabItem; item.z = 6000; }
    }
    // An item inside any open popup (the window's overlay), by objectName; pullOverlay() moves that popup's
    // visual item into the widget's tree. For popups the widget creates on the fly (no handle to them).
    readonly property var overlay: QQC2.Overlay.overlay
    function inOverlay(name) {
        return tools.walk(tools.overlay, function(it) { return it.objectName === name && it.visible; });
    }
    function pullOverlay(inner) {
        var top = inner;
        while (top.parent && top.parent !== tools.overlay) top = top.parent;
        if (top.parent === tools.overlay) { top.parent = tools.grabItem; top.z = 6000; }
    }

    // The composer's command runner (chat/CommandRunner.qml): what Enter does with a "/command" line.
    function runner() {
        var data = composer ? composer.data || [] : [];
        for (var i = 0; i < data.length; i++)
            if (data[i].notice !== undefined && data[i].track !== undefined && data[i].runMode !== undefined) return data[i];
        return null;
    }
    function runCommand(text) {
        var r = tools.runner();
        if (!r) { kit.fail("the command runner was not found"); return; }
        r.run(text);
        app.chatInputText = "";
    }

    function last() { return app.messages.length ? app.messages[app.messages.length - 1] : {}; }

    // The reply is complete: nothing loading, nothing queued, the last message is an answer.
    function answered() {
        var m = app.messages;
        if (app.loading || m.length < 2)
            return false;
        for (var i = 0; i < m.length; i++)
            if (m[i].role === "queued")
                return false;
        var l = m[m.length - 1];
        return l.role === "assistant" && String(l.content || "").length > 0;
    }
    function waitAnswer(then, after) { kit.waitFor("the reply", tools.answered, 40000, function() { kit.later(after === undefined ? 900 : after, then); }); }
    function streaming(chars) { return app.loading && String(app.currentStreamText || "").length >= chars; }

    // Types `text` into the box and sends it.
    function ask(text, then, every) {
        tools.type(text, every || 40, function() { kit.later(400, function() { app.sendMessage(); then(); }); });
    }

    // Both a flow's start and end: a fresh scratch chat in front, everything of the flow put away after.
    function fresh(then) { tour.newChat(then); }

    function tidy(then) {
        app.editingMessageIndex = -1;
        app.editingDraft = "";
        app.chatInputText = "";
        app.historyOnlyMode = false;
        if (composer) composer.quoteChips.quotes = [];
        app.attachedFiles = [];
        if (list) list.clearSelection();
        if (app.incognito && app.incognito.active) {
            app.messages = [];
            app.incognito.close();
        }
        tour.dismissUndo();
        var id = app.currentSessionId;
        var go = function() { kit.later(600, function() { tour.dismissUndo(); kit.later(300, then); }); };
        kit.later(400, function() {
            if (String(id).indexOf("s-1000000000") !== 0) tour.deleteOpenChat(go); else go();
        });
    }

    // Records `name` in a fresh scratch chat: run(done) does the flow, then everything is put away.
    function flow(name, run, next) {
        tools.fresh(function() {
            app.chatInputText = "";
            kit.record(name, tools.grabItem, 80, run, function() { tools.tidy(next); });
        });
    }

    // Records `name` in the seeded chat `chatId`; the caller's run must put back what it changes.
    function flowIn(chatId, name, run, next) {
        tour.goTo(chatId, function() {
            kit.record(name, tools.grabItem, 80, run, function() { tools.tidy(next); });
        });
    }

    // Runs functions of the form f(next) one after another.
    function chain(fns, next) {
        var i = 0;
        var go = function() { if (i >= fns.length) { next(); return; } fns[i++](go); };
        go();
    }

    // Scrolls a Flickable down to contentY `to` in steps (a settings page).
    function scrollItem(flick, to, step, every, then) {
        var go = function() {
            var target = Math.min(to, flick.contentHeight - flick.height);
            if (flick.contentY >= target - 1) { then(); return; }
            flick.contentY = Math.min(target, flick.contentY + step);
            kit.later(every, go);
        };
        go();
    }

    // Scrolls the chat view smoothly down to content pixel `to` in steps.
    function scroll(to, step, every, then) {
        var go = function() {
            var y = list.contentY;
            var target = Math.min(to, list.contentHeight - list.height + list.originY);
            if (y >= target - 1) { then(); return; }
            list.contentY = Math.min(target, y + step);
            kit.later(every, go);
        };
        go();
    }
}
