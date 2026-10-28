// The video's other chapters: 1 first run, 2 personality and avatars, 3 memory, 4 the three modes, 5 schedules,
// 6 voice, 7 small touches, 8 settings tour. Each chapter is its own file (VideoMore<Name>.qml, all a
// VideoChapter) and records its flows with kit.record("<flow name>", grabItem, 80, ...); the captions of the
// flows are in scripts/media/video_start.py (1), video_more.py (2-7) and video_settings.py (8).
// Run only this part with DEV_MEDIA_ONLY=videoMore scripts/dev-media.sh light; DEV_MEDIA_PART=modes,voice (chapter
// names below) runs just those chapters. The widget's configuration is put back at the end.
import QtQuick
import QtCore

VideoChapter {
    id: more

    VideoMoreStart { id: start; tour: more.tour; kit: more.kit; app: more.app; body: more.body; settingsDialog: more.settingsDialog
        scheduleOverlay: more.scheduleOverlay; exportDialog: more.exportDialog; plasmoidRef: more.plasmoidRef; pages: more.pages; grabItem: more.grabItem }
    VideoMorePersona { id: persona; tour: more.tour; kit: more.kit; app: more.app; body: more.body; settingsDialog: more.settingsDialog
        scheduleOverlay: more.scheduleOverlay; exportDialog: more.exportDialog; plasmoidRef: more.plasmoidRef; pages: more.pages; grabItem: more.grabItem }
    VideoMoreMemory { id: memory; tour: more.tour; kit: more.kit; app: more.app; body: more.body; settingsDialog: more.settingsDialog
        scheduleOverlay: more.scheduleOverlay; exportDialog: more.exportDialog; plasmoidRef: more.plasmoidRef; pages: more.pages; grabItem: more.grabItem }
    VideoMoreModes { id: modes; tour: more.tour; kit: more.kit; app: more.app; body: more.body; settingsDialog: more.settingsDialog
        scheduleOverlay: more.scheduleOverlay; exportDialog: more.exportDialog; plasmoidRef: more.plasmoidRef; pages: more.pages; grabItem: more.grabItem }
    VideoMoreSchedule { id: schedule; tour: more.tour; kit: more.kit; app: more.app; body: more.body; settingsDialog: more.settingsDialog
        scheduleOverlay: more.scheduleOverlay; exportDialog: more.exportDialog; plasmoidRef: more.plasmoidRef; pages: more.pages; grabItem: more.grabItem }
    VideoMoreVoice { id: voice; tour: more.tour; kit: more.kit; app: more.app; body: more.body; settingsDialog: more.settingsDialog
        scheduleOverlay: more.scheduleOverlay; exportDialog: more.exportDialog; plasmoidRef: more.plasmoidRef; pages: more.pages; grabItem: more.grabItem }
    VideoMoreTouches { id: touches; tour: more.tour; kit: more.kit; app: more.app; body: more.body; settingsDialog: more.settingsDialog
        scheduleOverlay: more.scheduleOverlay; exportDialog: more.exportDialog; plasmoidRef: more.plasmoidRef; pages: more.pages; grabItem: more.grabItem }
    VideoMoreSettings { id: settingsTour; tour: more.tour; kit: more.kit; app: more.app; body: more.body; settingsDialog: more.settingsDialog
        scheduleOverlay: more.scheduleOverlay; exportDialog: more.exportDialog; plasmoidRef: more.plasmoidRef; pages: more.pages; grabItem: more.grabItem }

    // The chapters to run: all, or those named in <data>/media-part.txt (written by dev-media.sh from DEV_MEDIA_PART).
    function wanted() {
        var text = "";
        try {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)) + "/media-part.txt", false);
            xhr.send();
            text = String(xhr.responseText || "").trim();
        } catch (e) { text = ""; }
        return text === "" ? [] : text.split(",");
    }

    function run(next) {
        var all = [["start", start], ["persona", persona], ["memory", memory], ["modes", modes], ["schedule", schedule],
                   ["voice", voice], ["touches", touches], ["settings", settingsTour]];
        var only = wanted();
        var chosen = all.filter(function(c) { return only.length === 0 || only.indexOf(c[0]) >= 0; });
        var saved = {};
        config.keys().forEach(function(k) { saved[k] = config[k]; });
        seq(chosen.map(function(c) { return c[1].run; }), function() {
            for (var k in saved)
                if (config[k] !== saved[k]) config[k] = saved[k];
            tour.goTo(tour.demoChat, next);
        });
    }
}
