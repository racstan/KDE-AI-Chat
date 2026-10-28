// The video's chat chapters: everything inside a chat (sending, messages, quoting, organising, keyboard, commands, attachments, incognito, questions).
// Handed the same things as MediaTour's other parts; run(next) records this chapter's flows with
// kit.record("<flow name>", grabItem, 80, ...) and calls next() when done. Captions for each flow
// go in scripts/media/video_chat.py (youtube.py). Run only this chapter with DEV_MEDIA_ONLY=videoChat scripts/dev-media.sh light.
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
