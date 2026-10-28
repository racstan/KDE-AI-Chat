// Chapter 6, voice: Settings -> Voice switches on read aloud and dictation; a reply is read aloud and the
// sentence being read glows and moves along (chat/SpokenGlow.qml); then a question is dictated and sent.
// Nothing plays or records: read aloud uses Qt's silent test voice ("mock", which reports each word like a
// real voice), and dictation goes to the stand-in Speech Note of dev-media.sh (scripts/media/fake_busctl.py),
// which answers with a fixed sentence instead of listening.
import QtQuick

VideoChapter {
    id: chapter

    function settings(next) {
        openPage("ConfigVoice.qml", null, function(page) {
            kit.record("voice-settings", scratch, 80, function(done) {
                kit.later(1500, function() {
                    var read = byName(page, "readAloudSwitch");
                    tap(read, scratch, function() {
                        read.checked = true;
                        kit.later(1200, function() {
                            var dictate = byName(page, "dictationSwitch");
                            tap(dictate, scratch, function() {
                                dictate.checked = true;
                                kit.later(1500, function() { scrollThrough(page, 9000, 1400, function() { kit.later(1200, done); }); });
                            });
                        });
                    });
                });
            }, function() { apply(page); closePage(page, next); });
        });
    }

    // The "Read aloud" button of message i (shown for the picked message, as for the hovered one).
    function readButton(i) {
        var list = body.chatView.list;
        return pages.byPred(list.itemAtIndex(i), function(it) { return it.icon !== undefined && it.text === "Read aloud" && it.visible; });
    }

    function read(next) {
        config.voiceTtsEngine = "system";
        app.voiceManagerRef.ttsPluginOverride = {"system": "mock"};
        tour.goTo(tour.demoChat, function() {
            var list = body.chatView.list;
            var i = app.messages.length - 1;
            kit.record("voice-read", grabItem, 80, function(done) {
                list.positionViewAtIndex(i, ListView.Beginning);
                list.select(i);
                kit.waitFor("the Read aloud button", function() { return chapter.readButton(i) !== null; }, 8000, function() {
                    kit.later(1500, function() {
                        var button = chapter.readButton(i);
                        tap(button, null, function() {
                            button.clicked();
                            list.clearSelection();   // the glow, not the picked message's tint
                            // Most of the reply, then stop (the button again).
                            kit.waitFor("reading to start", function() { return app.voiceManagerRef.isPlaying; }, 8000, function() {
                                kit.later(11000, function() {
                                    app.voiceManagerRef.stopTTS();
                                    app.playingMessageIndex = -1;
                                    list.clearSelection();
                                    kit.later(1500, done);
                                });
                            });
                        });
                    });
                });
            }, next);
        });
    }

    function dictate(next) {
        config.voiceAutoSend = true;
        tour.goTo(tour.tripChat, function() {
            var mic = function() {
                return pages.byPred(body.composerItem, function(it) { return it.Accessible !== undefined && (it.Accessible.name === "Record voice" || it.Accessible.name === "Stop recording") && it.visible; });
            };
            kit.record("voice-dictate", grabItem, 80, function(done) {
                kit.waitFor("the microphone button", function() { return mic() !== null; }, 8000, function() {
                    kit.later(1500, function() {
                        var before = app.messages.length;
                        tap(mic(), null, function() {
                            mic().clicked();
                            kit.waitFor("listening", function() { return app.voiceManagerRef.isRecording; }, 15000, function() {
                                kit.later(3000, function() {
                                    tap(mic(), null, function() {
                                        mic().clicked();
                                        kit.waitFor("the dictated question and its answer", function() {
                                            var m = app.messages;
                                            return !app.loading && m.length >= before + 2 && m[m.length - 1].role === "assistant" && String(m[m.length - 1].content || "") !== "";
                                        }, 30000, function() { kit.later(3500, done); });
                                    });
                                });
                            });
                        });
                    });
                });
            }, next);
        });
    }

    function run(next) { seq([settings, read, dictate], next); }
}
