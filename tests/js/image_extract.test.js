// Tests for chat/ImageExtract.js (images in a model's reply) and Security.validateImageUrl,
// run by tests/test_image_extract.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const ui = path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/");
function load(file, expose) {
    const src = fs.readFileSync(ui + file, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
    const ctx = {};
    vm.runInNewContext(src + "\nthis.exports = {" + expose + "};", ctx);
    return ctx.exports;
}
const X = load("chat/ImageExtract.js", "parseDataUrl, itemFromUrl, itemFromPart, fromMessage, textOf, extractMarkdown, bytesToBase64, itemKey, MAX_ITEMS");
const S = load("Security.js", "validateImageUrl");
const plain = x => JSON.parse(JSON.stringify(x));
const PNG_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==";

const tests = {
    data_urls_are_parsed_and_checked() {
        assert.deepStrictEqual(plain(X.parseDataUrl("data:image/png;base64," + PNG_B64)), {mime: "image/png", b64: PNG_B64});
        assert.deepStrictEqual(plain(X.parseDataUrl("data:image/jpg;base64,QUJD")), {mime: "image/jpeg", b64: "QUJD"});
        assert.strictEqual(X.parseDataUrl("data:image/svg+xml;base64,QUJD"), null);
        assert.strictEqual(X.parseDataUrl("data:text/html;base64,QUJD"), null);
        assert.strictEqual(X.parseDataUrl("data:image/png,notbase64"), null);
        assert.strictEqual(X.parseDataUrl("data:image/png;base64,@@@@"), null);
        assert.strictEqual(X.parseDataUrl("data:image/png;base64,"), null);
        assert.strictEqual(X.parseDataUrl(null), null);
    },
    openrouter_message_images() {
        const msg = {role: "assistant", content: "Here you go", images: [{type: "image_url", image_url: {url: "data:image/png;base64," + PNG_B64}}]};
        assert.deepStrictEqual(plain(X.fromMessage(msg)), [{kind: "data", b64: PNG_B64, mime: "image/png"}]);
    },
    openrouter_delta_images_with_an_https_url() {
        const delta = {images: [{type: "image_url", image_url: {url: "https://cdn.example.com/a.png"}, index: 0}]};
        assert.deepStrictEqual(plain(X.fromMessage(delta)), [{kind: "url", url: "https://cdn.example.com/a.png"}]);
    },
    duplicate_images_are_dropped_and_the_count_is_capped() {
        const part = {type: "image_url", image_url: {url: "data:image/png;base64," + PNG_B64}};
        assert.strictEqual(X.fromMessage({images: [part, part, part]}).length, 1);
        const many = [];
        for (let i = 0; i < 20; i++) many.push({image_url: "https://x.example.com/" + i + ".png"});
        assert.strictEqual(X.fromMessage({images: many}).length, X.MAX_ITEMS);
    },
    openai_style_content_parts() {
        const msg = {content: [{type: "text", text: "hi"}, {type: "output_image", image_url: "data:image/webp;base64,QUJD"},
                               {type: "image", b64_json: PNG_B64}, {type: "image", source: {type: "base64", media_type: "image/gif", data: "QUJE"}}]};
        const items = plain(X.fromMessage(msg));
        assert.deepStrictEqual(items.map(i => i.mime), ["image/webp", "image/png", "image/gif"]);
        assert.strictEqual(X.textOf(msg.content), "hi");
    },
    gemini_inline_data() {
        assert.deepStrictEqual(plain(X.itemFromPart({inlineData: {mimeType: "image/jpeg", data: "QUJD"}})), {kind: "data", b64: "QUJD", mime: "image/jpeg"});
    },
    unsafe_or_odd_parts_are_ignored() {
        assert.strictEqual(X.itemFromPart({image_url: "http://x.example.com/a.png"}), null);
        assert.strictEqual(X.itemFromPart({image_url: "file:///etc/passwd"}), null);
        assert.strictEqual(X.itemFromPart({image_url: "javascript:alert(1)"}), null);
        assert.strictEqual(X.itemFromPart({b64_json: "not base64!!"}), null);
        assert.strictEqual(X.itemFromPart(null), null);
        assert.deepStrictEqual(plain(X.fromMessage({images: "nope"})), []);
        assert.deepStrictEqual(plain(X.fromMessage(null)), []);
    },
    text_of_content() {
        assert.strictEqual(X.textOf("plain"), "plain");
        assert.strictEqual(X.textOf([{type: "text", text: "a"}, {type: "text", text: "b"}]), "ab");
        assert.strictEqual(X.textOf(undefined), "");
    },
    markdown_links_become_placeholders_and_a_list() {
        const text = "Look: ![a cat](https://img.example.com/cat.png) and ![](https://img.example.com/b.jpg \"title\").";
        const r = plain(X.extractMarkdown(text));
        assert.strictEqual(r.text, "Look: [image: a cat] and [image].");
        assert.deepStrictEqual(r.links, [{alt: "a cat", url: "https://img.example.com/cat.png"}, {alt: "", url: "https://img.example.com/b.jpg"}]);
        assert.deepStrictEqual(r.data, []);
    },
    markdown_data_images_are_pulled_out_of_the_text() {
        const r = plain(X.extractMarkdown("x ![pic](data:image/png;base64," + PNG_B64 + ") y"));
        assert.strictEqual(r.text, "x [image: pic] y");
        assert.deepStrictEqual(r.data, [{kind: "data", b64: PNG_B64, mime: "image/png"}]);
    },
    markdown_http_and_other_schemes_are_never_offered() {
        const r = plain(X.extractMarkdown("![a](http://x.example.com/a.png) ![b](file:///etc/passwd) ![c](//x.example.com/c.png) ![d](javascript:x)"));
        assert.deepStrictEqual(r.links, []);
        assert.ok(!/http|file:|javascript/.test(r.text), r.text);
    },
    markdown_accept_callback_filters_links() {
        const r = plain(X.extractMarkdown("![a](https://localhost/a.png) ![b](https://ok.example.com/b.png)", u => !/localhost/.test(u)));
        assert.deepStrictEqual(r.links.map(l => l.url), ["https://ok.example.com/b.png"]);
    },
    markdown_without_images_is_untouched_and_repeats_count_once() {
        assert.strictEqual(X.extractMarkdown("a [link](https://x.example.com) b").text, "a [link](https://x.example.com) b");
        assert.strictEqual(X.extractMarkdown("![a](https://x.example.com/1.png)![a](https://x.example.com/1.png)").links.length, 1);
        assert.strictEqual(X.extractMarkdown(null).text, "");
    },
    base64_of_bytes() {
        const bytes = new Uint8Array(Buffer.from("hello world, this is a longer test string!"));
        assert.strictEqual(X.bytesToBase64(bytes), Buffer.from(bytes).toString("base64"));
        for (const n of [0, 1, 2, 3, 4, 5]) {
            const b = new Uint8Array(n).map((_, i) => 250 - i);
            assert.strictEqual(X.bytesToBase64(b), Buffer.from(b).toString("base64"));
        }
        const big = new Uint8Array(200000).map((_, i) => i % 251);
        assert.strictEqual(X.bytesToBase64(big), Buffer.from(big).toString("base64"));
    },
    image_url_policy() {
        const ok = ["https://cdn.example.com/a.png", "https://example.com:8443/a.png?x=1", "https://93.184.216.34/a.png"];
        const bad = ["http://example.com/a.png", "https://localhost/a.png", "https://127.0.0.1/a.png", "https://10.1.2.3/a.png",
                     "https://192.168.1.2/a.png", "https://172.16.0.1/a.png", "https://169.254.169.254/latest", "https://[::1]/a.png",
                     "https://printer.local/a.png", "https://intranet/a.png", "https://user@example.com/a.png", "https://0x7f000001/a.png",
                     "https://2130706433/a.png", "file:///etc/passwd", "data:image/png;base64,QUJD", "javascript:alert(1)", "",
                     "https://example.com/" + "a".repeat(2100)];
        for (const url of ok) assert.strictEqual(S.validateImageUrl(url), url, url);
        for (const url of bad) assert.strictEqual(S.validateImageUrl(url), "", url);
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try { fn(); console.log("ok " + name); } catch (e) { failed++; console.log("FAIL " + name + ": " + e.message); }
}
process.exit(failed ? 1 : 0);
