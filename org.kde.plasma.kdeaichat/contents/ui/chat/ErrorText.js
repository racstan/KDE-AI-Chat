.pragma library

// Plain-language text for the errors the widget shows.
//
// describe(raw) turns whatever a backend or the widget reported ("Request to
// https://... failed (HTTP 429): ...") into
//   {kind, text, detail, settings}
// kind      auth | missing-key | setup | credit | rate | timeout | network |
//           model | server | empty | agent-missing | agent-offline | other
// text      one or two plain sentences
// detail    the original message (without a leading warning sign), "" if it
//           says nothing more than `text`
// settings  true when opening the settings can fix it
// providerName_ (optional) is the provider's display name, used in the model message.
// Plain JavaScript on strings, so tests run it in node.

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

function _result(kind, text, detail, settings) {
    return {"kind": kind, "text": text, "detail": detail === text ? "" : detail, "settings": settings === true};
}

function describe(raw, providerName_) {
    var msg = _clean(raw);
    var low = msg.toLowerCase();
    var status = _status(msg);

    if (/isn't installed|is not installed|no `?(opencode|pi)`? command/.test(low))
        return _result("agent-missing", _agentName(msg) + " isn't installed on this computer. Install it, then try again.", msg, true);
    if (/isn't reachable|isn't running|couldn't be started|could not be started|bridge/.test(low) && /opencode|\bpi\b/.test(low))
        return _result("agent-offline", _agentName(msg) + " isn't running and couldn't be started. Check that it is installed and that its address in Settings is right.", msg, true);

    var provider = /(?:message|chat) with (.+?)\. missing/i.exec(msg);
    var providerName = provider ? provider[1] : "";
    if (/missing:.*api key/i.test(msg))
        return _result("missing-key", "There's no API key for " + (providerName || "this provider") + " yet. Add one in Settings, then try again.", msg, true);
    if (/^cannot send|missing:|isn't set up any more|configure:/.test(low))
        return _result("setup", "This chat isn't set up yet. Finish the provider and model settings, then try again.", msg, true);

    if (status === 401 || status === 403 || /api key (was )?(rejected|invalid|incorrect)|rejected the api key|invalid api key|incorrect api key|unauthori[sz]ed|authentication (failed|error)/.test(low))
        return _result("auth", "Your API key was rejected. Check the key for this provider in Settings.", msg, true);

    var creditWords = /insufficient|out of credit|credits?\b|billing|balance|quota|payment/.test(low);
    if (status === 402 || (creditWords && status !== 429) || (status === 429 && creditWords && /insufficient|credit|billing|balance/.test(low)))
        return _result("credit", "The provider says your account is out of credit or over its quota. Add credit with the provider, or switch to another one.", msg, false);

    if (status === 429 || /rate.?limit|too many requests/.test(low))
        return _result("rate", "The provider is limiting how fast you can send. Wait a moment and try again.", msg, false);

    if (/timed out|timeout/.test(low))
        return _result("timeout", "The provider took too long to answer. Try again, or choose a faster model.", msg, false);

    if (/could not reach|can't reach|cannot reach|network|offline|connection (refused|reset|closed)|failed to fetch|unreachable|getaddrinfo|name not resolved/.test(low) || (status === 0 && /could not (read|start) the (provider|request)/.test(low)))
        return _result("network", "Can't reach the provider. Check your internet connection and the server address in Settings.", msg, true);

    // The chosen model is listed but the account can't use it (NIM: 404 "Function '...': Not found
    // for account", 410 "has reached its end of life"), or the provider says it doesn't know it.
    // A bare 404 (wrong URL) says none of this, so it stays "other".
    var retired = (status === 410 || /model/.test(low)) && /end of life|no longer available|has been (retired|deprecated)|\bretired\b/.test(low);
    var unknown = /model_not_found/.test(low)
        || (/\bfunction\b/.test(low) && /not found/.test(low) && (status === 404 || status === 0))
        || ((status === 404 || status === 400 || status === 0) && /model/.test(low)
            && /not found|does not exist|doesn't exist|not available|unknown|no such|invalid model|not supported/.test(low));
    if (retired || unknown) {
        var who = providerName_ ? "your " + providerName_ + " account" : "your account";
        var lead = retired ? "This model has been retired and isn't available on " + who + " any more."
            : "This model isn't available on " + who + " (it may be retired or not enabled).";
        var body = /\):\s*([\s\S]+)$/.exec(msg);
        return _result("model", lead + " Pick another model in Settings \u2192 Connection, or in this chat's settings."
            + (body ? "\n\n" + body[1].trim() : ""), msg, true);
    }

    if (status >= 500 || /server error|overloaded|bad gateway|service unavailable|internal error/.test(low))
        return _result("server", "The provider had a problem on its side. Try again in a moment.", msg, false);

    if (/empty response/.test(low))
        return _result("empty", "The model sent back nothing. Try again.", msg, false);

    return _result("other", msg || "Something went wrong.", msg, false);
}
