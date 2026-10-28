// Chapter 3, memory: Settings -> Memory (add, pin, edit and delete a memory, all through the real page and
// the helper's memory.json), and memory on or off for one chat in Chat info.
import QtQuick

VideoChapter {
    id: chapter

    function rowOf(page, text) {
        return pages.byPred(page, function(i) { return i.memory !== undefined && i.memory !== null && i.memory.text === text && i.startEdit !== undefined; });
    }

    function memoryPage(next) {
        openPage("ConfigMemory.qml", function(p) { return !pages.shown(p, "memoryEmpty") && kit.find(p, "memorySearch") !== null; }, function(page) {
            var text = "My sister Maya lives in Porto, so trips there are short.";
            var edited = "My sister Maya lives in Porto; I visit her every spring.";
            kit.record("memory-page", scratch, 80, function(done) {
                kit.later(1500, function() {
                    typeInto(byName(page, "memoryAddField"), text, 40, function() {
                        kit.later(400, function() {
                            var add = byName(page, "memoryAddButton");
                            tap(add, scratch, function() {
                                add.clicked();
                                kit.waitFor("the new memory", function() { return chapter.rowOf(page, text) !== null; }, 8000, function() {
                                    kit.later(1500, function() {
                                        var row = chapter.rowOf(page, text);
                                        var pin = kit.find(row, "memoryPinButton");
                                        tap(pin, scratch, function() {
                                            pin.checked = true; pin.toggled();
                                            kit.later(1800, function() {
                                                var edit = kit.find(chapter.rowOf(page, text), "memoryEditButton");
                                                tap(edit, scratch, function() {
                                                    edit.clicked();
                                                    kit.later(500, function() {
                                                        var editor = kit.find(chapter.rowOf(page, text), "memoryEditor");
                                                        typing(function(t) { editor.text = t; }, edited, 35, function() {
                                                            kit.later(400, function() {
                                                                var save = kit.find(chapter.rowOf(page, text), "memorySaveButton");
                                                                tap(save, scratch, function() {
                                                                    save.clicked();
                                                                    kit.waitFor("the edited memory", function() { return chapter.rowOf(page, edited) !== null; }, 8000, function() {
                                                                        kit.later(1800, function() {
                                                                            var del = kit.find(chapter.rowOf(page, edited), "memoryDeleteButton");
                                                                            tap(del, scratch, function() {
                                                                                del.clicked();
                                                                                kit.later(2500, done);
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
                                    });
                                });
                            });
                        });
                    });
                });
            }, function() { closePage(page, next); });
        });
    }

    function chatInfo(next) {
        tour.goTo(tour.demoChat, function() {
            settingsDialog.openForSession(app.currentSessionId);
            kit.waitFor("the memory switch", function() { var s = kit.find(tour.target, "chatMemorySwitch"); return s !== null && s.visible; }, 8000, function() {
                kit.record("memory-chat", grabItem, 80, function(done) {
                    kit.later(1800, function() {
                        var sw = kit.find(tour.target, "chatMemorySwitch");
                        tap(sw, null, function() {
                            sw.checked = false; sw.toggled();
                            kit.later(2500, function() {
                                tap(sw, null, function() {
                                    sw.checked = true; sw.toggled();
                                    kit.later(2000, done);
                                });
                            });
                        });
                    });
                }, function() { settingsDialog.close(); kit.later(500, next); });
            });
        });
    }

    function run(next) { seq([memoryPage, chatInfo], next); }
}
