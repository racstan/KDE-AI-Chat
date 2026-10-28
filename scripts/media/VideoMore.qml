// The video's other chapters: first run, personality and avatars, memory, the three modes, schedules, voice, settings tour, small touches.
// Handed the same things as MediaTour's other parts; run(next) records this chapter's flows with
// kit.record("<flow name>", grabItem, 80, ...) and calls next() when done. Captions for each flow
// go in scripts/media/video_start.py / video_more.py / video_settings.py (youtube.py). Run only this chapter with DEV_MEDIA_ONLY=videoMore scripts/dev-media.sh light.
import QtQuick

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

    function run(next) {
        next();
    }
}
