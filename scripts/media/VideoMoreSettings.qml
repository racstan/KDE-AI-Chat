// Chapter 8, the settings tour: each settings page the earlier chapters did not show, opened as Plasma's
// settings window shows it (820 px wide) and scrolled slowly from top to bottom. Captions in
// scripts/media/video_settings.py, one per page (flow "settings-tour-<page>").
import QtQuick

VideoChapter {
    id: chapter

    // [flow name, page file, ready test]
    readonly property var tourPages: [
        ["settings-tour-connection", "ConfigConnection.qml"],
        ["settings-tour-chat", "ConfigChat.qml"],
        ["settings-tour-appearance", "ConfigAppearance.qml"],
        ["settings-tour-desktop", "ConfigDesktop.qml"],
        ["settings-tour-storage", "ConfigStorage.qml"],
        ["settings-tour-support", "ConfigSupport.qml"]
    ]
    // dev-media.sh finds the flows by these calls' names:
    //   kit.record("settings-tour-connection"  kit.record("settings-tour-chat"  kit.record("settings-tour-appearance"
    //   kit.record("settings-tour-desktop"  kit.record("settings-tour-storage"  kit.record("settings-tour-support"

    function show(entry, next) {
        openPage(entry[1], null, function(page) {
            kit.later(1200, function() {
                kit.record(entry[0], scratch, 80, function(done) {
                    kit.later(2000, function() { scrollThrough(page, 12000, 100000, function() { kit.later(1500, done); }); });
                }, function() { closePage(page, next); });
            });
        });
    }

    function run(next) {
        seq(tourPages.map(function(entry) { return function(go) { chapter.show(entry, go); }; }), next);
    }
}
