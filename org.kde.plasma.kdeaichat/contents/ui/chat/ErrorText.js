.pragma library

// Plain-language text for the errors the widget shows.
//
// describe(raw) turns whatever a backend or the widget reported ("Request to
// https://... failed (HTTP 429): ...") into
//   {kind, text, detail, settings, checkSetup, template, args, extra}
// kind      auth | missing-key | setup | credit | rate | timeout | network |
//           model | server | empty | agent-missing | agent-offline | image | other
// text      one or two plain sentences
// detail    the original message (without a leading warning sign), "" if it
//           says nothing more than `text`
// settings  true when opening the settings can fix it
// changeModel true when picking another model is the fix (the card offers Change model)
// checkSetup true when Settings → Connection → Check setup can tell what's wrong
// template, args, extra  the plain text for translation: `text` is `template`
//           with %1… filled from `args`, then `extra` (the provider's own words,
//           not translated). The QML shows i18n(template, args…) + extra
//           (translated(), MessageDelegate.qml); templates are marked with
//           I18N_NOOP so xgettext finds them. An empty template means `text` is
//           shown as it is (a service's own message).
// providerName_ (optional) is the provider's display name, used in the model message.
// Plain JavaScript on strings, so tests run it in node.

// Marks text for translation (xgettext -kI18N_NOOP); the QML shows it through i18n().
function I18N_NOOP(text) {
    return text;
}

function _fill(template, args) {
    return String(template).replace(/%(\d)/g, function(all, n) {
        var value = args[parseInt(n, 10) - 1];
        return value === undefined ? all : String(value);
    });
}

var CHECKABLE = ["missing-key", "setup", "network", "timeout", "agent-missing", "agent-offline"];

function _clean(raw) {
    return String(raw === undefined || raw === null ? "" : raw)
        .replace(/^[\s⚠ℹ️❌]+/, "")
        .trim();
}

function _status(raw) {
    var m = /\bHTTP (\d{3})\b/.exec(raw) || /\b(?:status|error|code)[: ]+(\d{3})\b/i.exec(raw);
    return m ? parseInt(m[1], 10) : 0;
}

function _agentName(raw) {
    return /\bpi\b/i.test(raw) && !/opencode/i.test(raw) ? "Pi" : "OpenCode";
}

// template "" = `raw` is shown as it is.
function _result(kind, template, args, detail, settings, extra, raw) {
    var text = template ? _fill(template, args || []) + (extra || "") : raw;
    return {"kind": kind, "text": text, "detail": detail === text ? "" : detail, "settings": settings === true,
            "checkSetup": CHECKABLE.indexOf(kind) >= 0, "changeModel": kind === "model", "template": template, "args": args || [], "extra": extra || ""};
}

// `info` (from describe) in the user's language; tr(template, args) is i18n.
function translated(info, tr) {
    if (!info || !info.template)
        return info ? info.text : "";
    return tr(info.template, info.args || []) + (info.extra || "");
}

