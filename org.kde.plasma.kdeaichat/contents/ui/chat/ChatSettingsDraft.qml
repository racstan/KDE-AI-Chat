// The editable copy of one chat's own settings behind the Chat info panel
// (ChatSettingsDialog.qml). load() reads the chat's overrides, the form
// edits the properties, save() writes them back in one go through
// rootRef.setSessionOverrides, and nothing else in the widget changes until
// then. It also fetches the provider / OpenCode / Pi model lists the form
// offers; answers that arrive after the chat (or the panel) changed are
// dropped by `_generation`.
import QtQuick
import "../ProviderService.js" as ProviderService

QtObject {
    id: draft

    // main.qml (or a stand-in): sessions, messages, plasmoid, OpenCode/Pi fetchers.
    property var rootRef: null
    // True while the panel is shown; lists are only refreshed then.
    property bool active: false

    property string sessionId: ""
    property string sessionTitle: ""
    property string mode: "provider"          // "provider" | "opencode" | "pi"
    property string provider: ""              // "" = the global default provider
    property string model: ""
    property string ocAgent: ""
    property string ocProvider: ""
    property string ocModel: ""
    property string ocCwd: ""
    property bool systemEnabled: true
    property string system: ""
    property int responseLength: 0
    property string piProvider: ""
    property string piModel: ""
    property string piThinking: ""
    property var piProviders: []
    property var piModelMap: ({})
    property var modelCandidates: []
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

    function _get(key, fallback) {
        if (rootRef && typeof rootRef.getSessionProperty === "function")
            return rootRef.getSessionProperty(sessionId, key, fallback);
        return fallback;
    }

    function _setStatus(text, isError) {
        status = text;
        statusError = isError === true;
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
        var source = _get("source", "");
        if (!source)
            source = rootRef && rootRef.openCodeMode ? "opencode" : "provider";
        sessionTitle = rootRef && rootRef.currentSessionTitle ? rootRef.currentSessionTitle : i18n("Current Chat");
        mode = source;
        provider = _get("chatProvider", "");
        model = _get("chatModel", "");
        ocAgent = _get("openCodeAgent", "");
        ocProvider = _get("openCodeProvider", "");
        ocModel = _get("openCodeModel", "");
        ocCwd = _get("openCodeWorkspaceCwd", "");
        systemEnabled = _get("chatSystemPromptEnabled", true);
        system = _get("chatSystemPrompt", "");
        responseLength = _get("responseLength", 0) || 0;
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
            if (sessionId !== id || !active)
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

    function setMode(newMode) {
        if (mode === newMode)
            return;
        invalidate();
        mode = newMode;
        modelCandidates = [];
        dirty = true;
        listsChanged();
        if (newMode === "opencode")
            refreshOpenCode(function() { refreshAgents(); });
        else if (newMode === "pi")
            refreshPi();
        else if (newMode === "provider")
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
        ProviderService.fetchModels(ProviderService.getProviderConfig(id, _config), (rootRef.walletApiKeys || {})[id] || "",
            function(models) {
                if (!_current(token)) return;
                busy = false;
                modelCandidates = models || [];
                if (!model && modelCandidates.length > 0)
                    model = modelCandidates[0];
                listsChanged();
                _setStatus(modelCandidates.length > 0 ? i18np("Loaded 1 model", "Loaded %1 models", modelCandidates.length) : i18n("No models returned"));
            },
            function(errorText) {
                if (!_current(token)) return;
                busy = false;
                _setStatus(i18n("Model refresh failed: %1", errorText), true);
            });
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
            _setStatus(providerCount > 0 ? i18n("Loaded %1 providers, %2 models", providerCount, modelCount)
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
            "source": mode,
            "chatProvider": mode === "pi" ? provider : (effectiveProvider() === globalProvider ? "" : effectiveProvider()),
            "chatModel": mode === "pi" ? model : model.trim(),
            "piProvider": piProvider,
            "piModel": piModel,
            "piThinking": piThinking,
            "openCodeAgent": agent,
            "openCodeProvider": ocProviderName,
            "openCodeModel": ocModelName,
            "openCodeWorkspaceCwd": ocCwd.trim(),
            "chatSystemPromptEnabled": systemEnabled,
            "chatSystemPrompt": system,
            "responseLength": responseLength
        };
        if (typeof rootRef.setSessionOverrides === "function")
            rootRef.setSessionOverrides(sessionId, overrides);
        else if (typeof rootRef.setSessionProperty === "function") {
            for (var key in overrides)
                rootRef.setSessionProperty(sessionId, key, overrides[key]);
        }
        dirty = false;
        return true;
    }
}
