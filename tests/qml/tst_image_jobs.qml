// Making pictures: /image and chats that use an image service. The real request code
// (chat/SendController.qml, ReplyEvents.qml, ImageStore.qml, ImageJobs.qml and the
// AI Horde / Pollinations backends) runs against a fake network and a fast clock; the
// helper that saves files is a stand-in. The progress card (chat/ImageJobCard.qml)
// shows what the reply's job says.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/chat/ErrorText.js" as ErrorText
import "../../org.kde.plasma.kdeaichat/contents/ui/ProviderService.js" as ProviderService

Item {
    id: root
    width: 480
    height: 300

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    // ── The fake network: route(method, url) -> {status, body?, bytes?, headers?} ──
    property var requests: []
    property var route: null
    function webpBytes() {
        var head = "RIFF$\u0000\u0000\u0000WEBPVP8 ";
        var buffer = new ArrayBuffer(48);
        var bytes = new Uint8Array(buffer);
        for (var i = 0; i < head.length; i++)
            bytes[i] = head.charCodeAt(i);
        return buffer;
    }
    function makeXhr() {
        var x = {readyState: 0, status: 0, responseText: "", response: null, responseType: "", headers: {}, answer: {}};
        x.open = function(method, url) { x.method = method; x.url = url; };
        x.setRequestHeader = function(k, v) { x.headers[k] = v; };
        x.getResponseHeader = function(k) { return (x.answer.headers || {})[k.toLowerCase()] || null; };
        x.abort = function() { x.aborted = true; };
        x.send = function(body) {
            root.requests = root.requests.concat([{method: x.method, url: x.url, headers: x.headers, body: body ? JSON.parse(body) : null}]);
            var answer = root.route(x.method, x.url);
            if (!answer)
                return;   // never answers (a request still out)
            Qt.callLater(function() {
                if (x.aborted) return;
                x.answer = answer;
                x.status = answer.status;
                if (x.responseType === "arraybuffer")
                    x.response = answer.bytes || null;
                else
                    x.responseText = JSON.stringify(answer.body || {});
                x.readyState = 4;
                x.onreadystatechange();
            });
        };
        return x;
    }
    function count(method, part) {
        return root.requests.filter(function(r) { return r.method === method && r.url.indexOf(part) >= 0; }).length;
    }

    Component {
        id: fastTimer
        Timer { repeat: false }
    }
    // Every wait is 100 times shorter (AI Horde's 4 s between checks is 40 ms here).
    function fastSetTimer(fn, ms) {
        var t = fastTimer.createObject(root, {"interval": Math.max(1, Math.round(ms / 100))});
        t.triggered.connect(function() { fn(); t.destroy(); });
        t.start();
        return t;
    }

    // The progress of the reply being made, as each change was seen.
    property var jobLog: []
    readonly property var streamingJob: {
        var list = chat.messages;
        for (var i = list.length - 1; i >= 0; i--)
            if (list[i].imageJob) return list[i].imageJob;
        return null;
    }
    onStreamingJobChanged: if (streamingJob) jobLog = jobLog.concat([streamingJob])

    // ── The widget root, as far as these modules use it ──────────────────────
    QtObject {
        id: chat
        property var plasmoid: QtObject {
            property var metaData: ({"version": "1.4.0", "website": "https://github.com/racstan/KDE-AI-Chat"})
            property var configuration: QtObject {
                property string providersJson: ""
                property string imageProvider: ""
                property string pollinationsFreeState: ""
                property string provider: "nvidia"
            }
        }
        property var sessions: [{"value": "s1", "messages": []}]
        property string currentSessionId: "s1"
        property string currentSessionTitle: "Pictures"
        property var messages: []
        property bool loading: false
        property var activeXhr: null
        property int requestGeneration: 0
        property string activeRequestSessionId: ""
        property string currentStreamKey: ""
        property int currentStreamIndex: -1
        property string currentStreamText: ""
        property string currentStreamReasoning: ""
        property string currentStreamExtractedReasoning: ""
        property bool streamingResponse: false
        property var currentStreamUsage: ({})
        property var walletApiKeys: ({})
        property var errors: []
        property int queueCounter: 0
        property string schedulerResumeSessionId: ""
        property string effectiveProvider: "nvidia"
        property bool openCodeMode: false
        property bool piMode: false
        property var streamBuffer: Chat.StreamBuffer { target: chat; maxChars: 2000000 }
        property var imageStore: store
        onMessagesChanged: {
            if (chat.currentStreamIndex >= 0)
                chat.currentStreamIndex = indexOfId(chat.currentStreamKey);
        }
        function indexOfId(id) {
            for (var i = 0; i < messages.length; i++)
                if (messages[i].id === id) return i;
            return -1;
        }
        function sessionIndexById(id) { return id === "s1" ? 0 : -1; }
        function switchSession(id) {}
        function effectiveConfig(id) { return {"mode": "provider", "direct": {"provider": effectiveProvider, "model": ""}}; }
        function getEffectiveProvider(id) { return effectiveProvider; }
        function getProviderConfig(id, sessionId) {
            var cfg = ProviderService.getProviderConfig(id, plasmoid.configuration);
            cfg.apiKey = walletApiKeys[id] || "";
            return cfg;
        }
        function providerDisplayName(id) { return ProviderService.getProviderDisplayName(id, plasmoid.configuration); }
        function requestIsCurrent(s, g) { return sender.requestIsCurrent(s, g); }
        function beginRequest(s) { return sender.beginRequest(s); }
        function applyBackendEvent(e, m, x) { replies.applyBackendEvent(e, m, x); }
        function updateMessageAt(i, f) { replies.updateMessageAt(i, f); }
        function resetProviderStreamingState() { replies.resetProviderStreamingState(); }
        function saveCurrentSessionState(t) {}
        function persistSessions() {}
        function pushErrorMessage(t) { errors = errors.concat([t]); }
        function triggerNotificationSound() {}
        function maybeGenerateChatTitle() {}
        function processNextQueuedMessage() { sender.processNextQueuedMessage(); }
        function stopStreaming() { sender.stopStreaming(); }
        function scrollToBottom() {}
        function nameChatFromFirstMessage(t) {}
        function applySessionSource(s) {}
        function setCurrentSessionSource() {}
        function doDirectRequest(c, s, g) { errors = errors.concat(["text request: should not happen"]); }
    }

    Chat.ReplyEvents {
        id: replies
        chat: chat
        notifierRef: QtObject { function replyFinished() {} }
    }
    Chat.SendController {
        id: sender
        chat: chat
        notifierRef: QtObject { function failed() {} }
    }
    Chat.ImageStore {
        id: store
        chat: chat
        directory: "/data/kdeaichat/chats/applet-7"
        property var log: []
        runHelper: function(command, payload, onDone) {
            log = log.concat([{command: command, payload: payload}]);
            var out = command === "image_save" ? {"path": "images/" + payload.chat + "/" + payload.message + "-" + payload.n + ".webp", "mime": "image/webp", "bytes": 48} : {};
            onDone(JSON.stringify(out), 0, "");
        }
        stage: function(fileName, text) {}
    }

    Chat.ImageJobCard {
        id: card
        width: 440
        x: 20
        y: 20
        job: root.streamingJob || root.shownJob
        live: true
        onStopRequested: chat.stopStreaming()   // as chat/MessageDelegate.qml does
    }
    property var shownJob: ({})

    HarnessTestCase {
        id: tc
        name: "ImageJobs"

        readonly property var horde: ({"id": "aihorde", "name": "AI Horde (images)", "type": "image", "service": "horde", "baseUrl": "https://aihorde.net/api/v2", "model": "Deliberate", "accepted": true, "options": {}})
        readonly property var freePollinations: ({"id": "pollinations_free", "name": "Pollinations free", "type": "image", "service": "pollinations-legacy", "baseUrl": "https://image.pollinations.ai", "model": "sana", "accepted": true, "options": {}})

        // AI Horde that queues the job (place 3), works on it, then hands over one picture.
        function hordeRoute(checksBeforeDone) {
            var checks = 0;
            return function(method, url) {
                if (method === "POST") return {status: 202, body: {id: "job-1", kudos: 5}};
                if (method === "DELETE") return {status: 200, body: {}};
                if (url.indexOf("/generate/check/") >= 0) {
                    checks++;
                    if (checks === 1) return {status: 200, body: {finished: 0, processing: 0, waiting: 1, done: false, queue_position: 3, wait_time: 21, is_possible: true}};
                    if (checks < checksBeforeDone) return {status: 200, body: {finished: 0, processing: 1, waiting: 0, done: false, queue_position: 0, wait_time: 4, is_possible: true}};
                    return {status: 200, body: {finished: 1, processing: 0, waiting: 0, done: true}};
                }
                if (url.indexOf("/generate/status/") >= 0)
                    return {status: 200, body: {done: true, generations: [{img: "https://bucket.r2.example/img-1?sig=secret", seed: "7", model: "Deliberate", censored: false, state: "ok"}]}};
                if (url.indexOf("r2.example") >= 0) return {status: 200, bytes: root.webpBytes()};
                return {status: 404, body: {}};
            };
        }

        function configure(list, imageProvider) {
            chat.plasmoid.configuration.providersJson = JSON.stringify(list);
            chat.plasmoid.configuration.imageProvider = imageProvider || "";
        }

        function init() {
            store.jobs.xhrFactory = root.makeXhr;
            store.jobs.setTimer = root.fastSetTimer;
            store.jobs.settleInterval = 5;
            store.jobs._pacer = null;
            store.log = [];
            root.requests = [];
            root.jobLog = [];
            root.shownJob = ({});
            chat.messages = [];
            chat.errors = [];
            chat.loading = false;
            chat.activeXhr = null;
            chat.currentStreamIndex = -1;
            chat.effectiveProvider = "nvidia";
            chat.walletApiKeys = ({});
            chat.plasmoid.configuration.pollinationsFreeState = "";
            configure([{id: "nvidia", name: "NVIDIA", type: "openai-compat", baseUrl: "https://nim.example/v1", model: "m"}, horde]);
        }

        function test_1_image_command_shows_queue_progress_then_the_picture() {
            root.route = hordeRoute(3);
            var result = chat.imageStore.jobs ? sender.sendImageCommand("a red fox in the snow") : null;
            verify(result.ok, JSON.stringify(result));
            compare(chat.messages[0].role, "user");
            compare(chat.messages[0].content, "/image a red fox in the snow");
            verify(chat.loading);
            tryVerify(function() { return !chat.loading; }, 5000);
            compare(chat.errors, []);

            // What was sent: only the prompt, safe, with the app's honest name.
            var post = root.requests[0];
            compare(post.url, "https://aihorde.net/api/v2/generate/async");
            compare(post.body.prompt, "a red fox in the snow");
            compare(post.body.nsfw, false);
            compare(post.headers.apikey, "0000000000");
            compare(post.headers["Client-Agent"], "KDE-AI-Chat:1.4.0:https://github.com/racstan/KDE-AI-Chat");
            compare(post.body.params.width, 512);

            // The card's progress: the queue place and wait, then the work.
            var queued = root.jobLog.filter(function(j) { return j.phase === "queued" && j.queuePosition === 3; });
            verify(queued.length > 0, JSON.stringify(root.jobLog));
            compare(queued[0].waitTime, 21);
            verify(root.jobLog.some(function(j) { return j.phase === "working"; }));

            // The reply: one saved picture with its notes, no job left, no signed link anywhere.
            var reply = chat.messages[chat.messages.length - 1];
            compare(reply.role, "assistant");
            verify(!reply.imageJob);
            compare(reply.images.length, 1);
            compare(reply.images[0].path, "images/s1/" + reply.id + "-0.webp");
            compare(reply.images[0].prompt, "a red fox in the snow");
            compare(reply.images[0].service, "AI Horde");
            compare(reply.images[0].model, "Deliberate");
            compare(reply.images[0].seed, "7");
            compare(reply.images[0].provider, "aihorde");
            verify(JSON.stringify(chat.messages).indexOf("r2.example") < 0);
            verify(JSON.stringify(store.log).indexOf("r2.example") < 0, "the picture's bytes go through a staging file");
            compare(root.count("DELETE", "/generate/status/"), 0, "a finished job is not cancelled");
        }

        function test_2_card_says_the_place_and_the_wait() {
            root.shownJob = {"service": "horde", "name": "AI Horde", "phase": "queued", "queuePosition": 3, "waitTime": 21};
            compare(findChild(card, "jobStatus").text, "In AI Horde's queue: place 3, about 21 s left.");
            root.shownJob = {"service": "horde", "name": "AI Horde", "phase": "working", "waitTime": 4};
            compare(findChild(card, "jobStatus").text, "AI Horde is making your picture: about 4 s left.");
            root.shownJob = {"service": "pollinations-legacy", "name": "Pollinations", "phase": "countdown", "seconds": 38};
            compare(findChild(card, "jobStatus").text, "The older free Pollinations service makes one picture every 45 seconds. Yours starts in 38 s.");
            verify(findChild(card, "jobStop").visible);
            root.shownJob = {"service": "horde", "name": "AI Horde", "phase": "queued", "queuePosition": 12, "waitTime": 140};
            wait(50);
            screenshot(card, "image-job-card");
        }

        function test_3_stop_cancels_the_horde_job() {
            root.route = hordeRoute(1000000);
            verify(sender.sendImageCommand("a lighthouse").ok);
            tryVerify(function() { return root.jobLog.some(function(j) { return j.phase === "working"; }); }, 3000);
            mouseClick(findChild(card, "jobStop"));
            compare(root.count("DELETE", "/generate/status/job-1"), 1, "the job is cancelled with DELETE");
            verify(!chat.loading);
            compare(chat.messages.length, 1, "the unfinished reply goes away");
            compare(chat.errors, []);
            var checks = root.count("GET", "/generate/check/");
            wait(200);
            compare(root.count("GET", "/generate/check/"), checks, "no more checks after Stop");
        }

        function test_4_errors_come_in_plain_words() {
            root.route = function(method, url) {
                return {status: 403, body: {message: "Due to heavy demand, for requests over 586x586 ...", rc: "KudosUpfront"}};
            };
            verify(sender.sendImageCommand("a castle").ok);
            tryVerify(function() { return !chat.loading; }, 3000);
            compare(chat.errors.length, 1);
            verify(chat.errors[0].indexOf("AI Horde needs kudos") === 0, chat.errors[0]);
            var shown = ErrorText.describe(chat.errors[0], "AI Horde");
            compare(shown.kind, "image");
            compare(shown.text, chat.errors[0]);
            compare(root.count("POST", "generate/async"), 1, "no retry");
        }

        function test_5_needs_a_switched_on_service() {
            configure([]);
            compare(sender.sendImageCommand("x").code, "none");
            var off = Object.assign({}, horde, {"accepted": false});
            configure([off]);
            var result = sender.sendImageCommand("x");
            compare(result.code, "invalid");
            verify(result.problem.indexOf("switched off") >= 0, result.problem);
            compare(root.requests.length, 0);
            compare(chat.messages.length, 0);
        }

        function test_6_older_free_pollinations_counts_down_the_45_seconds() {
            configure([freePollinations]);
            chat.plasmoid.configuration.pollinationsFreeState = JSON.stringify({"lastAt": Date.now() - 7000, "blockedUntil": 0});
            root.route = function() { return {status: 200, bytes: root.webpBytes()}; };
            verify(sender.sendImageCommand("a cat").ok);
            tryVerify(function() { return root.jobLog.some(function(j) { return j.phase === "countdown"; }); }, 2000);
            var first = root.jobLog.filter(function(j) { return j.phase === "countdown"; })[0];
            verify(first.seconds >= 37 && first.seconds <= 38, first.seconds);
            compare(root.requests.length, 0, "nothing goes out during the gap");
            chat.stopStreaming();
            verify(!chat.loading);
        }

        function test_7_older_free_pollinations_honours_402_and_retry_after() {
            configure([freePollinations]);
            root.route = function() { return {status: 402, headers: {"retry-after": "30"}, body: {error: {code: "FREE_LIMIT", message: "Free limit reached"}}}; };
            verify(sender.sendImageCommand("a dog").ok);
            tryVerify(function() { return !chat.loading; }, 3000);
            compare(root.requests.length, 1);
            verify(root.requests[0].url.indexOf("https://image.pollinations.ai/prompt/a%20dog?") === 0, root.requests[0].url);
            verify(root.requests[0].headers["Referer"] === undefined && root.requests[0].headers["User-Agent"] === undefined);
            compare(chat.errors, ["Pollinations free limit: try again in 30 s."]);
            var state = JSON.parse(chat.plasmoid.configuration.pollinationsFreeState);
            verify(state.blockedUntil - Date.now() > 29000, "the wait is kept");
            // The next request waits for it, with a countdown.
            root.jobLog = [];
            verify(sender.sendImageCommand("a dog").ok);
            tryVerify(function() { return root.jobLog.some(function(j) { return j.phase === "countdown" && j.seconds >= 30; }); }, 2000);
            compare(root.requests.length, 1);
            chat.stopStreaming();
        }

        function test_8_a_chat_with_an_image_service_turns_messages_into_pictures() {
            chat.effectiveProvider = "aihorde";
            root.route = hordeRoute(2);
            sender.appendUserMessage("a quiet harbour at dawn", "queued", [], []);
            sender.sendMessageByIndex(0);
            tryVerify(function() { return !chat.loading; }, 5000);
            compare(chat.errors, []);
            compare(root.requests[0].body.prompt, "a quiet harbour at dawn");
            var reply = chat.messages[chat.messages.length - 1];
            compare(reply.images.length, 1);
            compare(chat.openCodeMode || chat.piMode, false, "the chat stays a direct chat");
        }
    }
}
