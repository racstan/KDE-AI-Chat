// Chapter 1, getting started: the first-run setup in an empty chat. The configuration is changed the way
// a brand-new install looks (no provider), the card finds the fake local server, one tap picks it, and the
// first message is typed and answered. VideoMore.qml puts the configuration back afterwards.
import QtQuick

VideoChapter {
    id: chapter

    function visibleItem(name) {
        var item = kit.find(tour.target, name);
        return item !== null && item.visible ? item : null;
    }

    function run(next) {
        var saved = [config.providersJson, config.provider, config.firstRunDismissed];
        tour.newChat(function() {
            config.firstRunDismissed = false;
            config.providersJson = "[]";
            config.provider = "";
            kit.waitFor("the welcome card", function() { return chapter.visibleItem("firstRunCard") !== null; }, 8000, function() {
                kit.waitFor("the local server to be found", function() { return chapter.visibleItem("firstRunServer") !== null; }, 20000, function() {
                    kit.record("first-run", grabItem, 80, function(done) {
                        kit.later(3000, function() {
                            var row = chapter.visibleItem("firstRunServer");
                            tap(row, null, function() {
                                row.clicked();
                                kit.waitFor("the ready step", function() { return chapter.visibleItem("firstRunFinish") !== null; }, 8000, function() {
                                    kit.later(2800, function() {
                                        var finish = chapter.visibleItem("firstRunFinish");
                                        tap(finish, null, function() {
                                            finish.clicked();
                                            kit.later(1200, function() {
                                                typing(function(t) { app.chatInputText = t; }, "Hi! What can you help me with?", 45, function() {
                                                    kit.later(500, function() {
                                                        app.sendMessage();
                                                        waitReply(3000, done);
                                                    });
                                                });
                                            });
                                        });
                                    });
                                });
                            });
                        });
                    }, function() {
                        config.providersJson = saved[0];
                        config.provider = saved[1];
                        config.firstRunDismissed = saved[2];
                        tour.deleteOpenChat(function() { tour.goTo(tour.demoChat, next); });
                    });
                });
            });
        });
    }
}
