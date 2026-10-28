// Chapter 5, schedules: "Schedule a message…" from the chat's More menu opens the editor over the chat; the
// name and message are typed, "Describe when" is filled in by the AI (the demo server turns the sentence
// into rules, as a real model does) and the schedule is saved, for two minutes from now. At that time
// dev-media.sh runs the real scheduler job (kde_ai_helper.py run_schedule) as systemd would, the
// job sends the message to the demo server in the chat's own mode and the answer arrives in the open chat
// (chat/ScheduleInbox.qml). Then Settings -> Schedules shows it with its next run and its history.
import QtQuick

VideoChapter {
    id: chapter

    readonly property string name: "Lisbon briefing"
    // The time the schedule runs (two minutes ahead: typing takes a while, and a run is only due for a
    // time after the schedule was saved).
    property date dueAt: new Date()

    function two(n) { return (n < 10 ? "0" : "") + n; }

    function create(next) {
        tour.goTo(tour.tripChat, function() {
            kit.record("schedule-create", grabItem, 80, function(done) {
                var more = kit.find(tour.target, "moreButton");
                kit.later(1200, function() {
                    tap(more, null, function() {
                        scheduleOverlay.openForChat(app.currentSessionId);
                        kit.waitFor("the schedule editor", function() { return scheduleOverlay.visible; }, 8000, function() {
                            chapter.fill(done);
                        });
                    });
                });
            }, next);
        });
    }

    function fill(done) {
        var editor = scheduleOverlay.dialog.editor;
        var field = kit.find(scheduleOverlay, "scheduleName");
        kit.later(1200, function() {
            typing(function(t) { field.text = t; editor.setField("name", t); }, chapter.name, 70, function() {
                var message = kit.find(scheduleOverlay, "scheduleMessage");
                kit.later(500, function() {
                    typing(function(t) { message.text = t; }, "Give me a short briefing for today.", 40, function() {
                        var due = new Date(Date.now() + 120000);
                        due.setSeconds(0, 0);
                        chapter.dueAt = due;
                        var when = "every day at " + chapter.two(due.getHours()) + ":" + chapter.two(due.getMinutes());
                        var describe = kit.find(scheduleOverlay, "describeField");
                        kit.later(600, function() {
                            typing(function(t) { describe.text = t; }, when, 60, function() {
                                var fillIn = kit.find(scheduleOverlay, "describeButton");
                                tap(fillIn, null, function() {
                                    fillIn.clicked();
                                    kit.waitFor("the rules", function() { var f = kit.find(scheduleOverlay, "describeFilled"); return f !== null && f.visible; }, 20000, function() {
                                        kit.later(3500, function() {
                                            var save = kit.find(scheduleOverlay, "saveSchedule");
                                            tap(save, null, function() {
                                                save.clicked();
                                                kit.waitFor("the schedule to be saved", function() { return !scheduleOverlay.visible; }, 15000, function() {
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
        });
    }

    // The scheduler's answer arrives in the open chat by itself.
    function arrive(next) {
        var before = app.messages.length;
        // Nothing worth seeing until shortly before the time: the recording starts 3 s ahead of it.
        kit.later(Math.max(0, chapter.dueAt.getTime() - Date.now() - 3000), function() {
            chapter.record(before, next);
        });
    }

    function record(before, next) {
        kit.record("schedule-run", grabItem, 80, function(done) {
            kit.waitFor("the scheduled answer", function() {
                var m = app.messages;
                return m.length > before && m[m.length - 1].role === "assistant" && String(m[m.length - 1].scheduleRunId || "") !== "";
            }, 90000, function() { kit.later(4000, done); });
        }, next);
    }

    function list(next) {
        openPage("ConfigSchedules.qml", function(p) { return pages.byPred(p, function(i) { return i.objectName === "scheduleRow" && i.item && i.item.name === chapter.name; }) !== null; }, function(page) {
            kit.record("schedule-list", scratch, 80, function(done) {
                kit.later(2500, function() {
                    var row = pages.byPred(page, function(i) { return i.objectName === "scheduleRow" && i.item && i.item.name === chapter.name; });
                    var history = kit.find(row, "scheduleHistory");
                    tap(history, scratch, function() {
                        history.clicked();
                        kit.later(4500, done);
                    });
                });
            }, function() { closePage(page, next); });
        });
    }

    function run(next) { seq([create, arrive, list], next); }
}
