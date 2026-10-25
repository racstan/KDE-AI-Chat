// Tests for backends/HordeBackend.js, PollinationsBackend.js and ImageHttp.js,
// run by tests/test_image_services.py. No network: a fake XMLHttpRequest and a fake clock.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const read = name => fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/" + name), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
function load(file, expose) {
    const ctx = {};
    vm.runInNewContext(read(file) + "\nthis.exports = {" + expose + "};", ctx);
    return ctx.exports;
}
const H = load("backends/HordeBackend.js", "clientAgent, clampOptions, buildSubmit, parseSubmit, parseCheck, parseGenerations, parseModels, defaultModel, describeError, generate, modelsRequest, BASE_URL, ANONYMOUS_KEY");
const P = load("backends/PollinationsBackend.js", "clampOptions, buildRequest, describeError, createPacer, parseModels, generate, FREE_GAP_MS");
const T = load("backends/ImageHttp.js", "request, bytesOf, retryAfterSeconds, looksLikeImage, randomSeed, clampInt, MAX_IMAGE_BYTES, asciiOf");
const X = load("chat/ImageExtract.js", "bytesToBase64");
const plain = x => JSON.parse(JSON.stringify(x));
const WEBP = Buffer.concat([Buffer.from("RIFF"), Buffer.from([0x24, 0, 0, 0]), Buffer.from("WEBPVP8 "), Buffer.alloc(32)]);
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32)]);
const arrayBuffer = buf => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);

// A fake network: route(method, url, headers, body) -> {status, text?, buffer?, headers?} or "error".
function makeNet(route) {
    const log = [];
    const factory = () => {
        const xhr = {
            readyState: 0, status: 0, response: null, responseText: "", headers: {}, aborted: false, responseType: "",
            open(method, url) { this.method = method; this.url = url; },
            setRequestHeader(k, v) { this.headers[k] = v; },
            getResponseHeader(k) { return (this.answerHeaders || {})[k.toLowerCase()] || null; },
            abort() { this.aborted = true; },
            send(body) {
                log.push({method: this.method, url: this.url, headers: this.headers, body: body ? JSON.parse(body) : null, binary: this.responseType === "arraybuffer"});
                const answer = route(this.method, this.url, this.headers, body);
                if (answer === "error") { this.onerror(); return; }
                this.status = answer.status;
                this.answerHeaders = answer.headers || {};
                this.responseText = answer.text || "";
                this.response = answer.buffer ? arrayBuffer(answer.buffer) : (this.responseType === "arraybuffer" ? arrayBuffer(Buffer.from(answer.text || "")) : null);
                this.readyState = 4;
                this.onreadystatechange();
            },
        };
        return xhr;
    };
    return {factory, log};
}

// A fake clock with timers: advance(ms) runs what is due.
function makeClock() {
    let now = 1000000;
    let nextId = 1;
    const timers = new Map();
    return {
        now: () => now,
        setTimer(fn, ms) { const id = nextId++; timers.set(id, {at: now + ms, fn}); return id; },
        clearTimer(id) { timers.delete(id); },
        advance(ms) {
            const end = now + ms;
            for (;;) {
                let due = null;
                for (const [id, t] of timers) if (t.at <= end && (!due || t.at < timers.get(due).at)) due = id;
                if (due === null) break;
                const t = timers.get(due);
                timers.delete(due);
                now = Math.max(now, t.at);
                t.fn();
            }
            now = end;
        },
        pending: () => timers.size,
    };
}

function run(module, options, route) {
    const net = makeNet(route);
    const clock = makeClock();
    const events = [];
    const handle = module.generate(Object.assign({http: T, xhrFactory: net.factory, setTimer: clock.setTimer, clearTimer: clock.clearTimer,
        now: clock.now, toBase64: X.bytesToBase64, version: "1.4.0", onEvent: e => events.push(e)}, options));
    return {net, clock, events, handle};
}

const json = (status, obj, headers) => ({status, text: JSON.stringify(obj), headers: headers || {}});

