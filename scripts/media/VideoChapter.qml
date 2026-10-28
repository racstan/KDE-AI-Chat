// Base of the video chapters in VideoMore*.qml: what MediaTour hands over, plus the few things every
// recorded flow needs (a tap marker, typing, scrolling a settings page, showing a settings page,
// running steps in order). A chapter file is `VideoChapter { function run(next) {...} }`.
import QtQuick
import QtQuick.Window

Item {
    id: chapter

    property var tour: null
    property var kit: null
    property var app: null           // main.qml's root: the chat API
    property var body: null          // chat/ChatBody
    property var settingsDialog: null
    property var scheduleOverlay: null
    property var exportDialog: null
    property var plasmoidRef: null
    property var pages: null         // TourSettings (the settings pages)
    property var grabItem: null      // what a frame shows (the widget)

    readonly property var config: plasmoidRef ? plasmoidRef.configuration : null
    readonly property var scratch: pages ? pages.scratch : null

    // The soft ring the video shows where a click happens (the real clicks have no mouse pointer).
    Component {
        id: ringComponent
        Rectangle {
            id: ring
            width: 46; height: 46; radius: 23
            color: "#403daee9"
            border.color: "#3daee9"; border.width: 3
            z: 9000
            opacity: 0
            scale: 1.7
            ParallelAnimation {
                running: true
                NumberAnimation { target: ring; property: "opacity"; from: 0; to: 1; duration: 250 }
                NumberAnimation { target: ring; property: "scale"; from: 1.7; to: 1; duration: 300; easing.type: Easing.OutCubic }
            }
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }

    // Marks `item`, then (after the ring has settled) calls then(): the click itself goes in then().
    function tap(item, host, then) {
        var h = host || tour.target;
        var p = item.mapToItem(h, item.width / 2, item.height / 2);
        var ring = ringComponent.createObject(h, {"x": p.x - 23, "y": p.y - 23});
        kit.later(450, function() {
            if (then) then();
            kit.later(250, function() { ring.opacity = 0; kit.later(300, function() { ring.destroy(); }); });
        });
    }

    // `set(text)` is called with a growing prefix of `text`, one letter every `every` ms.
    function typing(set, text, every, then) {
        var i = 0;
        var step = function() {
            if (i >= text.length) { if (then) then(); return; }
            set(text.substring(0, ++i));
            kit.later(every, step);
        };
        step();
    }

    function typeInto(field, text, every, then) {
        field.forceActiveFocus();
        typing(function(t) { field.text = t; }, text, every, then);
    }

    // Runs functions of the form f(done) one after another, then next().
    function seq(list, next) {
        var i = 0;
        var go = function() {
            if (i >= list.length) { next(); return; }
            list[i++](go);
        };
        go();
    }

    // Waits for the message list to hold a finished reply (the mock ends its replies with "go deeper" or similar).
    function waitReply(extra, then) {
        kit.waitFor("the reply", function() {
            var m = app.messages;
            return !app.loading && m.length >= 2 && m[m.length - 1].role === "assistant" && String(m[m.length - 1].content || "") !== "";
        }, 30000, function() { kit.later(extra, then); });
    }

    // Scrolls a settings page's flickable to `y` over `ms` milliseconds.
    function scrollPage(page, y, ms, then) {
        var flick = page.flickable;
        var from = flick.contentY, to = Math.max(0, Math.min(y, flick.contentHeight - flick.height));
        var steps = Math.max(1, Math.round(ms / 40)), i = 0;
        var step = function() {
            if (i >= steps) { if (then) then(); return; }
            i++;
            flick.contentY = from + (to - from) * (i / steps);
            kit.later(40, step);
        };
        step();
    }

    // Scrolls the whole page slowly, top to bottom (as far as it goes, at most `max` px).
    function scrollThrough(page, ms, max, then) {
        var flick = page.flickable;
        var room = Math.max(0, Math.min(flick.contentHeight - flick.height, max || 100000));
        if (room < 20) { kit.later(ms / 2, then); return; }
        scrollPage(page, room, ms, function() { kit.later(700, then); });
    }

    function byText(page, text) { return pages.byText(page, text); }
    function byName(page, name) { return kit.find(page, name); }

    // Creates a settings page in the overlay (what Plasma's settings window shows) and gives it to then(page).
    function openPage(file, ready, then) {
        var component = Qt.createComponent(Qt.resolvedUrl("../" + file));
        if (component.status !== Component.Ready) { kit.fail(file + " could not load: " + component.errorString()); return; }
        scratch.visible = true;
        scratch.z = 5000;
        var page = component.createObject(scratch, {"width": scratch.width, "height": scratch.height});
        if (!page) { kit.fail(file + " could not be created"); return; }
        pages.fill(page);
        kit.later(800, function() {
            if (ready) kit.waitFor(file + " to be ready", function() { return ready(page); }, 15000, function() { kit.later(300, function() { then(page); }); });
            else then(page);
        });
    }

    function closePage(page, then) {
        page.destroy();
        scratch.visible = false;   // the window goes back from maximized to the widget's size (MediaTour)
        var tries = 0;
        kit.waitFor("the window back at the widget's size", function() {
            var win = tour.target.Window.window;
            // Back from maximized; plasmawindowed may keep a minimum a little above the widget's width (500 px).
            var ok = win && win.visibility !== Window.Maximized && tour.target.width <= tour.width_ + 60
                && Math.abs(tour.target.height - tour.height_) < 2;
            if (!ok && win && ++tries % 10 === 0) {   // the window manager may still be restoring: ask again
                console.log("MEDIA_RESIZE target=" + tour.target.width + "x" + tour.target.height + " window=" + win.width + "x" + win.height + " min=" + win.minimumWidth + " visibility=" + win.visibility);
                win.minimumWidth = Math.min(win.minimumWidth, tour.width_);
                if (win.visibility === Window.Maximized) win.showNormal();
                win.width = tour.width_;
                win.height = tour.height_;
            }
            return ok;
        }, 15000, function() { kit.later(400, then); });
    }

    // What Plasma does on OK/Apply: every cfg_<key> that changed goes to the widget's configuration.
    function apply(page) {
        for (var name in page) {
            if (name.indexOf("cfg_") !== 0 || /Default$/.test(name) || typeof page[name] === "function")
                continue;
            var key = name.substring(4);
            if (config[key] === undefined || config[key] === null) continue;
            if (config[key] !== page[name])
                config[key] = page[name];
        }
    }

    // A popup (menu) lives in the window's overlay: move its visual item into `host` to have it in the frames.
    function pull(popup, host) {
        var item = popup.contentItem ? popup.contentItem.parent : null;
        if (item) { item.parent = host || tour.target; item.z = 6000; }
    }

    function run(next) { next(); }
}
