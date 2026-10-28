// Video chapters 5 and 6: organising chats (pin, rename, history, projects, search) and the keyboard
// (see VideoChat.qml). Keys are shown by calling what the key calls: the shortcuts (chat/ChatShortcuts.qml)
// and the list's key handler (chat/ChatView.qml) call exactly these functions.
import QtQuick

Item {
    id: part

    property var tour: null
    property var kit: null
    property var app: null
    property var tools: null
    property var pages: null
    property string projectId: ""

    readonly property string shortChat: "s-1000000000003-0003"   // Count duplicate lines: two short messages
    readonly property string mealChat: "s-1000000000004-0004"

    function typeText(setter, text, every, then) {
        var i = 0;
        var step = function() {
            if (i < text.length) { setter(text.substring(0, ++i)); kit.later(every, step); return; }
            then();
        };
        step();
    }

    // 5. Organising ------------------------------------------------------------
    // The pin button keeps the widget open when you click away.
    function pinFlow(next) {
        tools.flowIn(tour.demoChat, "chat-pin", function(done) {
            var pin = kit.find(tools.grabItem, "pinButton");
            kit.later(1200, function() {
                pin.toggle();
                kit.later(1800, function() { pin.toggle(); kit.later(1800, done); });
            });
        }, next);
    }

    // The history list; rename a chat from its row.
    function renameFlow(next) {
        tools.flowIn(tour.demoChat, "chat-rename", function(done) {
            app.historyOnlyMode = true;
            kit.waitFor("the history", function() { return tools.body.sessionList !== null && tools.body.sessionList.visible; }, 8000, function() {
                kit.later(1800, function() {
                    app.startSessionRename(part.mealChat);
                    kit.later(1000, function() {
                        part.typeText(function(t) { app.editingSessionDraft = t; }, "Weekly meals", 90, function() {
                            kit.later(700, function() {
                                var save = tools.walk(tools.body.sessionList, function(it) { return it.objectName === "renameButton" && it.visible; });
                                if (save) save.clicked(); else app.saveSessionRename(part.mealChat);
                                kit.later(2200, done);
                            });
                        });
                    });
                });
            });
        }, next);
    }

    // A project: name, instructions, a chat moved into it, and what it shows in the chat.
    function projectFlow(next) {
        var projects = app.projects;
        tools.flowIn(tour.demoChat, "chat-projects", function(done) {
            app.historyOnlyMode = true;
            kit.later(1500, function() {
                projects.openEditor("", part.mealChat);   // "Move to project > New project" does this
                var editor = tools.body.projectEditor;
                kit.waitFor("the project editor", function() { return editor.opened; }, 8000, function() {
                    tools.pull(editor);
                    var name = tools.walk(editor.contentItem, function(it) { return it.objectName === "projectName"; });
                    var instructions = tools.walk(editor.contentItem, function(it) { return it.objectName === "projectInstructions"; });
                    kit.later(1000, function() {
                        part.typeText(function(t) { name.text = t; }, "Cooking", 100, function() {
                            kit.later(500, function() {
                                part.typeText(function(t) { instructions.text = t; }, "Cheap, quick recipes. No more than 30 minutes.", 45, function() {
                                    kit.later(1200, function() {
                                        tools.walk(editor.contentItem, function(it) { return it.objectName === "saveProject"; }).clicked();
                                        kit.later(1800, function() {
                                            var id = projects.list[projects.list.length - 1].id;
                                            projects.view = id;   // the sidebar's project entry
                                            kit.later(2000, function() {
                                                projects.view = "all";
                                                app.switchSession(part.mealChat);
                                                app.historyOnlyMode = false;
                                                kit.later(2500, function() { part.projectId = id; done(); });
                                            });
                                        });
                                    });
                                });
                            });
                        });
                    });
                });
            });
        }, function() { projects.remove(part.projectId); tour.dismissUndo(); tour.goTo(tour.demoChat, next); });
    }

    // Search across all chats and click a result.
    function searchFlow(next) {
        tools.flowIn(tour.demoChat, "chat-search-jump", function(done) {
            app.historyOnlyMode = true;
            kit.waitFor("the search field", function() { return tools.body.sessionList && tools.body.sessionList.search; }, 8000, function() {
                var panel = tools.body.sessionList.search;
                kit.later(1000, function() {
                    part.typeText(function(t) { panel.field.text = t; }, "bash", 250, function() {
                        kit.waitFor("results", function() { return panel.resultList.count >= 1; }, 8000, function() {
                            kit.later(1500, function() {
                                panel.resultList.currentIndex = 0;
                                kit.later(900, function() {
                                    panel.open(panel.found.results[0]);
                                    kit.waitFor("the message", function() { return tools.list.selectedIndex >= 0; }, 8000, function() { kit.later(2500, done); });
                                });
                            });
                        });
                    });
                });
            });
        }, next);
    }

    // 6. Keyboard ---------------------------------------------------------------
    function keysNew(next) {
        tools.flowIn(tour.demoChat, "keys-new", function(done) {
            kit.later(1500, function() {
                app.createSession(true);   // Ctrl+N
                kit.later(2500, done);
            });
        }, next);
    }

    function keysIncognito(next) {
        tools.flowIn(tour.demoChat, "keys-incognito", function(done) {
            kit.later(1500, function() {
                app.incognito.start();   // Ctrl+Shift+N
                kit.later(2800, done);
            });
        }, next);
    }

    // Up and Down pick a message, Esc lets go.
    function keysPick(next) {
        tools.flowIn(part.shortChat, "keys-pick", function(done) {
            var list = tools.list;
            kit.later(1200, function() {
                list.browse(-1);
                kit.later(1500, function() {
                    list.browse(-1);
                    kit.later(1500, function() {
                        list.browse(1);
                        kit.later(1500, function() { list.leave(); kit.later(1200, done); });   // Esc
                    });
                });
            });
        }, next);
    }

    function keysEdit(next) {
        tools.flowIn(part.shortChat, "keys-edit", function(done) {
            kit.later(1200, function() {
                tools.composer.editLastMessage();   // Ctrl+E
                kit.later(2500, function() {
                    app.editingMessageIndex = -1;   // Esc cancels
                    app.editingDraft = "";
                    kit.later(1200, done);
                });
            });
        }, next);
    }

    function keysQuote(next) {
        tools.flowIn(part.shortChat, "keys-quote", function(done) {
            var list = tools.list;
            kit.later(1000, function() {
                list.select(1);
                kit.later(1500, function() {
                    list.quoteSelected();   // Ctrl+Q
                    kit.later(2500, function() { tools.composer.quoteChips.quotes = []; kit.later(600, done); });
                });
            });
        }, next);
    }

    function keysPage(next) {
        tools.flowIn(tour.demoChat, "keys-page", function(done) {
            var list = tools.list;
            kit.later(1000, function() {
                list.jumpLatest();   // PageDown
                app.focusInput();
                kit.later(1500, function() {
                    list.jumpFirst();   // PageUp
                    kit.later(1800, function() {
                        list.jumpLatest();
                        app.focusInput();
                        kit.later(1500, done);
                    });
                });
            });
        }, next);
    }

    // The shortcut list the widget shows: Settings > Appearance, scrolled to "Keyboard shortcuts".
    function keysList(next) {
        var scratch = pages.scratch;
        var component = Qt.createComponent(Qt.resolvedUrl("../ConfigAppearance.qml"));
        if (component.status !== Component.Ready) { kit.fail("ConfigAppearance.qml could not load: " + component.errorString()); return; }
        scratch.visible = true;
        scratch.z = 5000;
        var page = component.createObject(scratch, {"width": scratch.width, "height": scratch.height});
        pages.fill(page);
        kit.later(1200, function() {
            var row = kit.find(page, "shortcutRow");
            kit.record("keys-list", scratch, 80, function(done) {
                pages.scrollTo(page, row.parent);
                var flick = page.flickable;
                kit.later(1500, function() {
                    tools.scrollItem(flick, flick.contentY + 330, 3, 30, function() { kit.later(1500, done); });
                });
            }, function() { page.destroy(); scratch.visible = false; kit.later(2500, next); });
        });
    }

    function run(next) {
        tools.chain([pinFlow, renameFlow, projectFlow, searchFlow, keysNew, keysIncognito, keysPick, keysEdit, keysQuote, keysPage, keysList], next);
    }
}
