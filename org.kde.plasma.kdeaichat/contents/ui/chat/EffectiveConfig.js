.pragma library

// Which mode (provider / OpenCode / Pi), provider and model a chat really
// uses. Plain JavaScript on purpose (tested with node): no QML globals.
//
// A CHAT KEEPS ITS MODE. The mode is stored on the chat as `source`
// ("provider" = direct, "opencode" or "pi") when the chat is created, from the
// main mode of that moment, and never changes afterwards: not by the main
// settings, not by the two settings below, not by the Chat info panel. Changing
// the main mode only affects chats created later. A chat that was saved
// without a valid `source` (very old chats) gets one once, from inferSource(),
// and that is stored like any other.
//
// The two settings below (Settings -> Chat) only decide which provider, model,
// agent and variant (reasoning / thinking level) the chat uses WITHIN its mode:
//   perChatModelSettings  false: every chat uses the main settings for those. A
//                         chat's own model settings stay in storage but are
//                         ignored.
//   perChatPriority       "chat" or "main": when a chat has its own model
//                         settings, which side wins.
//
// A chat "has its own model settings" when `ownModel` is true (set by Apply in
// the Chat info panel, which asks for it explicitly). Chats saved before that
// flag existed (ownModel undefined) count as having their own settings when
// any model field is filled in. `source` never counts as a model setting.
//
// Decision table for the fields of the chat's mode (M = the main settings'
// value for that mode, C = this chat's own):
//   switch off                          -> M for everything
//   switch on, chat has no own settings -> M for everything
//   switch on, own settings, "chat"     -> every field from C, or from M where
//                                          C left it empty
//   switch on, own settings, "main"     -> every field from M, or from C only
//                                          where M left it empty (typically:
//                                          no model chosen in the main settings)
// Each mode keeps its own fields (direct: provider + model; OpenCode:
// provider + model + agent + variant; Pi: provider + model + thinking), so a
// fallback always belongs to the mode in use. A chat's direct model (and its
// variant) is only used with the provider it was chosen for. A variant is
// stored as its id only (Variants.js); whether it is still offered by the model
// is checked when the request is built, not here.

var MODES = ["provider", "opencode", "pi"];

function _s(value) {
    return value === undefined || value === null ? "" : String(value).trim();
}

// The mode the main settings select.
function mainMode(main) {
    if (main && main.useOpenCode === true)
        return "opencode";
    if (main && main.usePi === true)
        return "pi";
    return "provider";
}

// A stored mode name is one of MODES.
function isMode(value) {
    return MODES.indexOf(_s(value)) >= 0;
}

// The mode of a chat saved without one: an OpenCode session id means OpenCode,
// a message that came from a Pi dialog (harnessChatId) means Pi, otherwise a
// direct chat. Used once, when the chat is loaded; the result is stored.
function inferSource(chat) {
    if (chat && _s(chat.openCodeSessionId) !== "")
        return "opencode";
    var messages = chat && Array.isArray(chat.messages) ? chat.messages : [];
    for (var i = 0; i < messages.length; i++) {
        if (messages[i] && _s(messages[i].harnessChatId) !== "")
            return "pi";
    }
    return "provider";
}

// The mode a chat is in: its stored one, or (not stored yet) the inferred one.
function chatMode(chat) {
    return isMode(chat && chat.source) ? _s(chat.source) : inferSource(chat);
}

var MODE_NAMES = {"provider": "direct provider", "opencode": "OpenCode", "pi": "Pi"};

// What to tell the user when a chat's mode can't be used right now. The chat
// stays in that mode; it is never switched to another one to get an answer.
function unavailableText(mode, reason) {
    var name = MODE_NAMES[mode] || MODE_NAMES.provider;
    var detail = _s(reason);
    if (detail !== "" && !/[.!?]$/.test(detail))
        detail += ".";
    return "This is " + (mode === "opencode" ? "an " : "a ") + name + " chat and it can't answer right now. " + (detail || "Its mode isn't available.")
        + " It stays in " + name + " mode (a chat never switches mode). Fix that and send again, or start a new chat in another mode.";
}

