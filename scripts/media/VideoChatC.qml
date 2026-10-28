// Video chapters 7 to 10: commands, attachments, incognito, and the AI asking you (see VideoChat.qml).
import QtQuick

Item {
    id: part

    property var tour: null
    property var kit: null
    property var app: null
    property var tools: null
    property var plasmoidRef: null

    readonly property var composer: tools.composer
    // The repository (the frames folder is <repo>/build/media-frames): the attachments are real files in it.
    readonly property string repo: String(kit.framesDir).replace(/\/build\/media-frames$/, "")

    function popupShown() { var s = composer.suggestions; return s && s.visible && s.height > 20; }

    function typeSteps(texts, every, then) {
        var i = 0;
        var step = function() {
            if (i < texts.length) { app.chatInputText = texts[i++]; kit.later(every, step); return; }
            then();
        };
        step();
    }

    // 7. Commands ----------------------------------------------------------------
    function listFlow(next) {
        tools.flow("chat-commands-list", function(done) {
            kit.later(800, function() {
                app.chatInputText = "/";
                kit.waitFor("the commands", part.popupShown, 8000, function() {
                    kit.later(2200, function() {
                        part.typeSteps(["/s", "/su", "/sum"], 700, function() {
                            kit.later(1800, function() { app.chatInputText = ""; kit.later(500, done); });
                        });
                    });
                });
            });
        }, next);
    }

    // A saved prompt (/summarize) chosen from the list, then used on a text.
    function templateFlow(next) {
        tools.flow("chat-template", function(done) {
            kit.later(800, function() {
                part.typeSteps(["/", "/s", "/su", "/sum"], 450, function() {
                    kit.waitFor("the commands", part.popupShown, 8000, function() {
                        kit.later(1500, function() {
                            composer.suggestions.handleKey(Qt.Key_Tab);   // Tab picks the entry
                            kit.later(1500, function() {
                                var base = app.chatInputText;
                                var extra = "Rust gives every value one owner, lets you borrow it, and checks lifetimes at compile time.";
                                var i = 0;
                                var step = function() {
                                    if (i < extra.length) { app.chatInputText = base + extra.substring(0, ++i); kit.later(30, step); return; }
                                    kit.later(700, function() {
                                        app.sendMessage();
                                        tools.waitAnswer(function() { kit.later(1800, done); }, 600);
                                    });
                                };
                                step();
                            });
                        });
                    });
                });
            });
        }, next);
    }

    // /model changes this chat's model (per-chat models on, as in Settings > Chat).
    function modelFlow(next) {
        var cfg = plasmoidRef.configuration;
        cfg.perChatModelSettings = true;
        tools.flow("chat-model-cmd", function(done) {
            kit.later(800, function() {
                part.typeSteps(["/", "/m", "/mo", "/mod", "/mode", "/model", "/model "], 350, function() {
                    kit.waitFor("the model list", part.popupShown, 8000, function() {
                        kit.later(2500, function() { app.chatInputText = ""; kit.later(800, done); });
                    });
                });
            });
        }, function() { cfg.perChatModelSettings = false; next(); });
    }

    // /image makes a picture. The image service's address is pointed at the fake server (no network).
    function imageFlow(next) {
        var cfg = plasmoidRef.configuration;
        var saved = cfg.providersJson;
        var origin = String(JSON.parse(saved)[0].baseUrl).replace(/\/v1\/?$/, "");
        var jobs = app.imageStore.jobs;
        var list = JSON.parse(saved);
        list.push({"id": "pollinations_free", "name": "Pollinations.ai (older free service)", "type": "image",
                   "service": "pollinations-legacy", "baseUrl": "https://image.pollinations.ai", "model": "sana", "accepted": true});
        cfg.providersJson = JSON.stringify(list);
        jobs.xhrFactory = function() {
            var real = new XMLHttpRequest();
            var proxy = {};
            proxy.open = function(method, url, async) {
                if (!/^https:\/\/image\.pollinations\.ai\/prompt\//.test(String(url)))
                    throw new Error("media tour: refusing a real network address");
                real.open(method, origin + "/img/generated-lighthouse.jpg", async);
            };
            ["setRequestHeader", "send", "abort", "getResponseHeader"].forEach(function(n) {
                proxy[n] = function() { return real[n].apply(real, arguments); };
            });
            ["onreadystatechange", "onerror", "ontimeout", "responseType", "timeout"].forEach(function(n) {
                Object.defineProperty(proxy, n, {"set": function(v) { real[n] = v; }, "get": function() { return real[n]; }});
            });
            ["readyState", "status", "response", "responseText"].forEach(function(n) {
                Object.defineProperty(proxy, n, {"get": function() { return real[n]; }});
            });
            return proxy;
        };
        tools.flow("chat-image-cmd", function(done) {
            kit.later(800, function() {
                var text = "/image a lighthouse at dusk, watercolor";
                tools.type(text, 45, function() {
                    kit.later(800, function() {
                        tools.runCommand(text);
                        kit.waitFor("the picture", function() {
                            var l = tools.last();
                            return !app.loading && l.role === "assistant" && (l.images || []).length > 0;
                        }, 60000, function() { kit.later(3000, done); });
                    });
                });
            });
        }, function() { jobs.xhrFactory = null; cfg.providersJson = saved; next(); });
    }

    // 8. Attachments -----------------------------------------------------------------
    function attachFlow(next) {
        tools.flow("chat-attach", function(done) {
            kit.later(1000, function() {
                app.attachFile("file://" + part.repo + "/docs/voice.md");
                kit.waitFor("the document", function() { return app.attachedFiles.length === 1 && !app.attachedFiles[0].loading; }, 15000, function() {
                    kit.later(1500, function() {
                        app.attachFile("file://" + part.repo + "/scripts/media/lisbon-tram.jpg");
                        kit.waitFor("the picture", function() { return app.attachedFiles.length === 2 && !app.attachedFiles[1].loading; }, 15000, function() {
                            kit.later(1500, function() {
                                tools.ask("Here is the voice guide and a photo from my trip. How do I turn on read aloud, and what is in the photo?", function() {
                                    tools.waitAnswer(function() { kit.later(2000, done); }, 600);
                                }, 35);
                            });
                        });
                    });
                });
            });
        }, next);
    }

    // 9. Incognito ---------------------------------------------------------------------
    function incognitoFlow(next) {
        tools.flowIn(tour.demoChat, "chat-incognito-flow", function(done) {
            kit.later(800, function() {
                app.incognito.start();
                kit.waitFor("an incognito chat", function() { return app.incognito.active && app.messages.length === 0; }, 8000, function() {
                    kit.later(1500, function() {
                        tools.ask("Help me word a polite no to a meeting invite.", function() {
                            tools.waitAnswer(function() {
                                kit.later(1500, function() {
                                    var close = kit.find(tools.grabItem, "incognitoCloseButton");
                                    close.clicked();
                                    kit.waitFor("the leave question", function() { return tools.inOverlay("incognitoLeaveText") !== null; }, 8000, function() {
                                        tools.pullOverlay(tools.inOverlay("incognitoLeaveText"));
                                        kit.later(2200, function() {
                                            kit.find(tools.grabItem, "incognitoLeaveButton").clicked();
                                            kit.later(2500, done);
                                        });
                                    });
                                });
                            }, 600);
                        }, 40);
                    });
                });
            });
        }, next);
    }

    // 10. The AI asks you ----------------------------------------------------------------
    function askFlow(next) {
        tools.flow("chat-ask-flow", function(done) {
            kit.later(600, function() {
                tools.ask("Please ask me which style I want, then write a summary of Rust.", function() {
                    var card = function() { return tools.walk(tools.grabItem, function(it) { return it.objectName === "questionText" && it.visible; }); };
                    kit.waitFor("the question", function() { return card() !== null; }, 30000, function() {
                        kit.later(2500, function() {
                            var choice = tools.walk(tools.grabItem, function(it) { return it.checkable === true && it.text === "Short" && it.visible; });
                            if (!choice) { kit.fail("the Short answer button was not found"); return; }
                            choice.clicked();
                            tools.waitAnswer(function() { kit.later(2500, done); }, 800);
                        });
                    });
                }, 40);
            });
        }, next);
    }

    function run(next) {
        tools.chain([listFlow, templateFlow, modelFlow, imageFlow, attachFlow, incognitoFlow, askFlow], next);
    }
}
