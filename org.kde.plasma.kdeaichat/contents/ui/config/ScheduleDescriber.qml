// "Describe when": one conversation with the main settings' provider and
// model (Settings → Connection, direct mode; OpenCode and Pi are not used)
// that turns a sentence into rules. The request is the chat-title one-shot
// request (chat/ChatTitle.js); the prompt and the parsing are in
// ScheduleDescribe.js. When the model asks a question, answer() continues the
// conversation. Rules are checked with the helper's schedule_preview before
// rulesReady() hands them to the editor; nothing is saved here.
import QtQuick
import "../ProviderService.js" as ProviderService
import "../Security.js" as Sec
import "../chat/ChatTitle.js" as ChatTitle
import "ScheduleDescribe.js" as Describe

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QtObject {
    id: describer

    property var configuration: null
    // store/Wallet.qml: keys by provider id; loaded on first use if empty.
    property var wallet: null
    // ScheduleService: its preview() validates the rules.
    property var service: null
    // Replaces XMLHttpRequest in tests.
    property var xhrFactory: null
    property var now: null

    // "idle", "busy", "question" or "error".
    property string phase: "idle"
    property string question: ""
    property var options: []
    property string error: ""
    property var turns: []
    // The model's last answer as received (for scripts/dev-describe.sh).
    property string lastReply: ""
    property int _questions: 0
    property int _generation: 0
    property bool _walletTried: false
    property string _sentence: ""

    // rules: the v2 rules; preview: the helper's schedule_preview answer for them.
    signal rulesReady(var rules, var preview)

    readonly property string providerId: configuration ? String(configuration.provider || "") : ""
    readonly property var providerConfig: {
        var cfg = ProviderService.getProviderConfig(providerId, configuration || {});
        cfg.baseUrl = Sec.validateHttpUrl(cfg.baseUrl);
        return cfg;
    }
    readonly property bool available: providerId !== "" && providerConfig.found === true && providerConfig.type !== "image"
        && providerConfig.baseUrl !== "" && String(providerConfig.model || "") !== ""
    readonly property string providerName: providerId ? ProviderService.getProviderDisplayName(providerId, configuration || {}) : ""

    function start(text) {
        var sentence = String(text || "").trim();
        if (!sentence || phase === "busy")
            return;
        turns = [{"role": "user", "content": Describe.describeTurn(sentence)}];
        _sentence = sentence;
        _questions = 0;
        _send();
    }

    function answer(text) {
        var reply = String(text || "").trim();
        if (!reply || phase !== "question")
            return;
        turns = turns.concat([{"role": "user", "content": Describe.answerTurn(question, reply)}]);
        _send();
    }

    function cancel() {
        _generation += 1;
        phase = "idle";
        question = "";
        options = [];
        error = "";
    }

    function _fail(text) {
        phase = "error";
        error = text;
        question = "";
        options = [];
    }

    function _send() {
        if (!available) {
            _fail(i18n("Describing needs a provider with a model in Settings → Connection."));
            return;
        }
        var cfg = Object.assign({}, providerConfig);
        var key = wallet && wallet.keys ? String(wallet.keys[providerId] || "") : "";
        if (!key && !cfg.allowEmptyKey) {
            if (wallet && !_walletTried && typeof wallet.load === "function") {
                _walletTried = true;
                phase = "busy";
                wallet.load(function() { describer._send(); });
                return;
            }
            _fail(i18n("There is no API key for %1. Add it in Settings → Connection.", providerName));
            return;
        }
        cfg.apiKey = key;
        var generation = ++_generation;
        phase = "busy";
        error = "";
        var request = ChatTitle.buildChatRequest(cfg, Describe.buildMessages(turns, now || new Date()), 4000);
        ChatTitle.send(request, 90000, xhrFactory || function() { return new XMLHttpRequest(); }, function(text, failure) {
            if (generation !== describer._generation)
                return;
            if (failure)
                describer._fail(i18n("%1 could not answer (%2).", describer.providerName, failure));
            else
                describer._handle(text, generation);
        });
    }

    function _handle(text, generation) {
        lastReply = String(text || "");
        var reply = Describe.parseReply(text);
        if (reply.error) {
            _fail(i18n("The model's answer was not usable. Try again, or put it differently."));
            return;
        }
        turns = turns.concat([{"role": "assistant", "content": JSON.stringify(reply)}]);
        // A phrase with two common readings ("every other day") is always
        // asked about first, with both readings as options, even when the
        // model guessed or asked about something else; the answer goes back
        // to the model, which then gives the rules.
        var unsure = _questions === 0 ? Describe.ambiguity(_sentence) : null;
        if (unsure)
            reply = unsure;
        if (reply.question) {
            _questions += 1;
            if (_questions > Describe.MAX_QUESTIONS) {
                _fail(i18n("The model keeps asking. Set the rules below by hand."));
                return;
            }
            question = reply.question;
            options = reply.options;
            phase = "question";
            return;
        }
        if (!service) {
            _fail(i18n("The rules could not be checked."));
            return;
        }
        service.preview({"rules": reply.rules}, function(result) {
            if (generation !== describer._generation)
                return;
            if (!result.ok) {
                describer._fail(i18n("The model suggested rules that don't work (%1). Try again, or put it differently.", result.error));
                return;
            }
            describer.phase = "idle";
            describer.question = "";
            describer.options = [];
            describer.rulesReady(reply.rules, result);
        });
    }
}