function describe(raw, providerName_) {
    var msg = _clean(raw);
    var low = msg.toLowerCase();
    var status = _status(msg);

    // The image services' own messages are already plain words ("AI Horde needs kudos for this size ...").
    if (/^(AI Horde|Pollinations)\b/.test(msg))
        return _result("image", "", [], "", /Settings/.test(msg), "", msg);
    if (/isn't installed|is not installed|no `?(opencode|pi)`? command/.test(low))
        return _result("agent-missing", I18N_NOOP("%1 isn't installed on this computer. Install it, then try again."), [_agentName(msg)], msg, true);
    if (/isn't reachable|isn't running|couldn't be started|could not be started|bridge/.test(low) && /opencode|\bpi\b/.test(low))
        return _result("agent-offline", I18N_NOOP("%1 isn't running and couldn't be started. Check that it is installed and that its address in Settings is right."), [_agentName(msg)], msg, true);

    var provider = /(?:message|chat) with (.+?)\. missing/i.exec(msg);
    var providerName = provider ? provider[1] : "";
    if (/missing:.*api key/i.test(msg))
        return providerName ? _result("missing-key", I18N_NOOP("There's no API key for %1 yet. Add one in Settings, then try again."), [providerName], msg, true)
            : _result("missing-key", I18N_NOOP("There's no API key for this provider yet. Add one in Settings, then try again."), [], msg, true);
    if (/^cannot send|missing:|isn't set up any more|configure:/.test(low))
        return _result("setup", I18N_NOOP("This chat isn't set up yet. Finish the provider and model settings, then try again."), [], msg, true);

    if (status === 401 || status === 403 || /api key (was )?(rejected|invalid|incorrect)|rejected the api key|invalid api key|incorrect api key|unauthori[sz]ed|authentication (failed|error)/.test(low))
        return _result("auth", I18N_NOOP("Your API key was rejected. Check the key for this provider in Settings."), [], msg, true);

    // The model can't take what was sent (a picture, ...): another model is the fix.
    if (/\b(images?|vision|multimodal|multi-modal|image_url)\b/.test(low)
            && /not support|n't support|unsupported|no support|cannot (process|accept|read|handle)|can't (process|accept|read|handle)|does not accept|doesn't accept|only (accepts? )?text|invalid.*image/.test(low)
            && (status === 0 || status === 400 || status === 404 || status === 422)) {
        var detailBody = /\):\s*([\s\S]+)$/.exec(msg);
        return _result("model", I18N_NOOP("This model can't read images. Remove the image, or pick a model that supports images."), [], msg, true,
                       detailBody ? "\n\n" + detailBody[1].trim() : "");
    }

    var creditWords = /insufficient|out of credit|credits?\b|billing|balance|quota|payment/.test(low);
    if (status === 402 || (creditWords && status !== 429) || (status === 429 && creditWords && /insufficient|credit|billing|balance/.test(low)))
        return _result("credit", I18N_NOOP("The provider says your account is out of credit or over its quota. Add credit with the provider, or switch to another one."), [], msg, false);

    if (status === 429 || /rate.?limit|too many requests/.test(low))
        return _result("rate", I18N_NOOP("The provider is limiting how fast you can send. Wait a moment and try again."), [], msg, false);

    if (/timed out|timeout/.test(low))
        return _result("timeout", I18N_NOOP("The provider took too long to answer. Try again, or choose a faster model."), [], msg, false);

    if (/could not reach|can't reach|cannot reach|network|offline|connection (refused|reset|closed)|failed to fetch|unreachable|getaddrinfo|name not resolved/.test(low) || (status === 0 && /could not (read|start) the (provider|request)/.test(low)))
        return _result("network", I18N_NOOP("Can't reach the provider. Check your internet connection and the server address in Settings."), [], msg, true);

    // The chosen model is listed but the account can't use it (NIM: 404 "Function '...': Not found
    // for account", 410 "has reached its end of life"), or the provider says it doesn't know it.
    // A bare 404 (wrong URL) says none of this, so it stays "other".
    var retired = (status === 410 || /model/.test(low)) && /end of life|no longer available|has been (retired|deprecated)|\bretired\b/.test(low);
    var unknown = /model_not_found/.test(low)
        || (/\bfunction\b/.test(low) && /not found/.test(low) && (status === 404 || status === 0))
        || ((status === 404 || status === 400 || status === 0) && /model/.test(low)
            && /not found|does not exist|doesn't exist|not available|unknown|no such|invalid model|not supported/.test(low));
    if (retired || unknown) {
        var body = /\):\s*([\s\S]+)$/.exec(msg);
        var extra = body ? "\n\n" + body[1].trim() : "";
        if (retired && providerName_)
            return _result("model", I18N_NOOP("This model has been retired and isn't available on your %1 account any more. Pick another model in Settings \u2192 Connection, or in this chat's settings."), [providerName_], msg, true, extra);
        if (retired)
            return _result("model", I18N_NOOP("This model has been retired and isn't available on your account any more. Pick another model in Settings \u2192 Connection, or in this chat's settings."), [], msg, true, extra);
        if (providerName_)
            return _result("model", I18N_NOOP("This model isn't available on your %1 account (it may be retired or not enabled). Pick another model in Settings \u2192 Connection, or in this chat's settings."), [providerName_], msg, true, extra);
        return _result("model", I18N_NOOP("This model isn't available on your account (it may be retired or not enabled). Pick another model in Settings \u2192 Connection, or in this chat's settings."), [], msg, true, extra);
    }

    if (status >= 500 || /server error|overloaded|bad gateway|service unavailable|internal error/.test(low))
        return _result("server", I18N_NOOP("The provider had a problem on its side. Try again in a moment."), [], msg, false);

    if (/empty response/.test(low))
        return _result("empty", I18N_NOOP("The model sent back nothing. Try again."), [], msg, false);

    if (!msg)
        return _result("other", I18N_NOOP("Something went wrong."), [], msg, false);
    return _result("other", "", [], msg, false, "", msg);
}
