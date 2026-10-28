// Chapter 4, the three modes: Settings -> Connection switches Direct -> OpenCode -> Pi (the real radio
// buttons and sections); the open chat is Direct and stays Direct (the blue banner and its New chat button);
// the new chat is an OpenCode chat (a permission prompt, answered), then Pi is chosen and a Pi chat shows
// the activity box (thinking and steps, opened). Chat info names each chat's mode. The agents are the
// demo OpenCode server (scripts/media/demo_opencode.py: real files of this repository, several agents) and
// a fake `pi` replaying a recorded real Pi run (tests/fixtures), so its prompt is the recorded one.
import QtQuick
import QtQuick.Controls as QQC2

VideoChapter {
    id: chapter

    property var made: []        // chats this chapter created (deleted at the end)

    function radio(page, text) { return byText(page, text); }
    function choose(page, text, then) {
        var r = radio(page, text);
        tap(r, scratch, function() { r.checked = true; r.toggled(); then(); });   // as a click: toggled() tells the page
    }

    // The Connection page in the overlay; leaving it applies what was chosen (what OK does in Plasma).
    function connection(then) { openPage("ConfigConnection.qml", null, then); }
    function leave(page, next) { return function() { apply(page); closePage(page, next); }; }

    function switchModes(next) {
        connection(function(page) {
            kit.record("modes-settings", scratch, 80, function(done) {
                kit.later(2500, function() {
                    chapter.choose(page, "Through OpenCode", function() {
                        kit.later(3500, function() {
                            chapter.choose(page, "Through Pi", function() {
                                kit.later(3500, function() {
                                    chapter.choose(page, "Directly to a provider", function() {
                                        kit.later(2500, function() {
                                            chapter.choose(page, "Through OpenCode", function() { kit.later(2500, done); });
                                        });
                                    });
                                });
                            });
                        });
                    });
                });
            }, chapter.leave(page, next));
        });
    }

    function banner() {
        var b = kit.find(tour.target, "modeMismatchBanner");
        return b !== null && b.visible && b.text !== "" ? b : null;
    }

    // Taps the banner's New chat button; the new chat is empty and open when then() runs.
    function newChatFromBanner(then) {
        var before = app.currentSessionId;
        var b = chapter.banner();
        var button = pages.byPred(b, function(i) { return i.text === "New chat" && i.clicked !== undefined; });
        tap(button, null, function() {
            button.clicked();
            kit.waitFor("the new chat", function() { return app.currentSessionId !== before && app.messages.length === 0; }, 8000, function() {
                chapter.made.push(app.currentSessionId);
                kit.later(1500, then);
            });
        });
    }

    // Agent chats end with a permission or activity row, so "done" is: nothing loading and an answer in the list.
    function waitDone(extra, then) {
        kit.waitFor("the agent to finish", function() {
            if (app.loading) return false;
            for (var i = 0; i < app.messages.length; i++)
                if (app.messages[i].role === "assistant" && String(app.messages[i].content || "") !== "") return true;
            return false;
        }, 60000, function() { kit.later(extra, then); });
    }

    function showInfo(then) {
        settingsDialog.openForSession(app.currentSessionId);
        kit.waitFor("the chat info", function() { var l = kit.find(tour.target, "effectiveLine"); return l !== null && l.visible; }, 8000, function() {
            kit.later(3200, function() { settingsDialog.close(); kit.later(600, then); });
        });
    }

    function agentChat(first, text, then) {
        // The chat in the new mode: its first message, any permission, the reply, and the chat info.
        typing(function(t) { app.chatInputText = t; }, text, 45, function() {
            kit.later(500, function() { app.sendMessage(); then(); });
        });
    }

    // Replies so far (agent chats also hold activity rows): done when `n` have text and nothing loads.
    function waitAnswers(n, extra, then) {
        kit.waitFor(n + " answers", function() {
            if (app.loading) return false;
            var count = 0;
            for (var i = 0; i < app.messages.length; i++)
                if (app.messages[i].role === "assistant" && String(app.messages[i].content || "") !== "") count++;
            return count >= n;
        }, 60000, function() { kit.later(extra, then); });
    }

    // Chat info -> Change... -> the agent `name` (OpenCode's own agents, read from the server).
    function pickAgent(name, then) {
        settingsDialog.openForSession(app.currentSessionId);
        kit.waitFor("the chat info", function() { var b = kit.find(tour.target, "changeModelButton"); return b !== null && b.visible; }, 8000, function() {
            kit.later(1500, function() {
                var change = kit.find(tour.target, "changeModelButton");
                tap(change, null, function() {
                    change.clicked();
                    // The picker is a popup in the window's overlay: its visual item is moved into the frames.
                    var overlay = QQC2.Overlay.overlay;
                    var choices = function() { return pages.byPred(overlay, function(i) { return i.objectName === "agentChoices" && i.visible; }); };
                    kit.waitFor("the agents", function() { return choices() !== null; }, 8000, function() {
                        var top = choices();
                        while (top.parent && top.parent !== overlay) top = top.parent;
                        top.parent = tour.target; top.z = 6000;
                        kit.later(2200, function() {
                            var pick = pages.byPred(top, function(i) { return i.objectName === "agentChoice" && i.text === name; });
                            if (!pick) { kit.fail("no agent " + name + " in the picker"); return; }
                            tap(pick, null, function() {
                                pick.clicked();
                                kit.later(1500, function() { settingsDialog.close(); kit.later(700, then); });   // picking closes the picker
                            });
                        });
                    });
                });
            });
        });
    }

    function openCodeChat(next) {
        var cfg = plasmoidRef.configuration;
        tour.goTo(tour.demoChat, function() {
            app.chatInputText = "";
            kit.waitFor("the mode banner", function() { return chapter.banner() !== null; }, 8000, function() {
                kit.record("mode-banner", grabItem, 80, function(done) {
                    kit.later(4500, function() { chapter.newChatFromBanner(function() { kit.later(1500, done); }); });
                }, function() {
                    cfg.perChatModelSettings = true;   // each chat its own agent (Settings -> Chat)
                    kit.record("mode-opencode", grabItem, 80, function(done) {
                        chapter.agentChat(true, "What does scripts/check_file_sizes.py check?", function() {
                            chapter.waitAnswers(1, 3500, function() {
                                chapter.pickAgent("plan", function() {
                                    chapter.agentChat(false, "Plan a setting for dark code blocks.", function() {
                                        chapter.waitAnswers(2, 3500, function() {
                                            chapter.pickAgent("build", function() {
                                                chapter.agentChat(false, "Create build/hello.txt with a short greeting.", function() {
                                                    kit.waitFor("the permission prompt", function() {
                                                        var a = kit.find(tour.target, "allowButton");
                                                        return a !== null && a.visible;
                                                    }, 40000, function() {
                                                        kit.later(3000, function() {
                                                            var allow = kit.find(tour.target, "allowButton");
                                                            tap(allow, null, function() {
                                                                allow.clicked();
                                                                chapter.waitAnswers(3, 3000, function() { chapter.showInfo(done); });
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
                    }, function() { cfg.perChatModelSettings = false; next(); });
                });
            });
        });
    }

    function piChat(next) {
        connection(function(page) { kit.record("mode-pi-settings", scratch, 80, function(done) {
            kit.later(2000, function() { chapter.choose(page, "Through Pi", function() { kit.later(3500, done); }); });
        }, chapter.leave(page, function() {
            kit.waitFor("the mode banner", function() { return chapter.banner() !== null; }, 8000, function() {
                kit.record("mode-pi", grabItem, 80, function(done) {
                    kit.later(3000, function() {
                        chapter.newChatFromBanner(function() {
                            chapter.agentChat(false, "Use the write tool to create hello.txt containing hi. Then say done.", function() {
                                chapter.waitDone(2500, function() {
                                    var box = kit.find(tour.target, "activitySummary");
                                    if (box === null || !box.visible) { kit.fail("no activity box in the Pi chat"); return; }
                                    tap(box, null, function() {
                                        box.clicked();
                                        kit.later(5000, function() { chapter.showInfo(done); });
                                    });
                                });
                            });
                        });
                    });
                }, next);
            });
        })); });
    }

    function cleanup(next) {
        // Back to Direct, as the chats of the later chapters are (no mode banner over them).
        config.useOpenCode = false;
        config.usePi = false;
        var go = function() {
            if (chapter.made.length === 0) { tour.goTo(tour.demoChat, next); return; }
            var id = chapter.made.pop();
            if (app.sessionIndexById(id) < 0) { go(); return; }
            app.switchSession(id);
            kit.waitFor("the chat to open", function() { return app.currentSessionId === id; }, 8000, function() { tour.deleteOpenChat(go); });
        };
        go();
    }

    function run(next) { seq([switchModes, openCodeChat, piChat, cleanup], next); }
}
