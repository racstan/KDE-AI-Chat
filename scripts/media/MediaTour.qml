// The docs-media tour (scripts/dev-media.sh): walks the real widget through
// each state the docs show and saves the widget's own item (grabToImage, never
// a screen grab) as <outDir>/<state>-<theme>.png, then, when `flows` is on,
// records the short flows as frame sequences. Staged into the dev copy of
// FullRepresentationContent only (dev-run.sh DEV_MEDIA_TOUR); the demo data
// comes from scripts/media/seed.py, the replies from scripts/media/mock_openai.py.
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

Item {
    id: tour

    // Handed over by FullRepresentationContent, whose ids this file can't see.
    property var target: null        // the widget's root item (what is saved)
    property var app: null           // main.qml's root: the chat API
    property var body: null          // chat/ChatBody
    property var settingsDialog: null
    property var scheduleOverlay: null
    property var exportDialog: null
    property var plasmoidRef: null
    property bool flows: false
    // Comma-separated step names to run instead of the whole tour (DEV_MEDIA_ONLY); see steps() below.
    property string only: ""
    property string themeName: "light"
    property string outDir: ""
    property string framesDir: ""
    readonly property real width_: 460
    readonly property real height_: 640

    readonly property string demoChat: "s-1000000000001-0001"
    readonly property string tripChat: "s-1000000000002-0002"

    TourKit {
        id: kit
        outDir: tour.outDir
        theme: tour.themeName
        framesDir: tour.framesDir
    }

    MediaExtras {
        id: extras
        tour: tour
        kit: kit
    }

    VideoChat {
        id: videoChat
        tour: tour; kit: kit; app: tour.app; body: tour.body; settingsDialog: tour.settingsDialog
        scheduleOverlay: tour.scheduleOverlay; exportDialog: tour.exportDialog; plasmoidRef: tour.plasmoidRef
        pages: pages; grabItem: tour.target
    }

    VideoMore {
        id: videoMore
        tour: tour; kit: kit; app: tour.app; body: tour.body; settingsDialog: tour.settingsDialog
        scheduleOverlay: tour.scheduleOverlay; exportDialog: tour.exportDialog; plasmoidRef: tour.plasmoidRef
        pages: pages; grabItem: tour.target
    }

    TourSettings {
        id: pages
        kit: kit
        plasmoidRef: tour.plasmoidRef
        host: tour.target
        scratch: scratch
    }

    // Parent of the settings pages, kept out of sight behind the chat.
    Item {
        id: scratch
        width: 640
        height: 560
        visible: false
        Rectangle { anchors.fill: parent; color: Kirigami.Theme.backgroundColor }
    }
    readonly property color themeBackground: Kirigami.Theme.backgroundColor

    function composer() { return body.composerItem; }

    function typeInto(text, every, then) {
        var i = 0;
        var step = function() {
            if (i >= text.length) { then(); return; }
            app.chatInputText = text.substring(0, ++i);
            kit.later(every, step);
        };
        step();
    }

    function goTo(chatId, then) {
        app.historyOnlyMode = false;
        if (app.currentSessionId !== chatId)
            app.switchSession(chatId);
        kit.waitFor("chat " + chatId + " to open", function() {
            return app.currentSessionId === chatId && app.messages.length > 0;
        }, 8000, function() { tour.dismissUndo(); kit.later(700, then); });
    }

    function newChat(then) {
        app.historyOnlyMode = false;
        var before = app.currentSessionId;
        app.createSession(true);
        kit.waitFor("a new chat", function() {
            return app.currentSessionId !== before && app.messages.length === 0;
        }, 8000, function() { tour.dismissUndo(); kit.later(900, then); });
    }

    function deleteOpenChat(then) {
        var id = app.currentSessionId;
        app.deleteSession(id);
        kit.waitFor("the scratch chat to go", function() { return app.sessionIndexById(id) < 0; }, 8000,
                    function() { kit.later(500, then); });
    }

    // The commands list is a Popup, which lives in the window's overlay, outside the widget's
    // item tree (and the window's own content item belongs to another QML engine, so it can't be
    // grabbed from here). Each time it opens, its visual item is moved into the widget's tree.
    readonly property var suggestions: body && body.composerItem ? body.composerItem.suggestions : null
    Connections {
        target: tour.suggestions
        function onOpened() {
            var popupItem = tour.suggestions.contentItem.parent;
            if (popupItem && tour.target) {
                popupItem.parent = tour.target;
                popupItem.z = 5000;
            }
        }
    }
    readonly property var grabItem: target
    // The toast with Undo (after deleting the scratch chat or question) is closed before a shot.
    function dismissUndo() {
        var button = kit.find(target, "undoDismiss");
        if (button && button.visible)
            button.clicked();
    }
    property bool keepToast: false
    function shot(name, then) {
        if (!keepToast) dismissUndo();
        kit.later(500, function() { kit.shot(grabItem, name, then); });
    }

    // The widget's item has no background of its own (Plasma paints the popup's), so a grab
    // would be transparent where the chat doesn't paint: this gives it the theme's window colour.
    Rectangle {
        parent: tour.target
        anchors.fill: parent
        z: -1000
        color: Kirigami.Theme.backgroundColor
    }

    // ---- states ------------------------------------------------------------
    function stateConversation(next) {
        goTo(demoChat, function() {
            var list = body.chatView.list;   // the question first, then the start of the answer
            if (list && typeof list.positionViewAtBeginning === "function")
                list.positionViewAtBeginning();
            kit.later(600, function() { shot("chat-conversation", next); });
        });
    }

    function stateEmpty(next) {
        newChat(function() {
            shot("chat-empty", function() { deleteOpenChat(next); });
        });
    }

    function stateHistory(next) {
        goTo(demoChat, function() {
            app.historyOnlyMode = true;
            kit.waitFor("the chat list", function() { return body.sessionList !== null && body.sessionList.visible; }, 8000,
                        function() { kit.later(700, function() { shot("chat-history", next); }); });
        });
    }

    function stateSearch(next) {
        app.historyOnlyMode = true;
        kit.waitFor("the search field", function() { return body.sessionList && body.sessionList.search; }, 8000, function() {
            var panel = body.sessionList.search;
            panel.field.text = "bash";
            kit.waitFor("search results", function() { return panel.resultList.count >= 1; }, 8000, function() {
                kit.later(700, function() {
                    shot("chat-search", function() { panel.field.text = ""; app.historyOnlyMode = false; kit.later(500, next); });
                });
            });
        });
    }

    function stateIncognito(next) {
        app.historyOnlyMode = false;
        app.incognito.start();
        kit.waitFor("an incognito chat", function() { return app.incognito.active; }, 8000, function() {
            app.messages = [
                {"role": "user", "content": "Help me word a polite no to a meeting invite.", "at": Date.now() - 60000},
                {"role": "assistant", "model": "nova-demo", "at": Date.now() - 30000,
                 "content": "Of course. Something like:\n\n> Thanks for the invite. I can't make it this time, but please send me the notes afterwards."}];
            kit.later(900, function() {
                shot("chat-incognito", function() {
                    app.messages = [];
                    app.incognito.close();
                    kit.waitFor("leaving incognito", function() { return !app.incognito.active; }, 8000, function() { kit.later(600, next); });
                });
            });
        });
    }

    function stateCommands(next) {
        goTo(demoChat, function() {
            app.chatInputText = "/";
            kit.waitFor("the commands popup", function() {
                var s = body.composerItem.suggestions;   // a Popup: not among the items
                return s && s.visible && s.height > 20;
            }, 8000, function() { kit.later(500, function() { shot("chat-commands", function() { app.chatInputText = ""; kit.later(400, next); }); }); });
        });
    }

    function stateAsk(next) {
        goTo(demoChat, function() {
            var count = app.messages.length;
            app.applyBackendEvent({"type": "question_request", "id": "ask-demo-1", "questions": [{
                "header": "", "question": "Which edition of Rust do you want the examples in?", "multiple": false, "custom": true,
                "options": [{"label": "2021", "description": ""}, {"label": "2024", "description": ""}]}]},
                "nova-demo", {"harness": "direct", "name": "nova-demo"});
            kit.waitFor("the question card", function() { return app.messages.length > count; }, 8000, function() {
                kit.later(900, function() {
                    shot("chat-ask", function() {
                        app.deleteMessage(app.messages.length - 1);
                        kit.later(500, next);
                    });
                });
            });
        });
    }

    function stateChatSettings(next) {
        goTo(demoChat, function() {
            settingsDialog.openForSession(app.currentSessionId);
            kit.waitFor("the chat settings", function() { return settingsDialog.visible; }, 8000, function() {
                kit.later(900, function() { shot("chat-settings", function() { settingsDialog.close(); kit.later(500, next); }); });
            });
        });
    }

    function stateSchedule(next) {
        goTo(tripChat, function() {
            scheduleOverlay.openForChat(app.currentSessionId);
            kit.waitFor("the schedule editor", function() { return scheduleOverlay.visible; }, 8000, function() {
                kit.later(1200, function() { shot("schedule-editor", function() { scheduleOverlay.visible = false; kit.later(500, next); }); });
            });
        });
    }

    // ---- flows (frame sequences) ------------------------------------------
    function flowSend(next) {
        newChat(function() {
            kit.record("send-message", grabItem, 80, function(done) {
                typeInto("What makes Rust memory safe?", 45, function() {
                    kit.later(300, function() {
                        app.sendMessage();
                        kit.waitFor("the reply", function() {
                            var m = app.messages;
                            return !app.loading && m.length >= 2 && String(m[m.length - 1].content || "").indexOf("go deeper") >= 0;
                        }, 30000, function() { kit.later(1200, done); });
                    });
                });
            }, function() { next(); });
        });
    }

    function flowSearch(next) {
        goTo(demoChat, function() {
            kit.record("search", grabItem, 80, function(done) {
                app.historyOnlyMode = true;
                kit.waitFor("the search field", function() { return body.sessionList && body.sessionList.search; }, 8000, function() {
                    var text = "bash", i = 0, panel = body.sessionList.search;
                    var step = function() {
                        if (i < text.length) { panel.field.text = text.substring(0, ++i); kit.later(250, step); return; }
                        kit.waitFor("search results", function() { return panel.resultList.count >= 1; }, 8000,
                                    function() { kit.later(1500, function() { panel.field.text = ""; app.historyOnlyMode = false; kit.later(400, done); }); });
                    };
                    kit.later(600, step);
                });
            }, function() { next(); });
        });
    }

    function flowIncognito(next) {
        goTo(demoChat, function() {
            kit.record("incognito", grabItem, 80, function(done) {
                app.incognito.start();
                kit.waitFor("an incognito chat", function() { return app.incognito.active && app.messages.length === 0; }, 8000, function() {
                    kit.later(900, function() {
                        typeInto("Help me word a polite no to a meeting invite.", 40, function() {
                            kit.later(300, function() {
                                app.sendMessage();
                                kit.waitFor("the reply", function() {
                                    var m = app.messages;
                                    return !app.loading && m.length >= 2 && String(m[m.length - 1].content || "").indexOf("go deeper") >= 0;
                                }, 30000, function() {
                                    kit.later(1200, function() {
                                        app.messages = [];   // nothing to confirm when leaving
                                        app.incognito.close();
                                        kit.later(700, done);
                                    });
                                });
                            });
                        });
                    });
                });
            }, function() { next(); });
        });
    }

    function flowCommands(next) {
        goTo(demoChat, function() {
            kit.record("commands", grabItem, 80, function(done) {
                var texts = ["/", "/s", "/su", "/sum"];
                var i = 0;
                var step = function() {
                    if (i < texts.length) { app.chatInputText = texts[i++]; kit.later(i === 1 ? 1300 : 500, step); return; }
                    kit.later(1200, function() { app.chatInputText = ""; kit.later(500, done); });
                };
                kit.later(500, step);
            }, function() { next(); });
        });
    }

    // The whole tour, or only the named steps (DEV_MEDIA_ONLY=videoChat,flowSend).
    function steps() {
        var named = {
            "conversation": stateConversation, "empty": stateEmpty, "history": stateHistory, "search": stateSearch,
            "incognito": stateIncognito, "commands": stateCommands, "ask": stateAsk, "chatSettings": stateChatSettings,
            "schedule": stateSchedule, "pages": pages.run, "flowSend": flowSend, "flowSearch": flowSearch,
            "flowIncognito": flowIncognito, "flowCommands": flowCommands, "videoChat": videoChat.run,
            "videoMore": videoMore.run, "pageExtras": pages.runExtras, "extras": extras.run
        };
        if (tour.only !== "")
            return tour.only.split(",").map(function(n) {
                if (!named[n.trim()]) kit.fail("no tour step named " + n);
                return named[n.trim()];
            });
        var all = [stateConversation, stateEmpty, stateHistory, stateSearch, stateIncognito, stateCommands,
                   stateAsk, stateChatSettings, stateSchedule, pages.run];
        if (flows)
            all = all.concat([flowSend, flowSearch, flowIncognito, flowCommands, videoChat.run, videoMore.run]);
        return all.concat([pages.runExtras, extras.run]);
    }

    function run(steps, i) {
        if (i >= steps.length) {
            kit.waitFor("saves to finish", function() { return kit.saving === 0; }, 20000, function() { console.log("MEDIA_DONE"); });
            return;
        }
        steps[i](function() { tour.run(steps, i + 1); });
    }

    function start() {
        var win = target.Window.window;
        if (win) { win.width = width_; win.height = height_; }
        console.log("MEDIA_START theme=" + themeName + " window=" + (win ? win.width + "x" + win.height : "none"));
        kit.waitFor("the widget to size to " + width_ + "x" + height_, function() {
            return Math.abs(target.width - width_) < 2 && Math.abs(target.height - height_) < 2;
        }, 10000, function() {
            kit.waitFor("the demo chats", function() {
                console.log("MEDIA_WAIT sessions=" + app.sessions.length + " current=" + app.currentSessionId + " messages=" + app.messages.length);
                return app.sessions.length >= 6 && app.currentSessionId !== "" && app.messages.length > 0;
            }, 20000, function() {
                // Pixel-exact theme proof: the colour Kirigami gives the chat.
                console.log("MEDIA_THEME " + themeName + " background=" + themeBackground);
                tour.run(tour.steps(), 0);
            });
        });
    }

    Timer { interval: 3000; running: tour.target !== null; onTriggered: tour.start() }
}