const tests = {
    // --- AI Horde: requests ---
    horde_client_agent_names_the_app_version_and_repo() {
        assert.strictEqual(H.clientAgent("1.4.0"), "KDE-AI-Chat:1.4.0:https://github.com/racstan/KDE-AI-Chat");
        assert.strictEqual(H.clientAgent("1.4.0", "https://example.org/w"), "KDE-AI-Chat:1.4.0:https://example.org/w");
    },
    horde_anonymous_request_is_safe_and_within_limits() {
        const r = plain(H.buildSubmit({prompt: "a red fox", model: "Deliberate", width: 2048, height: 530, steps: 500, n: 9, version: "1.4.0"}));
        assert.strictEqual(r.url, "https://aihorde.net/api/v2/generate/async");
        assert.strictEqual(r.headers.apikey, "0000000000");
        assert.strictEqual(r.headers["Client-Agent"], "KDE-AI-Chat:1.4.0:https://github.com/racstan/KDE-AI-Chat");
        assert.strictEqual(r.body.nsfw, false);
        assert.strictEqual(r.body.censor_nsfw, true);
        assert.deepStrictEqual(r.body.models, ["Deliberate"]);
        assert.strictEqual(r.body.params.width, 576);       // anonymous: at most 576, in steps of 64
        assert.strictEqual(r.body.params.height, 512);
        assert.strictEqual(r.body.params.steps, 30);        // anonymous: at most 30 steps
        assert.strictEqual(r.body.params.n, 1);             // and one image at a time
        assert.strictEqual(r.body.params.seed, undefined);  // random
    },
    horde_default_size_and_steps() {
        const r = plain(H.buildSubmit({prompt: "x", model: "m"}));
        assert.deepStrictEqual([r.body.params.width, r.body.params.height, r.body.params.steps, r.body.params.n], [512, 512, 22, 1]);
    },
    horde_own_key_allows_larger_pictures_and_more_images() {
        const r = plain(H.buildSubmit({prompt: "x", model: "m", apiKey: "own-key", width: 1024, height: 1024, n: 4, seed: 42}));
        assert.strictEqual(r.headers.apikey, "own-key");
        assert.deepStrictEqual([r.body.params.width, r.body.params.n, r.body.params.seed], [1024, 4, "42"]);
        assert.strictEqual(r.body.nsfw, false);
    },
    // --- AI Horde: answers ---
    horde_submit_answers() {
        assert.deepStrictEqual(plain(H.parseSubmit(202, '{"id":"abc","kudos":5.0}')), {ok: true, id: "abc", kudos: 5});
        const kudos = plain(H.parseSubmit(403, '{"message":"Due to heavy demand ... requires 31.59 kudos","rc":"KudosUpfront"}'));
        assert.strictEqual(kudos.code, "kudos");
        assert.strictEqual(kudos.message, "AI Horde needs kudos for this size. Pick a smaller picture or fewer steps in Settings → Connection, or add your own AI Horde key.");
        const busy = plain(H.parseSubmit(429, '{"message":"slow down","rc":"TooManyRequests"}', 30));
        assert.deepStrictEqual([busy.code, busy.retryAfter], ["busy", 30]);
        assert.ok(busy.message.includes("30 s"));
        assert.strictEqual(H.parseSubmit(401, '{"rc":"InvalidAPIKey"}').code, "key");
        assert.strictEqual(H.parseSubmit(0, "").code, "unreachable");
        assert.strictEqual(H.parseSubmit(503, "<html>").code, "busy");
        assert.strictEqual(H.parseSubmit(400, '{"message":"width must be a multiple of 64"}').code, "bad_request");
        assert.strictEqual(H.parseSubmit(200, "nonsense").code, "bad_response");
    },
    horde_check_maps_to_progress() {
        const waiting = plain(H.parseCheck({finished: 0, processing: 0, waiting: 1, done: false, queue_position: 3, wait_time: 21, is_possible: true}));
        assert.deepStrictEqual([waiting.phase, waiting.queuePosition, waiting.waitTime, waiting.done, waiting.possible], ["queued", 3, 21, false, true]);
        const working = plain(H.parseCheck({finished: 0, processing: 1, waiting: 0, done: false, queue_position: 0, wait_time: 4}));
        assert.deepStrictEqual([working.phase, working.waitTime, working.done], ["working", 4, false]);
        assert.strictEqual(H.parseCheck({finished: 1, processing: 0, waiting: 0, done: true}).done, true);
        assert.strictEqual(H.parseCheck({faulted: true}).faulted, true);
        assert.strictEqual(H.parseCheck({is_possible: false, waiting: 1}).possible, false);
        assert.strictEqual(H.parseCheck(null).phase, "queued");
    },
    horde_generations_keep_urls_and_inline_data() {
        const g = plain(H.parseGenerations({generations: [
            {img: "https://r2.example.com/a", seed: "12", model: "Deliberate", censored: false},
            {img: "UklGRg==", seed: "13", model: "Deliberate", censored: true},
            {img: "", seed: "1"}, {img: "x", state: "faulted"}]}));
        assert.strictEqual(g.length, 2);
        assert.deepStrictEqual([g[0].url, g[0].seed, g[0].censored], ["https://r2.example.com/a", "12", false]);
        assert.deepStrictEqual([g[1].url, g[1].b64, g[1].censored], ["", "UklGRg==", true]);
    },
    // --- AI Horde: models ---
    horde_model_list_drops_adult_models_and_sorts_by_workers() {
        const list = [
            {name: "WAI-NSFW-illustrious-SDXL", count: 5, type: "image"}, {name: "Grapefruit Hentai", count: 2, type: "image"},
            {name: "Deliberate", count: 7, eta: 10, queued: 3, type: "image"}, {name: "stable_diffusion", count: 9, type: "image"},
            {name: "Dreamshaper", count: 4, nsfw: true, type: "image"}, {name: "Gone", count: 0}, {name: "Pony Diffusion XL", count: 3},
            {name: "Text model", count: 3, type: "text"}, {name: "ICBINP", count: 6, nsfw: false}];
        const models = plain(H.parseModels(list));
        assert.deepStrictEqual(models.map(m => m.id), ["stable_diffusion", "Deliberate", "ICBINP"]);
        assert.deepStrictEqual([models[1].workers, models[1].eta, models[1].queued], [7, 10, 3]);
        assert.strictEqual(H.defaultModel(models), "Deliberate");
        assert.strictEqual(H.defaultModel([{id: "Other", workers: 1}]), "Other");
        assert.strictEqual(H.defaultModel([]), "stable_diffusion");
        assert.strictEqual(H.modelsRequest("1.4.0").url, "https://aihorde.net/api/v2/status/models?type=image&min_count=1");
    },
    // --- AI Horde: a whole job ---
    horde_job_reports_the_queue_then_returns_the_image() {
        let checks = 0;
        const {net, clock, events} = run(H, {prompt: "a fox", model: "Deliberate"}, (method, url) => {
            if (method === "POST") return json(202, {id: "job1", kudos: 5});
            if (url.endsWith("/generate/check/job1")) {
                checks++;
                if (checks === 1) return json(200, {finished: 0, processing: 0, waiting: 1, done: false, queue_position: 3, wait_time: 21, is_possible: true});
                if (checks === 2) return json(200, {finished: 0, processing: 1, waiting: 0, done: false, queue_position: 0, wait_time: 4, is_possible: true});
                return json(200, {finished: 1, processing: 0, waiting: 0, done: true, is_possible: true});
            }
            if (url.endsWith("/generate/status/job1")) return json(200, {generations: [{img: "https://r2.example.com/stable-horde/0", seed: "77", model: "Deliberate", censored: false}]});
            if (url.startsWith("https://r2.example.com/")) return {status: 200, buffer: WEBP};
            throw new Error("unexpected " + method + " " + url);
        });
        clock.advance(20000);
        const types = events.map(e => e.type);
        assert.deepStrictEqual(types, ["submitted", "progress", "progress", "images", "done"]);
        assert.deepStrictEqual([events[1].phase, events[1].queuePosition, events[1].waitTime], ["queued", 3, 21]);
        assert.deepStrictEqual([events[2].phase, events[2].waitTime], ["working", 4]);
        const item = plain(events[3].items[0]);
        assert.deepStrictEqual([item.kind, item.mime, item.seed, item.model, item.width, item.height], ["data", "image/webp", "77", "Deliberate", 512, 512]);
        assert.strictEqual(Buffer.from(item.b64, "base64").compare(WEBP), 0);
        // Every request after the submit carries the honest Client-Agent and the anonymous key; the download carries neither.
        const submit = net.log[0];
        assert.strictEqual(submit.headers.apikey, "0000000000");
        assert.strictEqual(submit.headers["Client-Agent"], "KDE-AI-Chat:1.4.0:https://github.com/racstan/KDE-AI-Chat");
        assert.ok(net.log.filter(r => r.url.includes("/generate/check/")).every(r => r.headers["Client-Agent"].startsWith("KDE-AI-Chat:")));
        assert.ok(net.log[net.log.length - 1].binary);
        assert.ok(!net.log.some(r => r.method === "DELETE"));
    },
    horde_polls_every_three_to_five_seconds_then_slower() {
        const {net, clock} = run(H, {prompt: "x", model: "m"}, (method, url) => {
            if (method === "POST") return json(202, {id: "j", kudos: 1});
            return json(200, {finished: 0, processing: 0, waiting: 1, done: false, queue_position: 9, wait_time: 300, is_possible: true});
        });
        const checks = () => net.log.filter(r => r.url.includes("/check/")).length;
        clock.advance(1000);
        assert.strictEqual(checks(), 1);
        clock.advance(4000 * 3);
        assert.strictEqual(checks(), 4);          // one every 4 s
        clock.advance(60000);
        const before = checks();
        clock.advance(10000);
        assert.strictEqual(checks() - before, 1); // after a minute, one every 10 s
    },
    horde_stop_cancels_the_job_with_delete() {
        const {net, clock, events, handle} = run(H, {prompt: "x", model: "m", apiKey: "own"}, (method) =>
            method === "POST" ? json(202, {id: "j9", kudos: 1}) : json(200, {finished: 0, processing: 0, waiting: 1, queue_position: 2, wait_time: 40, is_possible: true}));
        clock.advance(2000);
        handle.cancel();
        const del = net.log.filter(r => r.method === "DELETE");
        assert.strictEqual(del.length, 1);
        assert.strictEqual(del[0].url, "https://aihorde.net/api/v2/generate/status/j9");
        assert.strictEqual(del[0].headers.apikey, "own");
        const count = events.length;
        clock.advance(60000);
        assert.strictEqual(events.length, count);   // nothing more is reported
        handle.cancel();
        assert.strictEqual(net.log.filter(r => r.method === "DELETE").length, 1);
        assert.strictEqual(clock.pending(), 0);
    },
    horde_stop_before_the_job_exists_sends_no_delete() {
        const {net, handle, events} = run(H, {prompt: "x", model: "m"}, () => ({status: 202, text: "{}"}));
        handle.cancel();
        assert.ok(!net.log.some(r => r.method === "DELETE"));
        assert.ok(!events.some(e => e.type === "images"));
    },
    horde_gives_up_after_the_limit_and_cancels() {
        const {net, clock, events} = run(H, {prompt: "x", model: "m", giveUpMs: 30000}, (method) =>
            method === "POST" ? json(202, {id: "slow", kudos: 1}) : json(200, {finished: 0, processing: 0, waiting: 1, queue_position: 50, wait_time: 900, is_possible: true}));
        clock.advance(60000);
        const error = events.find(e => e.type === "error");
        assert.strictEqual(error.code, "too_long");
        assert.ok(error.message.startsWith("AI Horde "));
        assert.strictEqual(net.log.filter(r => r.method === "DELETE").length, 1);
    },
    horde_reports_an_unavailable_model_and_a_faulted_job() {
        let a = run(H, {prompt: "x", model: "m"}, (method) => method === "POST" ? json(202, {id: "a"}) : json(200, {waiting: 1, is_possible: false, wait_time: 0}));
        a.clock.advance(60000);
        assert.strictEqual(a.events.find(e => e.type === "error").code, "no_workers");
        let b = run(H, {prompt: "x", model: "m"}, (method) => method === "POST" ? json(202, {id: "b"}) : json(200, {faulted: true}));
        b.clock.advance(5000);
        assert.strictEqual(b.events.find(e => e.type === "error").code, "faulted");
    },
    horde_censored_result_is_an_error_not_an_image() {
        const {clock, events} = run(H, {prompt: "x", model: "m"}, (method, url) => {
            if (method === "POST") return json(202, {id: "c"});
            if (url.includes("/check/")) return json(200, {finished: 1, done: true, processing: 0, waiting: 0});
            return json(200, {generations: [{img: "https://r2.example.com/x", seed: "1", model: "m", censored: true}]});
        });
        clock.advance(10000);
        assert.ok(!events.some(e => e.type === "images"));
        assert.strictEqual(events.find(e => e.type === "error").code, "censored");
    },
    horde_submit_errors_are_reported_once_without_retry() {
        for (const [answer, code] of [[json(403, {message: "kudos", rc: "KudosUpfront"}), "kudos"], [json(429, {message: "x"}, {"retry-after": "12"}), "busy"], ["error", "unreachable"]]) {
            const {net, clock, events} = run(H, {prompt: "x", model: "m"}, () => answer);
            clock.advance(60000);
            assert.strictEqual(events.length, 1);
            assert.strictEqual(events[0].code, code);
            assert.strictEqual(net.log.length, 1);   // never tried again
        }
        const limited = run(H, {prompt: "x", model: "m"}, () => json(429, {message: "x"}, {"retry-after": "12"}));
        assert.strictEqual(limited.events[0].retryAfter, 12);
    },
    horde_download_that_is_not_an_image_fails() {
        const {clock, events} = run(H, {prompt: "x", model: "m"}, (method, url) => {
            if (method === "POST") return json(202, {id: "d"});
            if (url.includes("/check/")) return json(200, {finished: 1, done: true});
            if (url.includes("/status/")) return json(200, {generations: [{img: "https://r2.example.com/x", seed: "1", model: "m"}]});
            return {status: 200, buffer: Buffer.from("<html>not an image at all</html>")};
        });
        clock.advance(10000);
        assert.strictEqual(events.find(e => e.type === "error").code, "download");
    },

    // --- Pollinations ---
    pollinations_legacy_url() {
        const r = plain(P.buildRequest({service: "legacy", prompt: "a cat & a dog / 100%", width: 700, height: 40, seed: 5, model: "ignored", apiKey: "sk_secret", random: 0.5}));
        assert.strictEqual(r.url, "https://image.pollinations.ai/prompt/a%20cat%20%26%20a%20dog%20%2F%20100%25?width=704&height=256&seed=5&model=sana");
        assert.strictEqual(r.headers.Authorization, undefined);   // the old service never gets a key
        assert.ok(!r.url.includes("sk_secret"));
    },
    pollinations_key_url_and_header() {
        const r = plain(P.buildRequest({service: "key", prompt: "robot", model: "flux", width: 512, height: 512, apiKey: "sk_abc", random: 0.25}));
        assert.strictEqual(r.url, "https://gen.pollinations.ai/image/robot?width=512&height=512&seed=536870911&model=flux&safe=true");
        assert.strictEqual(r.headers.Authorization, "Bearer sk_abc");
        assert.ok(!r.url.includes("sk_abc"));
        assert.deepStrictEqual([r.params.seed, r.params.model], [536870911, "flux"]);
    },
    pollinations_options_are_clamped() {
        assert.deepStrictEqual(plain(P.clampOptions({width: 5000, height: "x", seed: -1})), {width: 1024, height: 512, seed: -1});
        assert.deepStrictEqual(plain(P.clampOptions({width: 100, height: 1000, seed: 7})), {width: 256, height: 1024, seed: 7});
    },
    pollinations_pacer_keeps_45_seconds() {
        const p = P.createPacer({});
        const t = 1700000000000;
        assert.strictEqual(p.waitMs(t), 0);
        p.sent(t);
        assert.strictEqual(p.waitMs(t), 45000);
        assert.strictEqual(p.waitMs(t + 30000), 15000);
        assert.strictEqual(p.waitMs(t + 45000), 0);
        p.limited(t + 45000, 20);                  // a 402 with retry-after 20: nothing before 20 s (+1 s)
        assert.strictEqual(p.waitMs(t + 45000), 21000);
        const again = P.createPacer(p.state());     // survives a restart of the widget
        assert.strictEqual(again.waitMs(t + 45000), 21000);
    },
    pollinations_free_service_waits_then_sends_once() {
        const pacer = P.createPacer({});
        const clock0 = makeClock();
        pacer.sent(clock0.now() - 10000);          // an image was made 10 s ago
        const answers = [];
        const {net, clock, events} = run(P, {service: "legacy", prompt: "a cat", pacer, random: 0.1}, () => ({status: 200, buffer: PNG, headers: {"content-type": "image/png"}}));
        const countdown = events.filter(e => e.phase === "countdown");
        assert.ok(countdown.length >= 1 && countdown[0].seconds >= 34 && countdown[0].seconds <= 36, JSON.stringify(countdown[0]));
        assert.strictEqual(net.log.length, 0);     // nothing is sent during the countdown
        clock.advance(20000);
        assert.strictEqual(net.log.length, 0);
        clock.advance(20000);
        assert.strictEqual(net.log.length, 1);
        assert.ok(events.some(e => e.type === "images") && events[events.length - 1].type === "done");
        assert.strictEqual(plain(events.find(e => e.type === "images").items[0]).mime, "image/png");
        // The next one has to wait the full gap again.
        assert.ok(pacer.waitMs(clock.now()) > 35000 && pacer.waitMs(clock.now()) <= 45000);
        assert.ok(clock.pending() === 0);
    },
    pollinations_402_is_reported_with_retry_after_and_never_retried() {
        const pacer = P.createPacer({});
        const {net, clock, events} = run(P, {service: "legacy", prompt: "a cat", pacer}, () => ({
            status: 402, text: JSON.stringify({error: {code: "FREE_LIMIT", message: "Free limit reached: 1 image every 45 seconds per IP. Retry after 10s"}}), headers: {"retry-after": "10"}}));
        clock.advance(600000);
        assert.strictEqual(net.log.length, 1);
        const error = events.find(e => e.type === "error");
        assert.deepStrictEqual([error.code, error.retryAfter, error.message], ["free_limit", 10, "Pollinations free limit: try again in 10 s."]);
        assert.ok(pacer.waitMs(clock.now() - 599000) > 0);
    },
    pollinations_402_without_retry_after_assumes_the_gap() {
        const e = plain(P.describeError(402, "", 0, "legacy"));
        assert.deepStrictEqual([e.code, e.retryAfter], ["free_limit", 45]);
    },
    pollinations_key_errors() {
        assert.strictEqual(P.describeError(401, "", 0, "key").code, "key");
        assert.ok(P.describeError(401, "", 0, "legacy").message.includes("no longer gives free images"));
        assert.strictEqual(P.describeError(402, "", 0, "key").code, "credit");
        assert.strictEqual(P.describeError(429, "", 7, "key").retryAfter, 7);
        assert.strictEqual(P.describeError(503, "", 0, "key").code, "server");
        assert.strictEqual(P.describeError(0, "", 0, "key").code, "unreachable");
        assert.strictEqual(P.describeError(404, "", 0, "legacy").code, "gone");
        for (const s of [0, 401, 402, 404, 429, 500, 418]) assert.ok(P.describeError(s, "", 0, "key").message.startsWith("Pollinations"));
    },
    pollinations_keyed_request_goes_out_at_once_with_the_key() {
        const {net, events} = run(P, {service: "key", prompt: "robot", model: "flux", apiKey: "sk_abc"}, () => ({status: 200, buffer: WEBP, headers: {"content-type": "image/webp"}}));
        assert.strictEqual(net.log.length, 1);
        assert.strictEqual(net.log[0].headers.Authorization, "Bearer sk_abc");
        assert.ok(events.some(e => e.type === "images"));
    },
    pollinations_without_key_or_with_a_long_prompt_sends_nothing() {
        const a = run(P, {service: "key", prompt: "robot"}, () => { throw new Error("no request expected"); });
        assert.strictEqual(a.events[0].code, "key");
        const b = run(P, {service: "legacy", prompt: "x".repeat(1001), pacer: P.createPacer({})}, () => { throw new Error("no request expected"); });
        assert.strictEqual(b.events[0].code, "prompt_too_long");
    },
    pollinations_answer_that_is_not_a_picture() {
        const {events} = run(P, {service: "key", prompt: "robot", apiKey: "k"}, () => ({status: 200, buffer: Buffer.from("{\"error\":\"oops\"} padding padding")}));
        assert.strictEqual(events[events.length - 1].code, "not_image");
    },
    pollinations_stop_during_the_countdown_sends_nothing() {
        const pacer = P.createPacer({});
        pacer.sent(makeClock().now());
        const {net, clock, handle} = run(P, {service: "legacy", prompt: "x", pacer}, () => ({status: 200, buffer: PNG}));
        handle.cancel();
        clock.advance(100000);
        assert.strictEqual(net.log.length, 0);
        assert.strictEqual(clock.pending(), 0);
    },
    pollinations_model_list_has_image_models_only_free_first() {
        const models = plain(P.parseModels([
            {name: "qwen/qwen-image-2.1-pro", title: "Qwen Pro", paid_only: true, output_modalities: ["image"]},
            {name: "tongyi-mai/z-image-turbo", title: "Z-Image Turbo", paid_only: false, output_modalities: ["image"]},
            {name: "google/veo-3.1-fast", paid_only: true, output_modalities: ["video"]},
            {name: "community/x/y", paid_only: false, output_modalities: ["image"]},
            {name: "black-forest-labs/flux.1-schnell", title: "FLUX Schnell", paid_only: false, output_modalities: ["image"]}]));
        assert.deepStrictEqual(models.map(m => m.id), ["z-image-turbo", "flux.1-schnell", "qwen-image-2.1-pro"]);
        assert.deepStrictEqual(models.map(m => m.paid), [false, false, true]);
        assert.deepStrictEqual(plain(P.parseModels(null)), []);
    },

    // --- shared HTTP bits ---
    retry_after_seconds_and_dates() {
        assert.strictEqual(T.retryAfterSeconds("10"), 10);
        assert.strictEqual(T.retryAfterSeconds(" 2.2 "), 3);
        assert.strictEqual(T.retryAfterSeconds("", 0), 0);
        assert.strictEqual(T.retryAfterSeconds("soon"), 0);
        assert.strictEqual(T.retryAfterSeconds("Wed, 21 Oct 2026 07:28:30 GMT", Date.parse("Wed, 21 Oct 2026 07:28:00 GMT")), 30);
        assert.strictEqual(T.retryAfterSeconds("999999"), 3600);
    },
    image_signature_check() {
        for (const buf of [WEBP, PNG, Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(20)]), Buffer.concat([Buffer.from("GIF89a"), Buffer.alloc(20)])])
            assert.ok(T.looksLikeImage(new Uint8Array(buf)));
        assert.ok(!T.looksLikeImage(new Uint8Array(Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'></svg>"))));
        assert.ok(!T.looksLikeImage(null));
    },
    http_error_bodies_are_read_as_text() {
        const net = makeNet(() => ({status: 402, buffer: Buffer.from("{\"error\":\"free limit\"}")}));
        let got = null;
        T.request({xhrFactory: net.factory, url: "https://x.example.com/", binary: true}, r => { got = r; });
        assert.strictEqual(got.status, 402);
        assert.strictEqual(got.text, "{\"error\":\"free limit\"}");
    },
    random_seed_and_clamp() {
        assert.strictEqual(T.randomSeed(0.5), 1073741823);
        assert.strictEqual(T.clampInt("12", 1, 5, 3), 5);
        assert.strictEqual(T.clampInt("x", 1, 5, 3), 3);
        assert.strictEqual(T.clampInt(530, 64, 576, 512, 64), 512);
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("ok " + name); } catch (e) { failed++; console.log("FAIL " + name + "\n  " + (e.stack || e).toString().split("\n").slice(0, 4).join("\n  ")); }
}
process.exit(failed ? 1 : 0);