// True when the chat carries its own model settings (see above).
function hasOwnModelSettings(chat) {
    if (!chat)
        return false;
    if (chat.ownModel === true)
        return true;
    if (chat.ownModel === false)
        return false;
    var keys = ["chatProvider", "chatModel", "chatVariant", "openCodeProvider", "openCodeModel", "openCodeAgent", "openCodeVariant", "piProvider", "piModel", "piThinking"];
    for (var i = 0; i < keys.length; i++) {
        if (_s(chat[keys[i]]) !== "")
            return true;
    }
    return false;
}

// The first non-empty candidate: {value, from}. candidates: [{from, value}].
function _firstOf(candidates) {
    for (var i = 0; i < candidates.length; i++) {
        var v = _s(candidates[i].value);
        if (v !== "")
            return {"value": v, "from": candidates[i].from};
    }
    return {"value": "", "from": "main"};
}

// main: {useOpenCode, usePi, provider, openCodeProvider, openCodeModel, openCodeAgent,
//        openCodeVariant, piProvider, piModel, piThinking,
//        modelFor(providerId) -> that provider's configured model,
//        variantFor(providerId) -> that provider's configured variant id}
// chat: the stored chat ({source, chatProvider, chatModel, chatVariant, openCodeProvider, openCodeModel,
//       openCodeAgent, openCodeVariant, piProvider, piModel, piThinking, ownModel}) or null
// opts: {perChat: bool, priority: "chat" | "main"}
// Returns {mode (always the chat's own), provider, model, agent, thinking, variant,
//          source: "main" | "chat" (where those fields come from),
//          direct: {provider, model}}; provider/model/agent/thinking/variant are those
// of `mode` (variant: the variant id of the mode; for Pi it is the thinking
// level), and `direct` is always the direct-provider pair (used for things
// that always call a provider, such as naming a chat).
function resolve(main, chat, opts) {
    main = main || {};
    var modelFor = typeof main.modelFor === "function" ? main.modelFor : function() { return ""; };
    var variantFor = typeof main.variantFor === "function" ? main.variantFor : function() { return ""; };
    var chatFirst = !(opts && opts.priority === "main");
    var useChat = !!(opts && opts.perChat === true) && hasOwnModelSettings(chat);
    var mainDirect = _s(main.provider) || "openai";
    var mainModeValue = mainMode(main);

    // Pi chats before 1.4.0 kept their provider and model in chatProvider/chatModel.
    var legacyPi = useChat && chat.piProvider === undefined && chat.piModel === undefined && chatMode(chat) === "pi";

    // Candidates for one field, in priority order.
    function field(mainValue, chatValue) {
        var m = {"from": "main", "value": mainValue};
        if (!useChat)
            return _firstOf([m]);
        var c = {"from": "chat", "value": chatValue};
        return _firstOf(chatFirst ? [c, m] : [m, c]);
    }

    // The mode is the chat's own, always; without a chat there is only the main mode.
    var mode = chat ? chatMode(chat) : mainModeValue;

    // Direct: the provider, then the model for it.
    var provider = field(mainDirect, legacyPi ? "" : (useChat ? chat.chatProvider : ""));
    var chatDirectProvider = useChat && !legacyPi ? (_s(chat.chatProvider) || mainDirect) : "";
    var chatModel = useChat && !legacyPi && chatDirectProvider === provider.value ? chat.chatModel : "";
    var model = field(modelFor(provider.value), chatModel);
    var chatVariant = useChat && !legacyPi && chatDirectProvider === provider.value ? chat.chatVariant : "";
    var variant = field(variantFor(provider.value), chatVariant);
    var directFromChat = provider.from === "chat" || model.from === "chat" || variant.from === "chat";

    var result = {"mode": mode, "provider": provider.value, "model": model.value, "agent": "", "thinking": "", "variant": variant.value,
                  "direct": {"provider": provider.value, "model": model.value}};
    var fromChat = false;
    if (mode === "provider") {
        fromChat = directFromChat;
    } else if (mode === "opencode") {
        var ocProvider = field(main.openCodeProvider, useChat ? chat.openCodeProvider : "");
        var ocModel = field(main.openCodeModel, useChat ? chat.openCodeModel : "");
        var ocAgent = field(main.openCodeAgent, useChat ? chat.openCodeAgent : "");
        result.provider = ocProvider.value;
        result.model = ocModel.value;
        result.agent = ocAgent.value;
        var ocVariant = field(main.openCodeVariant, useChat ? chat.openCodeVariant : "");
        result.variant = ocVariant.value;
        fromChat = ocProvider.from === "chat" || ocModel.from === "chat" || ocAgent.from === "chat" || ocVariant.from === "chat";
    } else {
        var piProvider = field(main.piProvider, useChat ? (legacyPi ? chat.chatProvider : chat.piProvider) : "");
        var piModel = field(main.piModel, useChat ? (legacyPi ? chat.chatModel : chat.piModel) : "");
        var piThinking = field(main.piThinking, useChat ? chat.piThinking : "");
        result.provider = piProvider.value;
        result.model = piModel.value;
        result.thinking = piThinking.value;
        result.variant = piThinking.value;
        fromChat = piProvider.from === "chat" || piModel.from === "chat" || piThinking.from === "chat";
    }
    result.source = useChat && fromChat ? "chat" : "main";
    return result;
}

