// The editable copy of one chat's own settings behind the Chat info panel
// (ChatSettingsDialog.qml). load() reads the chat's overrides, the form
// edits the properties, save() writes them back in one go through
// rootRef.setSessionOverrides, and nothing else in the widget changes until
// then. A chat keeps the mode it was started in, so `mode` is read-only here
// and save() never writes `source`. It also fetches the provider / OpenCode / Pi model lists the form
// offers; answers that arrive after the chat (or the panel) changed are
// dropped by `_generation`.
import QtQuick
import "../ProviderService.js" as ProviderService
import "../ProviderCheck.js" as ProviderCheck
import "../ProviderVariants.js" as ProviderVariants
import "../Variants.js" as Variants
import "EffectiveConfig.js" as EffectiveConfig

QtObject {
    id: draft

    // main.qml (or a stand-in): sessions, messages, plasmoid, OpenCode/Pi fetchers.
    property var rootRef: null
    // True while the panel is shown; lists are only refreshed then.
    property bool active: false

    property string sessionId: ""
    property string sessionTitle: ""
    // The chat's mode, "provider" | "opencode" | "pi": fixed when the chat was started.
    property string mode: "provider"
    // This chat has its own model settings (provider, model, agent). Only
    // meaningful while "Let chats have their own model settings" is on.
    property bool ownModel: false
    property string provider: ""              // "" = the global default provider
    property string model: ""
    property string ocAgent: ""
    property string ocProvider: ""
    property string ocModel: ""
    // The model's variant (reasoning level) id, per mode: direct and OpenCode here, Pi's is piThinking.
    property string variant: ""
    property string ocVariant: ""
    // The direct model's variants, as the provider reports them (refreshVariants).
    property var directVariants: []
    // Set by the quick picker: the model the variants are looked up for, when it
    // is not the draft's own (the main settings can win over the chat's).
    property string variantProvider: ""
    property string variantModel: ""
    property string ocCwd: ""
    property bool systemEnabled: true
    property string system: ""
    property int responseLength: 0
    // Settings → Personality for this chat (direct mode; session property personalityOff).
    property bool personalityOn: true
    property string piProvider: ""
    property string piModel: ""
    property string piThinking: ""
    property var piProviders: []
    property var piModelMap: ({})
    property var modelCandidates: []
    // The variants of the model this draft would use, in the chat's mode: from
    // the source's own report only (empty = no picker), see Variants.js.
    readonly property var variantList: {
        var cfg = _config || {};
        if (mode === "opencode")
            return Variants.fromOpenCodeNames(((rootRef && rootRef.openCodeVariants) || {})[(_clean(ocProvider, defaultProviderText) || cfg.openCodeProvider || "") + "/" + (_clean(ocModel, defaultModelText) || cfg.openCodeModel || "")]);
        if (mode === "pi")
            return Variants.fromPi(EffectiveConfig.PI_THINKING_LEVELS, ((rootRef && rootRef.piThinkingModels) || {})[piProvider + "/" + piModel] === true);
        return directVariants;
    }
    readonly property string variantId: mode === "opencode" ? ocVariant : mode === "pi" ? piThinking : variant
    // Replaces XMLHttpRequest in tests.
    property var xhrFactory: null
    property bool busy: false
    property string status: ""
    property bool statusError: false
    property bool dirty: false
    // True while load() runs: the form fills its inputs without marking edits.
    property bool loading: false

    readonly property string defaultAgentText: i18n("(default agent)")
    readonly property string defaultProviderText: i18n("(default provider)")
    readonly property string defaultModelText: i18n("(default model)")

    property int _generation: 0

    // The form should put the draft's values into its inputs / the lists changed.
    signal loaded()
    signal listsChanged()

    readonly property var _config: rootRef && rootRef.plasmoid ? rootRef.plasmoid.configuration : null

    // The settings page's "Let chats have their own model settings".
    readonly property bool perChat: _config ? _config.perChatModelSettings === true : false
    // The panel edits provider/model/agent only when chats may have their own and this one does.
    readonly property bool modelEditable: perChat && ownModel

    function _session() {
        var list = rootRef ? (rootRef.sessions || []) : [];
        for (var i = 0; i < list.length; i++) {
            if (list[i].value === sessionId)
                return list[i];
        }
        return null;
    }

    function _get(key, fallback) {
        if (rootRef && typeof rootRef.getSessionProperty === "function")
            return rootRef.getSessionProperty(sessionId, key, fallback);
        return fallback;
    }

    function _setStatus(text, isError) {
        status = text;
        statusError = isError === true;
    }

    function _clean(value, sentinel) {
        var text = String(value || "").trim();
        return text === sentinel ? "" : text;
    }

    function setVariantId(id) {
        if (mode === "opencode") ocVariant = id;
        else if (mode === "pi") piThinking = id;
        else variant = id;
    }

    // Sets the direct / OpenCode model. A model the user typed or chose
    // (`byUser`) starts without a variant, since variants belong to a model.
    function changeModel(value, byUser) {
        var current = mode === "opencode" ? ocModel : model;
        if (byUser && value !== current)
            setVariantId("");
        if (mode === "opencode") ocModel = value;
        else model = value;
        if (mode === "provider" && byUser)
            refreshVariants();
    }

    function invalidate() {
        _generation += 1;
        busy = false;
        _setStatus("", false);
    }

    function _requestToken() {
        busy = true;
        return {"generation": _generation, "sessionId": sessionId};
    }

    function _current(token) {
        return token && token.generation === _generation && token.sessionId === sessionId;
    }

    // [{text, value}]: "Default · X" first, then the providers with keys.
    function providerEntries() {
        var global = _config ? (_config.provider || "openai") : "openai";
        var result = [{"text": i18n("Default · %1", ProviderService.getProviderDisplayName(global, _config)), "value": ""}];
        var configured = ProviderService.getConfiguredProviders(_config);
        var walletKeys = rootRef ? (rootRef.walletApiKeys || {}) : {};
        var supported = ProviderService.getSupportedProviders(_config);
        for (var w = 0; w < supported.length; w++) {
            if (walletKeys[supported[w]] && configured.indexOf(supported[w]) < 0)
                configured.push(supported[w]);
        }
        configured = ProviderService.sortDefaultFirst(configured, global);
        for (var i = 0; i < configured.length; i++)
            result.push({"text": ProviderService.getProviderDisplayName(configured[i], _config), "value": configured[i]});
        return result;
    }

    // Names of the entries (strings or objects) with `sentinel` first.
    function names(items, sentinel) {
        var result = [sentinel];
        for (var i = 0; i < (items || []).length; i++) {
            var item = items[i];
            var value = typeof item === "string" ? item : (item && (item.value || item.id || item.name || item.text));
            if (value && result.indexOf(value) < 0)
                result.push(value);
        }
        return result;
    }

    function load(id) {
        invalidate();
        sessionId = id || "";
        var source = EffectiveConfig.chatMode(_session());
        sessionTitle = rootRef && rootRef.currentSessionTitle ? rootRef.currentSessionTitle : i18n("Current Chat");
        ownModel = EffectiveConfig.hasOwnModelSettings(_session());
        mode = source;
        provider = _get("chatProvider", "");
        model = _get("chatModel", "");
        ocAgent = _get("openCodeAgent", "");
        ocProvider = _get("openCodeProvider", "");
        ocModel = _get("openCodeModel", "");
        variant = _get("chatVariant", "");
        ocVariant = _get("openCodeVariant", "");
        directVariants = [];
        ocCwd = _get("openCodeWorkspaceCwd", "");
        // A chat without instructions has the box unchecked; it is only on for real text.
        system = _get("chatSystemPrompt", "");
        systemEnabled = system.trim() !== "" && _get("chatSystemPromptEnabled", true) !== false;
        responseLength = _get("responseLength", 0) || 0;
        personalityOn = _get("personalityOff", false) !== true;
        // Pi chats used to keep their provider and model in chatProvider/chatModel.
        var configuration = _config || {};
        piProvider = _get("piProvider", source === "pi" ? _get("chatProvider", "") : "") || configuration.piProvider || "";
        piModel = _get("piModel", source === "pi" ? _get("chatModel", "") : "") || configuration.piModel || "";
        piThinking = _get("piThinking", "");
        piProviders = rootRef ? (rootRef.piProviderCandidates || []) : [];
        piModelMap = rootRef ? (rootRef.piProviderModelMap || {}) : {};
        modelCandidates = [];
        dirty = false;
        loading = true;
        loaded();
        loading = false;
        // Always refresh the active source when opening. The old UI skipped
        // refreshes when a per-chat override was empty or keys loaded late.
        Qt.callLater(function() {
            if (sessionId !== id || !active || !modelEditable)
                return;
            if (mode === "opencode")
                refreshOpenCode(function() { refreshAgents(); });
            else if (mode === "pi")
                refreshPi();
            else
                refreshModels(false);
        });
    }

    function reset() {
        load(sessionId);
    }

    // Turns this chat's own model settings on or off (the lists are fetched when on).
    function setOwnModel(on) {
        if (ownModel === on)
            return;
        ownModel = on;
        dirty = true;
        if (!on)
            return;
        invalidate();
        if (mode === "opencode")
            refreshOpenCode(function() { refreshAgents(); });
        else if (mode === "pi")
            refreshPi();
        else
            refreshModels(false);
    }

    // The provider the model list is for: the chosen one, else the global default.
    function effectiveProvider() {
        return provider || (_config ? (_config.provider || "openai") : "openai");
    }

    function refreshModels(showStatus) {
        if (busy || !rootRef || !rootRef.plasmoid)
            return;
        var id = effectiveProvider();
        var token = _requestToken();
        if (showStatus)
            _setStatus(i18n("Refreshing models…"));
        // The provider's live list, chat models only (no embeddings, safety
        // models and the like); the field still takes any typed id.
        ProviderCheck.listModels(ProviderService.getProviderConfig(id, _config), (rootRef.walletApiKeys || {})[id] || "",
            function(result) {
                if (!_current(token)) return;
                busy = false;
                if (!result.ok) {
                    _setStatus(i18n("Model refresh failed: %1", result.error === "rejected" ? i18n("the provider rejected the API key (HTTP %1)", result.status)
                               : result.error === "http" ? i18n("HTTP %1", result.status) : i18n("could not reach the provider")), true);
                    return;
                }
                modelCandidates = result.chat;
                if (!model && modelCandidates.length > 0)
                    model = modelCandidates[0];
                ProviderVariants.remember(ProviderService.getProviderConfig(id, _config), result);
                refreshVariants();
                listsChanged();
                _setStatus(modelCandidates.length > 0 ? i18np("Loaded 1 model", "Loaded %1 models", modelCandidates.length) : i18n("No models returned"));
            }, {"xhrFactory": xhrFactory});
    }

    // Looks up the variants of the direct model (`modelId`, else the draft's, else
    // the provider's configured one) in `providerId` (else the draft's), from the
    // provider's own report: the cached model list, or the list fetched now. A
    // chosen variant the model does not offer is dropped.
    function refreshVariants(providerId, modelId) {
        var id = providerId || variantProvider || effectiveProvider();
        var cfg = ProviderService.getProviderConfig(id, _config);
        var chosen = modelId || variantModel || model.trim() || cfg.model;
        var token = {"generation": _generation, "sessionId": sessionId};
        ProviderVariants.forModel(cfg, ((rootRef && rootRef.walletApiKeys) || {})[id] || "", chosen, ProviderCheck.listModels, function(list) {
            if (!_current(token) || (mode !== "provider"))
                return;
            directVariants = list;
            if (list.length > 0 && variant !== "" && !Variants.isValid(list, variant))
                variant = "";
        }, {"xhrFactory": xhrFactory});
    }

    function refreshAgents() {
        if (busy || !rootRef || typeof rootRef.fetchOpenCodeAgents !== "function")
            return;
        var token = _requestToken();
        _setStatus(i18n("Refreshing agents…"));
        rootRef.fetchOpenCodeAgents(function() {
            if (!_current(token)) return;
            busy = false;
            listsChanged();
            var count = (rootRef.openCodeAgentsList || []).length;
            _setStatus(count > 0 ? i18np("Loaded 1 agent", "Loaded %1 agents", count) : i18n("No agents reported by OpenCode"));
        });
    }

    function refreshOpenCode(done) {
        if (busy || !rootRef || typeof rootRef.fetchOpenCodeProvidersAndModels !== "function") {
            if (done) done();
            return;
        }
        var token = _requestToken();
        _setStatus(i18n("Refreshing OpenCode providers…"));
        rootRef.fetchOpenCodeProvidersAndModels(function() {
            if (!_current(token)) return;
            busy = false;
            listsChanged();
            var providerCount = (rootRef.openCodeProvidersList || []).length;
            var modelCount = (rootRef.openCodeModelsList || []).length;
            _setStatus(providerCount > 0 ? i18nc("%1 is a number of providers, %2 a number of models", "Loaded %1, %2", i18np("%1 provider", "%1 providers", providerCount), i18np("%1 model", "%1 models", modelCount))
                                         : i18n("OpenCode returned no providers or models"));
            if (done) done();
        });
    }

    function refreshPi() {
        if (busy || !rootRef || typeof rootRef.fetchPiModels !== "function")
            return;
        var token = _requestToken();
        _setStatus(i18n("Refreshing Pi providers and models…"));
        rootRef.fetchPiModels(function(providers, modelMap) {
            if (!_current(token)) return;
            piProviders = providers || [];
            piModelMap = modelMap || {};
            busy = false;
            _setStatus(piProviders.length > 0 ? i18np("Loaded 1 Pi provider", "Loaded %1 Pi providers", piProviders.length) : i18n("Pi returned no providers"));
        });
    }

    // Writes the draft to the chat in one update. Returns false if there is no chat.
    function save() {
        invalidate();
        if (!rootRef || !sessionId)
            return false;
        var agent = ocAgent.trim();
        var ocProviderName = ocProvider.trim();
        var ocModelName = ocModel.trim();
        if (agent === defaultAgentText) agent = "";
        if (ocProviderName === defaultProviderText) ocProviderName = "";
        if (ocModelName === defaultModelText) ocModelName = "";
        var globalProvider = _config ? (_config.provider || "openai") : "openai";
        var overrides = {
            "openCodeWorkspaceCwd": ocCwd.trim(),
            "responseLength": responseLength
        };
        // Instructions: only real text is saved. An empty (or blank) box saves no
        // text, and turns nothing on or off: the chat sends no instructions.
        if (system.trim() !== "" || _get("chatSystemPrompt", "") !== "") {
            var hasText = system.trim() !== "";
            overrides.chatSystemPrompt = hasText ? system : "";
            overrides.chatSystemPromptEnabled = hasText ? systemEnabled : _get("chatSystemPromptEnabled", true) !== false;
        }
        if (!personalityOn || _get("personalityOff", false) === true)
            overrides.personalityOff = !personalityOn;
        // The model settings are only written while they are editable; otherwise
        // what the chat has stays as it is (kept, not used). The mode (source)
        // is never written: a chat keeps the mode it was started in.
        if (perChat)
            overrides.ownModel = ownModel;
        if (modelEditable) {
            overrides.chatProvider = mode === "pi" ? provider : (effectiveProvider() === globalProvider ? "" : effectiveProvider());
            overrides.chatModel = mode === "pi" ? model : model.trim();
            overrides.chatVariant = variant;
            overrides.openCodeVariant = ocVariant;
            overrides.piProvider = piProvider;
            overrides.piModel = piModel;
            overrides.piThinking = piThinking;
            overrides.openCodeAgent = agent;
            overrides.openCodeProvider = ocProviderName;
            overrides.openCodeModel = ocModelName;
        }
        var was = rootRef.effectiveConfig(sessionId).model;
        if (typeof rootRef.setSessionOverrides === "function")
            rootRef.setSessionOverrides(sessionId, overrides);
        else if (typeof rootRef.setSessionProperty === "function") {
            for (var key in overrides)
                rootRef.setSessionProperty(sessionId, key, overrides[key]);
        }
        if (rootRef.composerRef) rootRef.composerRef.noteModelSwitch(sessionId, was, rootRef.effectiveConfig(sessionId).model);
        dirty = false;
        return true;
    }
}
