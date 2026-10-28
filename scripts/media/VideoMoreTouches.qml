// Chapter 7, small touches: the More menu opens the moment the pointer rests on it (a jump to the first
// message from there), and a chat deleted in the history comes back with Undo. Everything through the
// widget's own buttons.
import QtQuick

VideoChapter {
    id: chapter

    function moreMenu(next) {
        tour.goTo(tour.demoChat, function() {
            var button = kit.find(tour.target, "moreButton");
            kit.record("touch-more-menu", grabItem, 80, function(done) {
                kit.later(1200, function() {
                    tap(button, null, function() {
                        button.clicked();
                        kit.waitFor("the menu", function() { return button.menu.opened; }, 5000, function() {
                            pull(button.menu);
                            kit.later(2500, function() {
                                var first = pages.byPred(button.menu.contentItem, function(i) { return i.text === "Jump to first message"; });
                                tap(first, null, function() {
                                    first.triggered();
                                    button.menu.close();
                                    kit.later(3000, done);
                                });
                            });
                        });
                    });
                });
            }, next);
        });
    }

    // A row's button in the history (archive / delete) for the chat titled `title`.
    function rowButton(title, name) {
        var row = pages.byPred(body.sessionList, function(i) { return i.modelData !== undefined && i.modelData && i.modelData.text === title && kit.find(i, name) !== null; });
        return row ? kit.find(row, name) : null;
    }

    function history(next) {
        var title = "Reply to Sam about the invoice";
        app.historyOnlyMode = true;
        kit.waitFor("the history", function() { return body.sessionList && chapter.rowButton(title, "deleteButton") !== null; }, 8000, function() {
            kit.record("touch-undo", grabItem, 80, function(done) {
                kit.later(1500, function() {
                    var del = chapter.rowButton(title, "deleteButton");
                    if (!del) { kit.fail("no delete button for " + title); return; }
                    tap(del, null, function() {
                        del.clicked();
                        kit.waitFor("Undo", function() { var u = kit.find(tour.target, "undoButton"); return u !== null && u.visible; }, 8000, function() {
                            kit.later(1800, function() {
                                var undo = kit.find(tour.target, "undoButton");
                                tap(undo, null, function() {
                                    undo.clicked();
                                    kit.later(2500, done);
                                });
                            });
                        });
                    });
                });
            }, function() { app.historyOnlyMode = false; next(); });
        });
    }

    function run(next) { seq([moreMenu, history], next); }
}
