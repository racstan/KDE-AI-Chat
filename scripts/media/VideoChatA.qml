// Video chapters 1 to 4: chatting, working with messages, quoting, remembering (see VideoChat.qml).
import QtQuick

Item {
    id: part

    property var tour: null
    property var kit: null
    property var app: null
    property var tools: null

    readonly property string question: "Tell me a bedtime story about a lighthouse keeper."

    // 1. Chatting ------------------------------------------------------------
    // Type, send, watch it write, stop it with Esc (which calls stopStreaming, as the key does).
    function stopFlow(next) {
        tools.flow("chat-stop", function(done) {
            kit.later(600, function() {
                tools.ask(part.question, function() {
                    kit.waitFor("the story to start", function() { return tools.streaming(60); }, 20000, function() {
                        kit.later(1500, function() {
                            app.stopStreaming();
                            kit.waitFor("the reply to stop", function() { return !app.loading; }, 8000, function() { kit.later(1800, done); });
                        });
                    });
                }, 45);
            });
        }, next);
    }

    // A second message written while the first answer is still coming waits its turn.
    function queueFlow(next) {
        tools.flow("chat-queue", function(done) {
            kit.later(500, function() {
                tools.ask(part.question, function() {
                    kit.waitFor("the story to start", function() { return tools.streaming(40); }, 20000, function() {
                        kit.later(700, function() {
                            tools.ask("Thanks! Now say it in one line.", function() {
                                kit.later(1800, function() { tools.waitAnswer(function() { kit.later(900, done); }, 1500); });
                            }, 45);
                        });
                    });
                }, 45);
            });
        }, next);
    }

    // A formatted answer: a table, a code block with its copy button, a list.
    function formatFlow(next) {
        tools.flow("chat-formatted", function(done) {
            kit.later(500, function() {
                tools.ask("Compare the three modes in a table, with an example.", function() {
                    tools.waitAnswer(function() {
                        tools.list.positionViewAtIndex(1, ListView.Beginning);
                        kit.later(1200, function() {
                            tools.scroll(1e9, 4, 30, function() { kit.later(1500, done); });
                        });
                    }, 600);
                }, 35);
            });
        }, next);
    }

    // 2. Working with messages ---------------------------------------------------
    // Copy, regenerate (a new answer), edit your own message in place and save it, delete one.
    function messagesFlow(next) {
        tools.flow("chat-messages", function(done) {
            var delegate = function(i) { return tools.delegateAt(i); };
            kit.later(500, function() {
                tools.ask("Give me a tagline for a bakery.", function() {
                    tools.waitAnswer(function() {
                        tools.press(1, "Copy", function() {
                            // Regenerate: the same function the button's menu entry calls.
                            tools.list.select(1);
                            kit.later(900, function() {
                                var before = String(app.messages[1].content);
                                tools.walk(delegate(1), function(it) { return it.objectName === "messageActions"; }).regenerate("");
                                kit.waitFor("the new answer", function() { return tools.answered() && String(app.messages[1].content) !== before; }, 30000, function() {
                                    kit.later(1500, function() {
                                        tools.press(0, "Edit", function() {
                                            var editor = null;
                                            kit.waitFor("the editor", function() { return tools.walk(delegate(0), function(it) { return it.objectName === "inPlaceEditor"; }) !== null; }, 8000, function() {
                                                editor = tools.walk(delegate(0), function(it) { return it.objectName === "inPlaceEditor"; });
                                                var words = " that sells sourdough";
                                                var base = editor.text.replace(/\.$/, "");
                                                var i = 0;
                                                var step = function() {
                                                    if (i < words.length) { editor.text = base + words.substring(0, ++i); kit.later(60, step); return; }
                                                    editor.text = base + words + ".";
                                                    kit.later(900, function() {
                                                        tools.press(0, "Save edit", function() {
                                                            tools.waitAnswer(function() {
                                                                kit.later(1200, function() {
                                                                    tools.press(app.messages.length - 1, "Delete", function() { kit.later(1800, done); }, 600);
                                                                });
                                                            }, 900);
                                                        }, 300);
                                                    });
                                                };
                                                step();
                                            });
                                        }, 700);
                                    });
                                });
                            });
                        }, 1500);
                    }, 700);
                }, 40);
            });
        }, next);
    }

    // 3. Quoting -----------------------------------------------------------------
    // Quote a reply, send with it, then click the quote to jump back to the original.
    function quoteFlow(next) {
        tools.flow("chat-quote-jump", function(done) {
            kit.later(500, function() {
                tools.ask("Can you explain Rust lifetimes in simple terms?", function() {
                    tools.waitAnswer(function() {
                        tools.press(1, "Quote", function() {
                            kit.later(1200, function() {
                                tools.ask("Can you show an example of that?", function() {
                                    tools.waitAnswer(function() {
                                        kit.later(900, function() {
                                            var area = tools.walk(tools.delegateAt(2), function(it) { return it.objectName === "quoteArea"; });
                                            if (!area) { kit.fail("the quote in the sent message was not found"); return; }
                                            tools.list.positionViewAtEnd();
                                            kit.later(600, function() {
                                                area.clicked(null);
                                                kit.later(2200, done);
                                            });
                                        });
                                    }, 700);
                                }, 40);
                            });
                        }, 400);
                    }, 700);
                }, 40);
            });
        }, next);
    }

    // 4. Remembering -------------------------------------------------------------
    // The Remember action under a reply (save as a memory), then /remember typed in the box.
    function rememberFlow(next) {
        tools.flow("chat-remember-flow", function(done) {
            kit.later(500, function() {
                tools.ask("Give me a tagline for a bakery.", function() {
                    tools.waitAnswer(function() {
                        tools.press(1, "Remember", function() {
                            kit.waitFor("the Remember popup", function() { return tools.inOverlay("rememberText") !== null; }, 8000, function() {
                                var field = tools.inOverlay("rememberText");
                                var popup = {"contentItem": null};
                                tools.pullOverlay(field);
                                var save = tools.inOverlay("rememberSave") || tools.walk(tools.grabItem, function(it) { return it.objectName === "rememberSave"; });
                                kit.later(1200, function() {
                                    var text = "I like short taglines.", i = 0;
                                    field.text = "";
                                    var step = function() {
                                        if (i < text.length) { field.text = text.substring(0, ++i); kit.later(55, step); return; }
                                        kit.later(800, function() {
                                            save.clicked();
                                            kit.later(2200, function() {
                                                tools.type("/remember I prefer metric units", 50, function() {
                                                    kit.later(700, function() {
                                                        tools.runCommand("/remember I prefer metric units");
                                                        kit.later(2600, done);
                                                    });
                                                });
                                            });
                                        });
                                    };
                                    step();
                                });
                            });
                        }, 400);
                    }, 700);
                }, 40);
            });
        }, next);
    }

    function run(next) {
        tools.chain([stopFlow, queueFlow, formatFlow, messagesFlow, quoteFlow, rememberFlow], next);
    }
}
