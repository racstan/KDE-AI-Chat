// The video's chat chapters: everything inside a chat (sending, messages, quoting, remembering, organising,
// keyboard, commands, attachments, incognito, questions). Handed the same things as MediaTour's other
// parts; run(next) records this chapter's flows with kit.record("<flow name>", grabItem, 80, ...) and
// calls next() when done. The flows live in VideoChatA/B/C.qml (chapters 1-4, 5-6, 7-10), their helpers
// in VideoTools.qml. Captions for each flow go in scripts/media/video_chat.py (youtube.py).
// Run only this chapter with DEV_MEDIA_ONLY=videoChat scripts/dev-media.sh light.
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

    // dev-media.sh makes a frames folder for every kit.record("<name>" it finds in the tour files; the flows
    // are recorded through tools.flow(), so their names are listed here:
    //   kit.record("chat-stop"  kit.record("chat-queue"  kit.record("chat-formatted"  kit.record("chat-messages"
    //   kit.record("chat-quote-jump"  kit.record("chat-remember-flow"
    //   kit.record("chat-pin"  kit.record("chat-rename"  kit.record("chat-projects"  kit.record("chat-search-jump"
    //   kit.record("keys-new"  kit.record("keys-incognito"  kit.record("keys-pick"  kit.record("keys-edit"
    //   kit.record("keys-quote"  kit.record("keys-page"  kit.record("keys-list"
    //   kit.record("chat-commands-list"  kit.record("chat-template"  kit.record("chat-model-cmd"  kit.record("chat-image-cmd"
    //   kit.record("chat-attach"  kit.record("chat-incognito-flow"  kit.record("chat-ask-flow"

    VideoTools { id: tools; tour: chapter.tour; kit: chapter.kit; app: chapter.app; body: chapter.body; grabItem: chapter.grabItem }
    VideoChatA { id: partA; tour: chapter.tour; kit: chapter.kit; app: chapter.app; tools: tools }
    VideoChatB { id: partB; tour: chapter.tour; kit: chapter.kit; app: chapter.app; tools: tools; pages: chapter.pages }
    VideoChatC { id: partC; tour: chapter.tour; kit: chapter.kit; app: chapter.app; tools: tools; plasmoidRef: chapter.plasmoidRef }

    function run(next) {
        tools.chain([partA.run, partB.run, partC.run], next);
    }
}