// Builds the main-settings object for resolve() from plasmoid.configuration.
// modelFor / variantFor(providerId) give that provider's configured model / variant id (ProviderService).
function mainFromConfig(config, modelFor, variantFor) {
    config = config || {};
    return {"useOpenCode": config.useOpenCode === true, "usePi": config.usePi === true,
            "provider": config.provider, "openCodeProvider": config.openCodeProvider,
            "openCodeModel": config.openCodeModel, "openCodeAgent": config.openCodeAgent,
            "openCodeVariant": config.openCodeVariant, "piProvider": config.piProvider, "piModel": config.piModel,
            "piThinking": config.piThinking, "modelFor": modelFor, "variantFor": variantFor};
}

// resolve() for a stored chat, with the two settings read from the configuration.
function forSession(config, session, modelFor, variantFor) {
    config = config || {};
    return resolve(mainFromConfig(config, modelFor, variantFor), session,
                   {"perChat": config.perChatModelSettings === true, "priority": config.perChatPriority});
}

// Where an OpenCode agent picked for an open chat (the agent selector above the
// chat) has to be stored so that the chat then really uses it: "chat" (the
// chat's own openCodeAgent) when the chat's own agent decides, else "main"
// (Settings -> OpenCode). Same rules as resolve().
function agentOwner(config, session) {
    config = config || {};
    if (config.perChatModelSettings !== true || !hasOwnModelSettings(session))
        return "main";
    if (config.perChatPriority === "main" && _s(config.openCodeAgent) !== "")
        return "main";
    return "chat";
}

// Pi's thinking levels ("" = the model's default), for the settings and the Chat info line.
var PI_THINKING_LEVELS = ["", "off", "minimal", "low", "medium", "high", "xhigh", "max"];

// The chat's "variant" as a short phrase, or "": Pi's thinking level
// ("thinking high"), OpenCode's agent and variant ("agent build · variant high"),
// a direct chat's variant ("variant high"). `extra` is text the caller brings
// itself (shown as is, and it wins).
function variantText(eff, extra) {
    if (_s(extra) !== "")
        return _s(extra);
    if (eff.mode === "pi" && _s(eff.thinking) !== "")
        return "thinking " + _s(eff.thinking);
    var parts = [];
    if (eff.mode === "opencode" && _s(eff.agent) !== "")
        parts.push("agent " + _s(eff.agent));
    if (eff.mode !== "pi" && _s(eff.variant) !== "")
        parts.push("variant " + _s(eff.variant));
    return parts.join(" · ");
}

// "Pi · OpenAI · gpt-x" for the Chat info panel; names(providerId) -> display name.
// opts (the Chat info line): {directLabel: "Direct" (names the direct mode too),
// variant: text for the end of the line, which also stops OpenCode's agent
// standing in for a missing model}.
function describe(eff, names, opts) {
    var o = opts || {};
    var label = eff.mode === "opencode" ? "OpenCode" : (eff.mode === "pi" ? "Pi" : _s(o.directLabel));
    var parts = [];
    if (label)
        parts.push(label);
    if (eff.provider)
        parts.push(typeof names === "function" ? (names(eff.provider) || eff.provider) : eff.provider);
    if (eff.model)
        parts.push(eff.model);
    else if (eff.mode === "opencode" && eff.agent && o.variant === undefined)
        parts.push(eff.agent);
    if (_s(o.variant) !== "")
        parts.push(_s(o.variant));
    return parts.join(" · ");
}
