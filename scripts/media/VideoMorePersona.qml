// Chapter 2, personality and avatars: Settings -> Personality is filled in by typing (name, about you, tone,
// the AI's name and personality), the Developer's animated GIF becomes the AI's avatar and the panel icon
// (the file check is the helper's own), and a message shows the moving avatar in the chat. Plasma's OK/Apply
// is what VideoChapter.apply() stands in for; the native file dialog can't be captured, so the picked
// file goes straight to the picker's own setMedia()/choose(), which is what the dialog calls.
import QtQuick
import QtCore

VideoChapter {
    id: chapter

    readonly property string gif: String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)).replace(/^file:\/\//, "") + "/avatars/beagle.gif"

    function personalityPage(next) {
        openPage("ConfigPersonality.qml", null, function(page) {
            // Start from an empty form, then fill it in.
            page.cfg_userName = ""; page.cfg_userAbout = ""; page.cfg_userTone = ""; page.cfg_aiName = ""; page.cfg_aiPersonality = "";
            page.cfg_userAvatar = ""; page.cfg_aiAvatar = "";
            kit.later(600, function() {
                kit.record("personality", scratch, 80, function(done) {
                    kit.later(1200, function() {
                        typeInto(byName(page, "userNameField"), "Alex", 160, function() {
                            kit.later(500, function() {
                                var about = byName(page, "userAboutArea");
                                typing(function(t) { about.text = t; }, "I build small apps and I'm learning Rust.", 55, function() {
                                    var tone = byName(page, "toneCombo");
                                    tap(tone, scratch, function() {
                                        tone.currentIndex = 1; tone.activated(1);
                                        kit.later(900, function() {
                                            pages.scrollTo(page, byName(page, "aiNameField"));
                                            kit.later(900, function() {
                                                typeInto(byName(page, "aiNameField"), "Nova", 160, function() {
                                                    var pers = byName(page, "personalityCombo");
                                                    kit.later(500, function() {
                                                        tap(pers, scratch, function() {
                                                            pers.currentIndex = 1; pers.activated(1);
                                                            kit.later(1500, done);
                                                        });
                                                    });
                                                });
                                            });
                                        });
                                    });
                                });
                            });
                        });
                    });
                }, function() {
                    apply(page);
                    closePage(page, next);
                });
            });
        });
    }

    function avatarPage(next) {
        openPage("ConfigPersonality.qml", null, function(page) {
            var picker = byName(page, "avatarButton");
            var holder = pages.byPred(page, function(i) { return i.prefix === "avatar" && i.setMedia !== undefined; });
            pages.scrollTo(page, picker);
            kit.later(600, function() {
                kit.record("avatar-picker", scratch, 80, function(done) {
                    kit.later(1000, function() {
                        tap(picker, scratch, function() {
                            holder.menu.popup(picker, 0, picker.height);   // what pressing the button does
                            kit.waitFor("the avatar menu", function() { return holder.menu.opened; }, 5000, function() {
                                pull(holder.menu, scratch);
                                kit.later(2200, function() {
                                    holder.menu.close();
                                    kit.later(500, function() {
                                        holder.setMedia(chapter.gif, "animated");   // what "Choose Animated Image…" does with the picked file
                                        kit.waitFor("the checked avatar", function() { return holder.value === chapter.gif; }, 8000, function() { kit.later(3500, done); });
                                    });
                                });
                            });
                        });
                    });
                }, function() {
                    apply(page);
                    closePage(page, next);
                });
            });
        });
    }

    function panelIcon(next) {
        openPage("ConfigAppearance.qml", null, function(page) {
            var icon = pages.byPred(page, function(i) { return i.customIcon !== undefined && i.mode !== undefined && i.choose !== undefined; });
            pages.scrollTo(page, icon);
            kit.later(600, function() {
                kit.record("panel-icon", scratch, 80, function(done) {
                    kit.later(1200, function() {
                        var button = byName(page, "iconButton");
                        tap(button, scratch, function() {
                            icon.choose(chapter.gif, "animated");
                            kit.waitFor("the animated icon", function() { return icon.shown === "animated"; }, 8000, function() { kit.later(4500, done); });
                        });
                    });
                }, function() {
                    apply(page);
                    closePage(page, next);
                });
            });
        });
    }

    function chatWithAvatar(next) {
        tour.newChat(function() {
            kit.record("avatar-chat", grabItem, 80, function(done) {
                kit.later(1200, function() {
                    typing(function(t) { app.chatInputText = t; }, "Hi! Tell me who you are.", 70, function() {
                        kit.later(400, function() { app.sendMessage(); waitReply(5000, done); });
                    });
                });
            }, function() { tour.deleteOpenChat(next); });
        });
    }

    function run(next) {
        seq([personalityPage, avatarPage, panelIcon, chatWithAvatar], next);
    }
}
