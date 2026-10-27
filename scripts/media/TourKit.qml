// Helpers for the docs-media tour (scripts/dev-media.sh): waiting, saving the
// widget's own item with grabToImage (never a screen grab), recording frame
// sequences, and failing loudly. Every outcome is logged on one line:
//   MEDIA_SAVED <path>   MEDIA_FAIL <why>   MEDIA_DONE
// Used inside the staged copy of the widget only (see dev-run.sh DEV_MEDIA_TOUR).
import QtQuick

Item {
    id: kit

    // Folder for the stills (docs/media), the theme name in each file name,
    // pixel ratio of the saved images, and where the frame folders go.
    property string outDir: ""
    property string theme: "light"
    property real ratio: 2
    property string framesDir: ""
    property bool failed: false
    property int saving: 0
    // Steps that are allowed to fail (the extra states): guard(name, next) makes a failure log
    // MEDIA_SKIP and carry on with next(); every timer of the failed step is dropped (gen).
    property int gen: 0
    property var onSkip: null
    property string guarded: ""

    function guard(name, next) {
        kit.guarded = name;
        kit.onSkip = next;
    }
    function unguard() { kit.guarded = ""; kit.onSkip = null; }

    function fail(why) {
        if (kit.failed)
            return;
        if (kit.onSkip) {
            var skip = kit.onSkip;
            console.log("MEDIA_SKIP " + kit.guarded + ": " + why);
            kit.unguard();
            kit.gen++;
            skip();
            return;
        }
        kit.failed = true;
        console.log("MEDIA_FAIL " + why);
    }

    function path(url) { return String(url).replace(/^file:\/\//, ""); }

    // Calls then() after ms milliseconds.
    function later(ms, then) {
        var t = timerComponent.createObject(kit, {"interval": Math.max(1, ms)});
        var g = kit.gen;
        t.triggered.connect(function() { t.destroy(); if (!kit.failed && g === kit.gen) then(); });
        t.start();
    }

    // Calls then() once test() is true (polled every 50 ms); fails after `ms`.
    function waitFor(what, test, ms, then) {
        var waited = 0, g = kit.gen;
        var t = timerComponent.createObject(kit, {"interval": 50, "repeat": true});
        t.triggered.connect(function() {
            if (g !== kit.gen) { t.destroy(); return; }
            var ok = false;
            try { ok = !!test(); } catch (e) { ok = false; if (waited % 1000 === 0) console.log("MEDIA_WAITERR " + what + ": " + e); }
            waited += 50;
            if (ok || waited > ms || kit.failed) {
                t.destroy();
                if (ok && !kit.failed) then();
                else kit.fail("timed out waiting for " + what);
            }
        });
        t.start();
    }

    // The first item under `item` whose objectName is `name` (visual children
    // and Loader items), or null.
    function find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = kit.find(kids[i], name);
            if (found)
                return found;
        }
        return null;
    }

    // Saves `item` as <outDir>/<name>-<theme>.png, then calls then().
    function shot(item, name, then) {
        var file = kit.outDir + "/" + name + "-" + kit.theme + ".png";
        kit.save(item, file, kit.ratio, then);
    }

    function save(item, file, ratio, then) {
        if (item.width < 2 || item.height < 2) {
            kit.fail("nothing to save for " + file + " (item is " + item.width + "x" + item.height + ")");
            return;
        }
        var size = Qt.size(Math.round(item.width * ratio), Math.round(item.height * ratio));
        kit.saving++;
        var settled = false;
        kit.later(15000, function() { if (!settled) kit.fail("grabToImage never finished for " + file); });
        var started = item.grabToImage(function(result) {
            settled = true;
            var ok = result.saveToFile(file);
            kit.saving--;
            if (!ok) { kit.fail("could not save " + file); return; }
            console.log("MEDIA_SAVED " + file);
            if (then) then();
        }, size);
        if (!started) { kit.saving--; kit.fail("grabToImage refused to start for " + file); }
    }

    // Saves a frame of `item` every `every` ms into <framesDir>/<flow>/NNNN.png
    // while run() is going; run(done) must call done() when the flow is over.
    // Then calls then().
    function record(flow, item, every, run, then) {
        var dir = kit.framesDir + "/" + flow;
        var count = 0, recording = true;
        var t = timerComponent.createObject(kit, {"interval": every, "repeat": true});
        var frame = function() {
            var n = ("0000" + (++count)).slice(-4);
            var size = Qt.size(Math.round(item.width), Math.round(item.height));
            kit.saving++;
            item.grabToImage(function(result) {
                kit.saving--;
                if (!result.saveToFile(dir + "/" + n + ".png"))
                    kit.fail("could not save frame " + n + " of " + flow);
            }, size);
        };
        t.triggered.connect(frame);
        frame();
        t.start();
        run(function() {
            t.destroy();
            kit.waitFor("frames of " + flow + " to be written", function() { return kit.saving === 0; }, 20000, function() {
                console.log("MEDIA_FRAMES " + dir + " " + count);
                then();
            });
        });
    }

    Component { id: timerComponent; Timer {} }
}
