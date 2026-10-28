// The settings pages for the docs media: each page of contents/config/config.qml
// is created inside the running (staged) widget, so it uses the sandbox's real
// helper, memories, schedules and settings, and is saved at 640x560 as
// settings-<name>-<theme>.png. Plasma's settings window is a separate window
// that can't be reached from QML, so the pages are shown here the way
// tests/qml/tst_config_pages.qml loads them: cfg_* properties filled from the
// saved settings, as Plasma does.
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: pages

    property var kit: null
    property var plasmoidRef: null
    property var host: null
    property Item scratch: null

    readonly property var list: [
        {"file": "ConfigConnection.qml", "name": "settings-connection"},
        {"file": "ConfigChat.qml", "name": "settings-chat"},
        {"file": "ConfigPersonality.qml", "name": "settings-personality"},
        {"file": "ConfigMemory.qml", "name": "settings-memory", "ready": function(p) { return !pages.shown(p, "memoryEmpty") && pages.kit.find(p, "memorySearch") !== null; }},
        {"file": "ConfigSchedules.qml", "name": "settings-schedules", "ready": function(p) { return pages.kit.find(p, "scheduleRow") !== null; }},
        {"file": "ConfigVoice.qml", "name": "settings-voice"},
        {"file": "ConfigAppearance.qml", "name": "settings-appearance"},
        {"file": "ConfigDesktop.qml", "name": "settings-desktop"},
        {"file": "ConfigStorage.qml", "name": "settings-storage", "ready": function(p) { return pages.kit.find(p, "storageTotal") !== null; }},
        {"file": "ConfigSupport.qml", "name": "settings-support"},
        {"file": "ConfigConnection.qml", "name": "settings-setup-check", "check": true}
    ]

    // Extra shots (guarded: one that can't be reached is skipped, see TourKit.guard).
    readonly property var extraList: [
        {"file": "ConfigConnection.qml", "name": "settings-providers-find", "prep": function(page, done) {
            var button = pages.byText(page, "Find local servers");
            if (!button) { kit.fail("the Find local servers button was not found"); return; }
            button.clicked();
            kit.later(2500, function() { pages.scrollTo(page, pages.byText(page, "Through OpenCode"), 0); kit.later(400, done); });   // the page ends below this: start at a whole row, not a cut line
        }},
        {"file": "ConfigPersonality.qml", "name": "settings-avatar-picker", "prep": function(page, done) {
            var button = kit.find(page, "avatarButton");
            var picker = pages.byPred(page, function(i) { return i.menu !== undefined && i.prefix === "avatar"; });
            if (!button || !picker) { kit.fail("the avatar picker was not found"); return; }
            button.clicked();
            kit.waitFor("the picker menu", function() { return picker.menu.opened; }, 5000, function() {
                var item = picker.menu.contentItem.parent;
                item.parent = scratch; item.z = 6000;
                kit.later(500, done);
            });
        }},
        {"file": "ConfigAppearance.qml", "name": "settings-icon", "prep": function(page, done) {
            var icon = pages.byPred(page, function(i) { return i.customIcon !== undefined && i.mode !== undefined; });
            if (!icon) { kit.fail("the icon settings were not found"); return; }
            pages.scrollTo(page, icon);
            kit.later(400, done);
        }},
        {"file": "ConfigVoice.qml", "name": "settings-voice-speechnote", "prep": function(page, done) {
            page.cfg_voiceTtsEnabled = true;
            page.cfg_voiceTtsEngine = "speechnote";
            kit.later(800, done);
        }},
        {"file": "ConfigSchedules.qml", "name": "settings-schedule-dialog", "ready": function(p) { return pages.kit.find(p, "scheduleRow") !== null; },
         "prep": function(page, done) {
            var row = kit.find(page, "scheduleRow");
            page.edit(row.item);
            kit.waitFor("the schedule dialog", function() { return page.view === "edit"; }, 5000, function() { kit.later(900, done); });
        }}
    ]

    function byPred(item, test) {
        if (!item) return null;
        if (test(item)) return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = byPred(kids[i], test);
            if (found) return found;
        }
        return null;
    }
    function byText(page, text) { return byPred(page, function(i) { return i.text === text; }); }

    function shown(page, objectName) {
        var item = kit.find(page, objectName);
        return item !== null && item.visible;
    }

    // Plasma fills a page's cfg_<key> from the saved <key> setting.
    function fill(page) {
        var config = plasmoidRef.configuration;
        for (var name in page) {
            if (name.indexOf("cfg_") !== 0 || /Default$/.test(name) || typeof page[name] === "function")
                continue;
            var key = name.substring(4);
            if (config[key] !== undefined && config[key] !== null)
                page[name] = config[key];
        }
    }

    // Scrolls the page so `item` is at the top.
    function scrollTo(page, item, gap) {
        var flick = page.flickable;
        if (!flick || !item)
            return;
        var y = item.mapToItem(flick.contentItem, 0, 0).y;
        flick.contentY = Math.max(0, Math.min(y - (gap === undefined ? Kirigami.Units.largeSpacing : gap), flick.contentHeight - flick.height));
    }

    function one(entry, then) {
        var component = Qt.createComponent(Qt.resolvedUrl("../" + entry.file));
        if (component.status !== Component.Ready) {
            kit.fail(entry.file + " could not load: " + component.errorString());
            return;
        }
        var page = component.createObject(scratch, {"width": scratch.width, "height": scratch.height});
        if (!page) {
            kit.fail(entry.file + " could not be created");
            return;
        }
        fill(page);
        var finish = function() {
            kit.later(900, function() {
                kit.shot(scratch, entry.name, function() { page.destroy(); kit.later(400, then); });
            });
        };
        var settled = function() {
            if (page.flickable && !entry.prep)
                page.flickable.contentY = 0;   // every page starts at its first heading
            if (entry.prep) { entry.prep(page, finish); return; }
            if (!entry.check) { finish(); return; }
            var button = kit.find(page, "setupCheckButton");
            if (!button) { kit.fail("the Check setup button was not found"); return; }
            button.clicked();
            kit.waitFor("the setup check result", function() { return pages.shown(page, "setupCheckSummary"); }, 30000, function() {
                kit.later(500, function() { scrollTo(page, byText(page, "Through OpenCode"), 0); finish(); });
            });
        };
        kit.later(800, function() {
            if (entry.ready)
                kit.waitFor(entry.name + " to show its data", function() { return entry.ready(page); }, 15000, settled);
            else
                settled();
        });
    }

    function runList(entries, guarded, next) {
        scratch.visible = true;
        scratch.z = 5000;
        var i = 0;
        var step = function() {
            if (i >= entries.length) { scratch.visible = false; next(); return; }
            var entry = entries[i++];
            if (guarded) kit.guard(entry.name, function() {
                for (var c = scratch.children.length - 1; c > 0; c--) scratch.children[c].destroy();   // the first child is the background
                kit.later(1, step);
            });
            pages.one(entry, function() { kit.unguard(); step(); });
        };
        step();
    }
    function run(next) { runList(list, false, next); }
    function runExtras(next) { runList(extraList, true, next); }
}
