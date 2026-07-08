import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtCore
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus

KCM.SimpleKCM {
    id: page

    //* Ctrl+scroll zoom for the settings form (0.75–1.5).
    property real configZoom: 1
    property alias cfg_appearanceMode: appearanceModeCombo.currentIndex
    readonly property bool kwalletModeActive: true
    property alias cfg_provider: providerBox.currentValue
    property alias cfg_baseUrl: baseUrlField.text
    property alias cfg_apiKey: apiKeyField.text
    property alias cfg_model: modelField.text
    property alias cfg_anthropicApiKey: anthropicApiKeyField.text
    property alias cfg_anthropicModel: anthropicModelField.text
    property alias cfg_groqBaseUrl: groqBaseUrlField.text
    property alias cfg_groqApiKey: groqApiKeyField.text
    property alias cfg_groqModel: groqModelField.text
    property alias cfg_deepSeekBaseUrl: deepSeekBaseUrlField.text
    property alias cfg_deepSeekApiKey: deepSeekApiKeyField.text
    property alias cfg_deepSeekModel: deepSeekModelField.text
    property alias cfg_miniMaxBaseUrl: miniMaxBaseUrlField.text
    property alias cfg_miniMaxApiKey: miniMaxApiKeyField.text
    property alias cfg_miniMaxModel: miniMaxModelField.text
    property alias cfg_fireworksBaseUrl: fireworksBaseUrlField.text
    property alias cfg_fireworksApiKey: fireworksApiKeyField.text
    property alias cfg_fireworksModel: fireworksModelField.text
    property alias cfg_googleBaseUrl: googleBaseUrlField.text
    property alias cfg_googleApiKey: googleApiKeyField.text
    property alias cfg_googleModel: googleModelField.text
    property alias cfg_openRouterBaseUrl: openRouterBaseUrlField.text
    property alias cfg_openRouterApiKey: openRouterApiKeyField.text
    property alias cfg_openRouterModel: openRouterModelField.text
    property alias cfg_mistralBaseUrl: mistralBaseUrlField.text
    property alias cfg_mistralApiKey: mistralApiKeyField.text
    property alias cfg_mistralModel: mistralModelField.text
    property alias cfg_cloudflareBaseUrl: cloudflareBaseUrlField.text
    property alias cfg_cloudflareApiKey: cloudflareApiKeyField.text
    property alias cfg_cloudflareModel: cloudflareModelField.text
    property alias cfg_nvidiaBaseUrl: nvidiaBaseUrlField.text
    property alias cfg_nvidiaApiKey: nvidiaApiKeyField.text
    property alias cfg_nvidiaModel: nvidiaModelField.text
    property alias cfg_huggingFaceBaseUrl: huggingFaceBaseUrlField.text
    property alias cfg_huggingFaceApiKey: huggingFaceApiKeyField.text
    property alias cfg_huggingFaceModel: huggingFaceModelField.text
    property alias cfg_xaiBaseUrl: xaiBaseUrlField.text
    property alias cfg_xaiApiKey: xaiApiKeyField.text
    property alias cfg_xaiModel: xaiModelField.text
    property alias cfg_lmStudioBaseUrl: lmStudioBaseUrlField.text
    property alias cfg_lmStudioModel: lmStudioModelField.text
    property alias cfg_localBaseUrl: localBaseUrlField.text
    property alias cfg_localModel: localModelField.text
    property alias cfg_ollamaBaseUrl: ollamaBaseUrlField.text
    property alias cfg_ollamaModel: ollamaModelField.text
    property alias cfg_litellmBaseUrl: litellmBaseUrlField.text
    property alias cfg_litellmApiKey: litellmApiKeyField.text
    property alias cfg_litellmModel: litellmModelField.text
    property alias cfg_useOpenCode: openCodeToggle.checked
    property alias cfg_playNotificationSound: playSoundToggle.checked
    property alias cfg_openCodeUrl: openCodeUrlField.text
    property alias cfg_openCodeModel: openCodeModelValueField.text
    property alias cfg_openCodeProvider: openCodeProviderValueField.text
    property alias cfg_openCodeStartCommand: openCodeStartCommandField.text
    property alias cfg_openCodeStopCommand: openCodeStopCommandField.text
    property string discoveryStatus: ""
    property var pendingOps: ({
    })
    // Guard to prevent premature writes during KCM initialization (cfg_ aliases
    // are populated after the combo's onCurrentIndexChanged fires).
    property bool pageReady: false
    property bool keyringBusy: false
    property bool openCodeBusy: utilityDs.connectedSources.filter(function(sourceName) {
        return sourceName.indexOf("#opencode-") >= 0;
    }).length > 0
    property var providerModelCandidates: []
    property var openCodeProviderCandidates: []
    property var openCodeModelCandidates: []
    property var openCodeProviderModelMap: ({
    })
    property bool memRefreshing: false
    property int memOpenCode: 0
    property int memStt: 0
    property int memTts: 0
    property string providerModelSearch: ""
    property string openCodeModelSearch: ""
    property var filteredProviderModels: []
    property var filteredOpenCodeModels: []
    readonly property string walletFolderName: "KaiChat"
    readonly property string walletAppId: "org.kde.plasma.kdeaichat"

    function updateFilteredProviderModels(searchText) {
        var search = (searchText || "").toLowerCase();
        if (search === "") {
            filteredProviderModels = providerModelCandidates;
        } else {
            var filtered = [];
            for (var i = 0; i < providerModelCandidates.length; i++) {
                if (providerModelCandidates[i].toLowerCase().indexOf(search) >= 0)
                    filtered.push(providerModelCandidates[i]);

            }
            filteredProviderModels = filtered;
        }
    }

    function updateFilteredOpenCodeModels(searchText) {
        var search = (searchText || "").toLowerCase();
        if (search === "") {
            filteredOpenCodeModels = openCodeModelCandidates;
        } else {
            var filtered = [];
            for (var i = 0; i < openCodeModelCandidates.length; i++) {
                if (openCodeModelCandidates[i].toLowerCase().indexOf(search) >= 0)
                    filtered.push(openCodeModelCandidates[i]);

            }
            filteredOpenCodeModels = filtered;
        }
    }

    function effectiveWalletName() {
        return "kdewallet";
    }

    function walletCall(member, args, resolve, reject) {
        var reply = DBus.SessionBus.asyncCall({
            service: "org.kde.kwalletd6",
            path: "/modules/kwalletd6",
            iface: "org.kde.KWallet",
            member: member,
            arguments: args
        });
        reply.finished.connect(function() {
            if (reply.isError) {
                if (reject) reject(reply.error);
                else console.warn("KDE AI Chat: wallet DBus error:", member, reply.error);
            } else {
                var val = reply.value;
                if (val !== null && val !== undefined && typeof val === 'object' && val.hasOwnProperty("value")) val = val.value;
                if (resolve) resolve(val);
            }
        });
    }

    function setActiveProviderModelValue(value) {
        currentProviderConfig().modelField.text = value || "";
    }

    function activeProviderModelValue() {
        return currentProviderConfig().modelField.text || "";
    }

    // Shell script builders removed in favor of native DBus calls.

    function shellEscape(s) {
        return (s || "").replace(/'/g, "'\\''");
    }

    function quoteForShell(s) {
        return "'" + shellEscape(s) + "'";
    }

    function getHelperPath() {
        var urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        var path = decodeURIComponent(urlStr);
        if (path.indexOf("/") === 0 && path.indexOf("/contents/ui/") !== -1)
            return path;
        var localShare = StandardPaths.writableLocation(StandardPaths.GenericDataLocation);
        return localShare + "/plasma/plasmoids/org.kde.plasma.kdeaichat/contents/ui/kde_ai_helper.py";
    }

    function copyToClipboard(textValue) {
        var text = textValue || "";
        var cmd = "sh -lc \"if command -v wl-copy >/dev/null 2>&1; then printf '%s' '" + shellEscape(text) + "' | wl-copy; " + "elif command -v xclip >/dev/null 2>&1; then printf '%s' '" + shellEscape(text) + "' | xclip -selection clipboard; " + "else echo 'Clipboard tool missing: install wl-clipboard or xclip' 1>&2; exit 1; fi\"";
        utilityDs.connectSource(cmd + " #clipboard-copy");
    }

    function providerEnabled(providerId) {
        return !openCodeToggle.checked && providerBox.currentValue === providerId;
    }

    function providerNeedsApiKey(providerId) {
        return providerId !== "local" && providerId !== "lmstudio" && providerId !== "ollama" && providerId !== "litellm";
    }

    function providerHasConfiguredKey(providerId) {
        if (providerId === "anthropic")
            return (anthropicApiKeyField.text || "").trim() !== "";

        if (providerId === "groq")
            return (groqApiKeyField.text || "").trim() !== "";

        if (providerId === "deepseek")
            return (deepSeekApiKeyField.text || "").trim() !== "";

        if (providerId === "minimax")
            return (miniMaxApiKeyField.text || "").trim() !== "";

        if (providerId === "fireworks")
            return (fireworksApiKeyField.text || "").trim() !== "";

        if (providerId === "google")
            return (googleApiKeyField.text || "").trim() !== "";

        if (providerId === "openrouter")
            return (openRouterApiKeyField.text || "").trim() !== "";

        if (providerId === "mistral")
            return (mistralApiKeyField.text || "").trim() !== "";

        if (providerId === "cloudflare")
            return (cloudflareApiKeyField.text || "").trim() !== "";

        if (providerId === "nvidia")
            return (nvidiaApiKeyField.text || "").trim() !== "";

        if (providerId === "huggingface")
            return (huggingFaceApiKeyField.text || "").trim() !== "";

        if (providerId === "xai")
            return (xaiApiKeyField.text || "").trim() !== "";

        if (providerId === "litellm")
            return (litellmApiKeyField.text || "").trim() !== "";

        if (providerId === "openai")
            return (apiKeyField.text || "").trim() !== "";

        return true;
    }

    function refreshIfActiveProvider(providerId) {
        if (providerBox.currentValue === providerId)
            refreshCurrentProviderModels();

    }

    function providerModelVisible(providerId) {
        return providerEnabled(providerId) && (!providerNeedsApiKey(providerId) || providerHasConfiguredKey(providerId));
    }

    function providerNeedsKeyHintVisible(providerId) {
        return providerEnabled(providerId) && providerNeedsApiKey(providerId) && !providerHasConfiguredKey(providerId);
    }

    function currentProviderDisplayName() {
        return providerBox.currentText || "Provider";
    }

    function currentProviderConfig() {
        var p = providerBox.currentValue || "openai";
        if (p === "anthropic")
            return {
                "id": p,
                "type": "anthropic",
                "baseUrl": "https://api.anthropic.com/v1",
                "apiKey": anthropicApiKeyField.text,
                "modelField": anthropicModelField
            };

        if (p === "local")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": localBaseUrlField.text,
                "apiKey": "",
                "modelField": localModelField
            };

        if (p === "groq")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": groqBaseUrlField.text,
                "apiKey": groqApiKeyField.text,
                "modelField": groqModelField
            };

        if (p === "deepseek")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": deepSeekBaseUrlField.text,
                "apiKey": deepSeekApiKeyField.text,
                "modelField": deepSeekModelField
            };

        if (p === "minimax")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": miniMaxBaseUrlField.text,
                "apiKey": miniMaxApiKeyField.text,
                "modelField": miniMaxModelField
            };

        if (p === "fireworks")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": fireworksBaseUrlField.text,
                "apiKey": fireworksApiKeyField.text,
                "modelField": fireworksModelField
            };

        if (p === "google")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": googleBaseUrlField.text,
                "apiKey": googleApiKeyField.text,
                "modelField": googleModelField
            };

        if (p === "openrouter")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": openRouterBaseUrlField.text,
                "apiKey": openRouterApiKeyField.text,
                "modelField": openRouterModelField
            };

        if (p === "mistral")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": mistralBaseUrlField.text,
                "apiKey": mistralApiKeyField.text,
                "modelField": mistralModelField
            };

        if (p === "cloudflare")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": cloudflareBaseUrlField.text,
                "apiKey": cloudflareApiKeyField.text,
                "modelField": cloudflareModelField
            };

        if (p === "nvidia")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": nvidiaBaseUrlField.text,
                "apiKey": nvidiaApiKeyField.text,
                "modelField": nvidiaModelField
            };

        if (p === "huggingface")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": huggingFaceBaseUrlField.text,
                "apiKey": huggingFaceApiKeyField.text,
                "modelField": huggingFaceModelField
            };

        if (p === "xai")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": xaiBaseUrlField.text,
                "apiKey": xaiApiKeyField.text,
                "modelField": xaiModelField
            };

        if (p === "lmstudio")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": lmStudioBaseUrlField.text,
                "apiKey": "",
                "modelField": lmStudioModelField
            };

        if (p === "ollama")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": ollamaBaseUrlField.text,
                "apiKey": "",
                "modelField": ollamaModelField
            };

        if (p === "litellm")
            return {
                "id": p,
                "type": "openai-compat",
                "baseUrl": litellmBaseUrlField.text,
                "apiKey": litellmApiKeyField.text,
                "modelField": litellmModelField
            };

        return {
            "id": "openai",
            "type": "openai-compat",
            "baseUrl": baseUrlField.text,
            "apiKey": apiKeyField.text,
            "modelField": modelField
        };
    }

    function makeOpenAiModelsUrl(baseUrl) {
        return (baseUrl || "").replace(/\/$/, "") + "/models";
    }

    function parseModelIds(responseObj) {
        function pushId(v) {
            if (!v)
                return ;

            if (ids.indexOf(v) < 0)
                ids.push(v);

        }

        var ids = [];
        if (Array.isArray(responseObj)) {
            for (var i = 0; i < responseObj.length; i++) {
                if (typeof responseObj[i] === "string")
                    pushId(responseObj[i]);
                else if (responseObj[i] && responseObj[i].id)
                    pushId(responseObj[i].id);
                else if (responseObj[i] && responseObj[i].name)
                    pushId(responseObj[i].name);
            }
        } else if (responseObj && Array.isArray(responseObj.data)) {
            for (var j = 0; j < responseObj.data.length; j++) {
                if (responseObj.data[j] && responseObj.data[j].id)
                    pushId(responseObj.data[j].id);
                else if (responseObj.data[j] && responseObj.data[j].name)
                    pushId(responseObj.data[j].name);
            }
        } else if (responseObj && Array.isArray(responseObj.models)) {
            for (var k = 0; k < responseObj.models.length; k++) {
                if (typeof responseObj.models[k] === "string")
                    pushId(responseObj.models[k]);
                else if (responseObj.models[k] && responseObj.models[k].id)
                    pushId(responseObj.models[k].id);
                else if (responseObj.models[k] && responseObj.models[k].name)
                    pushId(responseObj.models[k].name);
            }
        }
        return ids;
    }

    function parseProviderIds(responseObj) {
        function pushId(v) {
            if (!v)
                return ;

            if (ids.indexOf(v) < 0)
                ids.push(v);

        }

        var ids = [];
        if (Array.isArray(responseObj)) {
            for (var i = 0; i < responseObj.length; i++) {
                if (typeof responseObj[i] === "string")
                    pushId(responseObj[i]);
                else if (responseObj[i] && responseObj[i].id)
                    pushId(responseObj[i].id);
                else if (responseObj[i] && responseObj[i].name)
                    pushId(responseObj[i].name);
                else if (responseObj[i] && responseObj[i].provider)
                    pushId(responseObj[i].provider);
            }
        } else if (responseObj && Array.isArray(responseObj.providers)) {
            for (var j = 0; j < responseObj.providers.length; j++) {
                if (typeof responseObj.providers[j] === "string")
                    pushId(responseObj.providers[j]);
                else if (responseObj.providers[j] && responseObj.providers[j].id)
                    pushId(responseObj.providers[j].id);
                else if (responseObj.providers[j] && responseObj.providers[j].name)
                    pushId(responseObj.providers[j].name);
            }
        } else if (responseObj && Array.isArray(responseObj.data)) {
            for (var k = 0; k < responseObj.data.length; k++) {
                if (responseObj.data[k] && responseObj.data[k].provider)
                    pushId(responseObj.data[k].provider);

            }
        }
        return ids;
    }

    function requestJson(url, headers, onSuccess, onError) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        for (var h in headers) {
            if (Object.prototype.hasOwnProperty.call(headers, h) && headers[h])
                xhr.setRequestHeader(h, headers[h]);

        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    onSuccess(JSON.parse(xhr.responseText));
                } catch (e) {
                    onError("Invalid JSON from " + url);
                }
            } else {
                onError("HTTP " + xhr.status + " from " + url);
            }
        };
        xhr.onerror = function() {
            onError("Network error while requesting " + url);
        };
        xhr.send();
    }

    function refreshCurrentProviderModels() {
        var cfg = currentProviderConfig();
        var headers = {
        };
        if (providerNeedsApiKey(cfg.id) && (!cfg.apiKey || cfg.apiKey.trim() === "")) {
            providerModelCandidates = [];
            providerModelSearch = "";
            updateFilteredProviderModels("");
            discoveryStatus = "API key is missing for " + currentProviderDisplayName() + ". Add key first, then refresh models.";
            return ;
        }
        if (cfg.apiKey)
            headers["Authorization"] = "Bearer " + cfg.apiKey;

        if (cfg.type === "anthropic") {
            headers["x-api-key"] = cfg.apiKey;
            headers["anthropic-version"] = "2023-06-01";
            requestJson("https://api.anthropic.com/v1/models", headers, function(obj) {
                var ids = parseModelIds(obj);
                providerModelCandidates = ids;
                providerModelSearch = "";
                updateFilteredProviderModels("");
                discoveryStatus = ids.length > 0 ? ("Loaded " + ids.length + " models for " + currentProviderDisplayName() + ".") : "No models returned for this provider/API key.";
            }, function(err) {
                providerModelCandidates = [];
                providerModelSearch = "";
                updateFilteredProviderModels("");
                discoveryStatus = err;
            });
            return ;
        }
        requestJson(makeOpenAiModelsUrl(cfg.baseUrl), headers, function(obj) {
            var ids = parseModelIds(obj);
            providerModelCandidates = ids;
            providerModelSearch = "";
            updateFilteredProviderModels("");
            discoveryStatus = ids.length > 0 ? ("Loaded " + ids.length + " models for " + currentProviderDisplayName() + ".") : "No models returned for this provider/API key.";
        }, function(err) {
            providerModelCandidates = [];
            providerModelSearch = "";
            updateFilteredProviderModels("");
            discoveryStatus = err;
        });
    }

    function applyDetectedModelToActiveProvider(modelId) {
        var cfg = currentProviderConfig();
        cfg.modelField.text = modelId || "";
    }

    function activeOpenCodeProvider() {
        return openCodeProviderValueField.text || "";
    }

    function setOpenCodeProviderValue(v) {
        openCodeProviderValueField.text = v || "";
    }

    function setOpenCodeModelValue(v) {
        openCodeModelValueField.text = v || "";
    }

    function openCodeServerRoot(baseUrl) {
        var value = (baseUrl || "").replace(/\/$/, "");
        if (value.slice(-3) === "/v1")
            return value.slice(0, -3);

        return value;
    }

    function parseOpenCodeProviderModels(providerObj) {
        function pushId(v) {
            if (!v)
                return ;

            if (ids.indexOf(v) < 0)
                ids.push(v);

        }

        var ids = [];
        if (!providerObj || !providerObj.models)
            return ids;

        if (Array.isArray(providerObj.models)) {
            for (var i = 0; i < providerObj.models.length; i++) {
                if (typeof providerObj.models[i] === "string")
                    pushId(providerObj.models[i]);
                else if (providerObj.models[i] && providerObj.models[i].id)
                    pushId(providerObj.models[i].id);
            }
            return ids;
        }
        for (var modelId in providerObj.models) {
            if (!Object.prototype.hasOwnProperty.call(providerObj.models, modelId))
                continue;

            pushId(providerObj.models[modelId].id || modelId);
        }
        return ids;
    }

    function syncOpenCodeProviderSelection(providerId, preferredModel) {
        var selectedProvider = providerId || "";
        var candidateModels = openCodeProviderModelMap[selectedProvider] || [];
        var chosenModel = preferredModel || openCodeModelValueField.text || "";
        if (candidateModels.indexOf(chosenModel) < 0)
            chosenModel = candidateModels.length > 0 ? candidateModels[0] : "";

        setOpenCodeProviderValue(selectedProvider);
        openCodeModelCandidates = candidateModels;
        openCodeModelSearch = "";
        updateFilteredOpenCodeModels("");
        setOpenCodeModelValue(chosenModel);
        if (openCodeProvidersCombo) {
            var pidx = openCodeProviderCandidates.indexOf(selectedProvider);
            if (pidx >= 0)
                openCodeProvidersCombo.currentIndex = pidx;

        }
        if (openCodeModelsCombo) {
            var midx = candidateModels.indexOf(chosenModel);
            if (midx >= 0)
                openCodeModelsCombo.currentIndex = midx;

        }
    }

    function refreshOpenCodeDiscovery() {
        probeOpenCodeProviders(openCodeUrlField.text);
    }

    function probeOpenCodeProviders(baseUrl) {
        var url = openCodeServerRoot(baseUrl) + "/config/providers";
        discoveryStatus = "Checking OpenCode server...";
        requestJson(url, {
        }, function(obj) {
            var providers = (obj && obj.providers) || [];
            var ids = [];
            var defaults = (obj && obj.default) || {
            };
            var modelsByProvider = {
            };
            for (var i = 0; i < providers.length; i++) {
                var provider = providers[i];
                var providerId = provider && provider.id ? provider.id : (provider && provider.name ? provider.name : "");
                if (!providerId)
                    continue;

                if (ids.indexOf(providerId) < 0)
                    ids.push(providerId);

                modelsByProvider[providerId] = parseOpenCodeProviderModels(provider);
            }
            openCodeProviderCandidates = ids;
            openCodeProviderModelMap = modelsByProvider;
            if (ids.length === 0) {
                openCodeModelCandidates = [];
                openCodeModelSearch = "";
                updateFilteredOpenCodeModels("");
                setOpenCodeProviderValue("");
                setOpenCodeModelValue("");
                discoveryStatus = "OpenCode server is reachable, but it returned no configured providers.";
                return ;
            }
            var selectedProvider = activeOpenCodeProvider();
            if (ids.indexOf(selectedProvider) < 0)
                selectedProvider = ids[0];

            var rememberedModel = openCodeModelValueField.text || "";
            var fallbackModel = defaults[selectedProvider] || "";
            syncOpenCodeProviderSelection(selectedProvider, rememberedModel || fallbackModel);
            discoveryStatus = "OpenCode server reachable. Loaded " + ids.length + " providers from /config/providers.";
        }, function(err) {
            openCodeProviderCandidates = [];
            openCodeProviderModelMap = ({
            });
            openCodeModelCandidates = [];
            openCodeModelSearch = "";
            updateFilteredOpenCodeModels("");
            setOpenCodeProviderValue("");
            setOpenCodeModelValue("");
            discoveryStatus = "OpenCode server check failed: " + err;
        });
    }

    function probeOpenCodeModels(baseUrl, providerId) {
        var selectedProvider = providerId || activeOpenCodeProvider();
        if (!selectedProvider) {
            openCodeModelCandidates = [];
            openCodeModelSearch = "";
            updateFilteredOpenCodeModels("");
            discoveryStatus = "Select an OpenCode provider first.";
            return ;
        }
        syncOpenCodeProviderSelection(selectedProvider, openCodeModelValueField.text);
        discoveryStatus = openCodeModelCandidates.length > 0 ? ("Loaded " + openCodeModelCandidates.length + " models for OpenCode provider " + selectedProvider + ".") : ("OpenCode provider " + selectedProvider + " has no models listed by /config/providers.");
    }

    function kwalletStore(targetId, value, isBulk) {
        if (!value || value.trim() === "")
            return;

        var walletName = effectiveWalletName();
        var keyName = "kai-chat-" + targetId + "-api-key";
        keyringBusy = true;
        
        walletCall("wallets", [], function(wallets) {
            if (wallets.indexOf(walletName) === -1) { keyringBusy = false; return; }
            walletCall("open", [walletName, new DBus.int64(0), walletAppId], function(handle) {
                if (handle < 0) { keyringBusy = false; return; }
                walletCall("hasFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function(hasFolder) {
                    if (!hasFolder) {
                        walletCall("createFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function() {
                            walletCall("writePassword", [new DBus.int32(handle), walletFolderName, keyName, value, walletAppId], function() {
                                walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                                keyringBusy = false;
                                if (!isBulk) keyringStatus = "Saved key for " + targetId + " to KWallet.";
                            });
                        });
                    } else {
                        walletCall("writePassword", [new DBus.int32(handle), walletFolderName, keyName, value, walletAppId], function() {
                            walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                            keyringBusy = false;
                            if (!isBulk) keyringStatus = "Saved key for " + targetId + " to KWallet.";
                        });
                    }
                });
            });
        });
    }

    function saveKey(targetId, value) {
        var val = (value || "").trim();
        kwalletStore(targetId, val, false);
    }

    function kwalletLoad(targetId, isBulk) {
        var walletName = effectiveWalletName();
        var keyName = "kai-chat-" + targetId + "-api-key";
        keyringBusy = true;
        
        walletCall("wallets", [], function(wallets) {
            if (wallets.indexOf(walletName) === -1) { keyringBusy = false; return; }
            walletCall("open", [walletName, new DBus.int64(0), walletAppId], function(handle) {
                if (handle < 0) { keyringBusy = false; return; }
                walletCall("hasFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function(hasFolder) {
                    if (!hasFolder) {
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                        keyringBusy = false;
                        return;
                    }
                    walletCall("hasEntry", [new DBus.int32(handle), walletFolderName, keyName, walletAppId], function(hasEntry) {
                        if (hasEntry) {
                            walletCall("readPassword", [new DBus.int32(handle), walletFolderName, keyName, walletAppId], function(secret) {
                                applyLoadedKey(targetId, secret);
                                walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                                keyringBusy = false;
                                if (!isBulk) keyringStatus = "Loaded key for " + targetId + " from KWallet.";
                            });
                        } else {
                            walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                            keyringBusy = false;
                            if (!isBulk) keyringStatus = "No saved key for " + targetId + " in KWallet.";
                        }
                    });
                });
            });
        });
    }

    function applyLoadedKey(targetId, secretValue) {
        var normalized = (secretValue || "").trim();
        var lower = normalized.toLowerCase();
        if (normalized === "" || normalized.indexOf("__KAI_") === 0)
            return ;

        var before = apiKeyForTarget(targetId);
        if (targetId === "openai")
            apiKeyField.text = normalized;
        else if (targetId === "anthropic")
            anthropicApiKeyField.text = normalized;
        else if (targetId === "groq")
            groqApiKeyField.text = normalized;
        else if (targetId === "deepseek")
            deepSeekApiKeyField.text = normalized;
        else if (targetId === "minimax")
            miniMaxApiKeyField.text = normalized;
        else if (targetId === "fireworks")
            fireworksApiKeyField.text = normalized;
        else if (targetId === "google")
            googleApiKeyField.text = normalized;
        else if (targetId === "openrouter")
            openRouterApiKeyField.text = normalized;
        else if (targetId === "mistral")
            mistralApiKeyField.text = normalized;
        else if (targetId === "cloudflare")
            cloudflareApiKeyField.text = normalized;
        else if (targetId === "nvidia")
            nvidiaApiKeyField.text = normalized;
        else if (targetId === "huggingface")
            huggingFaceApiKeyField.text = normalized;
        else if (targetId === "xai")
            xaiApiKeyField.text = normalized;
        else if (targetId === "litellm")
            litellmApiKeyField.text = normalized;
        var after = apiKeyForTarget(targetId);
        if (before !== after && providerBox.currentValue === targetId)
            refreshCurrentProviderModels();

    }

    function keyTargetIds() {
        return ["openai", "anthropic", "groq", "deepseek", "minimax", "fireworks", "google", "openrouter", "mistral", "cloudflare", "nvidia", "huggingface", "xai", "litellm"];
    }

    function apiKeyForTarget(targetId) {
        if (targetId === "openai")
            return apiKeyField.text;

        if (targetId === "anthropic")
            return anthropicApiKeyField.text;

        if (targetId === "groq")
            return groqApiKeyField.text;

        if (targetId === "deepseek")
            return deepSeekApiKeyField.text;

        if (targetId === "minimax")
            return miniMaxApiKeyField.text;

        if (targetId === "fireworks")
            return fireworksApiKeyField.text;

        if (targetId === "google")
            return googleApiKeyField.text;

        if (targetId === "openrouter")
            return openRouterApiKeyField.text;

        if (targetId === "mistral")
            return mistralApiKeyField.text;

        if (targetId === "cloudflare")
            return cloudflareApiKeyField.text;

        if (targetId === "nvidia")
            return nvidiaApiKeyField.text;

        if (targetId === "huggingface")
            return huggingFaceApiKeyField.text;

        if (targetId === "xai")
            return xaiApiKeyField.text;

        if (targetId === "litellm")
            return litellmApiKeyField.text;

        return "";
    }

    function kwalletLoadAll() {
        var walletName = effectiveWalletName();
        keyringStatus = "Refreshing API keys from KWallet...";
        keyringBusy = true;
        
        walletCall("wallets", [], function(wallets) {
            if (wallets.indexOf(walletName) === -1) { keyringBusy = false; return; }
            walletCall("open", [walletName, new DBus.int64(0), walletAppId], function(handle) {
                if (handle < 0) { keyringBusy = false; return; }
                walletCall("hasFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function(hasFolder) {
                    if (!hasFolder) {
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                        keyringBusy = false;
                        keyringStatus = "KWallet storage not initialized yet.";
                        return;
                    }
                    var targets = keyTargetIds();
                    var idx = 0;
                    function readNext() {
                        if (idx >= targets.length) {
                            walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                            keyringBusy = false;
                            keyringStatus = "Loaded API keys from KWallet.";
                            return;
                        }
                        var targetId = targets[idx++];
                        var key = "kai-chat-" + targetId + "-api-key";
                        walletCall("hasEntry", [new DBus.int32(handle), walletFolderName, key, walletAppId], function(hasEntry) {
                            if (hasEntry) {
                                walletCall("readPassword", [new DBus.int32(handle), walletFolderName, key, walletAppId], function(secret) {
                                    applyLoadedKey(targetId, secret);
                                    readNext();
                                });
                            } else {
                                readNext();
                            }
                        });
                    }
                    readNext();
                });
            });
        });
    }

    function kwalletStoreAll() {
        var walletName = effectiveWalletName();
        var targetsToSave = [];
        var ids = keyTargetIds();
        for (var i = 0; i < ids.length; i++) {
            var value = (apiKeyForTarget(ids[i]) || "").trim();
            if (value !== "") targetsToSave.push({id: ids[i], val: value});
        }
        
        if (targetsToSave.length === 0) {
            keyringStatus = "No API keys to sync.";
            return;
        }

        keyringBusy = true;
        walletCall("wallets", [], function(wallets) {
            if (wallets.indexOf(walletName) === -1) { keyringBusy = false; return; }
            walletCall("open", [walletName, new DBus.int64(0), walletAppId], function(handle) {
                if (handle < 0) { keyringBusy = false; return; }
                walletCall("hasFolder", [new DBus.int32(handle), walletFolderName, walletAppId], function(hasFolder) {
                    var proceedToSave = function() {
                        var idx = 0;
                        function saveNext() {
                            if (idx >= targetsToSave.length) {
                                walletCall("close", [new DBus.int32(handle), new DBus.bool(false), walletAppId]);
                                keyringBusy = false;
                                keyringStatus = "Synced " + targetsToSave.length + " API keys to KWallet.";
                                return;
                            }
                            var t = targetsToSave[idx++];
                            var key = "kai-chat-" + t.id + "-api-key";
                            walletCall("writePassword", [new DBus.int32(handle), walletFolderName, key, t.val, walletAppId], function() {
                                saveNext();
                            });
                        }
                        saveNext();
                    };

                    if (!hasFolder) {
                        walletCall("createFolder", [new DBus.int32(handle), walletFolderName, walletAppId], proceedToSave);
                    } else {
                        proceedToSave();
                    }
                });
            });
        });
    }

    function clearAllApiKeyFields() {
        apiKeyField.text = "";
        anthropicApiKeyField.text = "";
        groqApiKeyField.text = "";
        deepSeekApiKeyField.text = "";
        miniMaxApiKeyField.text = "";
        fireworksApiKeyField.text = "";
        googleApiKeyField.text = "";
        openRouterApiKeyField.text = "";
        mistralApiKeyField.text = "";
        cloudflareApiKeyField.text = "";
        nvidiaApiKeyField.text = "";
        huggingFaceApiKeyField.text = "";
        xaiApiKeyField.text = "";
        litellmApiKeyField.text = "";
    }



    function saveGeneralSettingsOnly() {
        // App name saved via ConfigOther.qml
        plasmoid.configuration.appearanceMode = appearanceModeCombo.currentIndex;

        plasmoid.configuration.provider = providerBox.currentValue;
        plasmoid.configuration.baseUrl = baseUrlField.text;
        plasmoid.configuration.model = modelField.text;
        plasmoid.configuration.anthropicModel = anthropicModelField.text;
        plasmoid.configuration.groqBaseUrl = groqBaseUrlField.text;
        plasmoid.configuration.groqModel = groqModelField.text;
        plasmoid.configuration.deepSeekBaseUrl = deepSeekBaseUrlField.text;
        plasmoid.configuration.deepSeekModel = deepSeekModelField.text;
        plasmoid.configuration.miniMaxBaseUrl = miniMaxBaseUrlField.text;
        plasmoid.configuration.miniMaxModel = miniMaxModelField.text;
        plasmoid.configuration.fireworksBaseUrl = fireworksBaseUrlField.text;
        plasmoid.configuration.fireworksModel = fireworksModelField.text;
        plasmoid.configuration.googleBaseUrl = googleBaseUrlField.text;
        plasmoid.configuration.googleModel = googleModelField.text;
        plasmoid.configuration.openRouterBaseUrl = openRouterBaseUrlField.text;
        plasmoid.configuration.openRouterModel = openRouterModelField.text;
        plasmoid.configuration.mistralBaseUrl = mistralBaseUrlField.text;
        plasmoid.configuration.mistralModel = mistralModelField.text;
        plasmoid.configuration.cloudflareBaseUrl = cloudflareBaseUrlField.text;
        plasmoid.configuration.cloudflareModel = cloudflareModelField.text;
        plasmoid.configuration.nvidiaBaseUrl = nvidiaBaseUrlField.text;
        plasmoid.configuration.nvidiaModel = nvidiaModelField.text;
        plasmoid.configuration.huggingFaceBaseUrl = huggingFaceBaseUrlField.text;
        plasmoid.configuration.huggingFaceModel = huggingFaceModelField.text;
        plasmoid.configuration.xaiBaseUrl = xaiBaseUrlField.text;
        plasmoid.configuration.xaiModel = xaiModelField.text;
        plasmoid.configuration.lmStudioBaseUrl = lmStudioBaseUrlField.text;
        plasmoid.configuration.lmStudioModel = lmStudioModelField.text;
        plasmoid.configuration.localBaseUrl = localBaseUrlField.text;
        plasmoid.configuration.localModel = localModelField.text;
        plasmoid.configuration.ollamaBaseUrl = ollamaBaseUrlField.text;
        plasmoid.configuration.ollamaModel = ollamaModelField.text;
        plasmoid.configuration.litellmBaseUrl = litellmBaseUrlField.text;
        plasmoid.configuration.litellmModel = litellmModelField.text;
        plasmoid.configuration.useOpenCode = openCodeToggle.checked;
        plasmoid.configuration.playNotificationSound = playSoundToggle.checked;
        plasmoid.configuration.openCodeUrl = openCodeUrlField.text;
        plasmoid.configuration.openCodeModel = openCodeModelValueField.text;
        plasmoid.configuration.openCodeProvider = openCodeProviderValueField.text;
        plasmoid.configuration.openCodeStartCommand = openCodeStartCommandField.text;
        plasmoid.configuration.openCodeStopCommand = openCodeStopCommandField.text;
        plasmoid.configuration.kwalletName = walletNameField.text;
    }

    function cancelKeyringOps() {
        var running = keyringDs.connectedSources;
        for (var i = 0; i < running.length; i++) keyringDs.disconnectSource(running[i])
        var utilityRunning = utilityDs.connectedSources;
        for (var j = 0; j < utilityRunning.length; j++) {
            if (utilityRunning[j].indexOf("#kwallet-") >= 0)
                utilityDs.disconnectSource(utilityRunning[j]);

        }
        pendingOps = ({
        });
    }

    function resetToDefaults() {
        // App name reset handled in reset helper
        providerBox.currentIndex = 0;
        baseUrlField.text = "https://api.openai.com/v1";
        apiKeyField.text = "";
        modelField.text = "gpt-4o-mini";
        anthropicApiKeyField.text = "";
        anthropicModelField.text = "claude-3-5-sonnet-latest";
        groqBaseUrlField.text = "https://api.groq.com/openai/v1";
        groqApiKeyField.text = "";
        groqModelField.text = "llama-3.3-70b-versatile";
        deepSeekBaseUrlField.text = "https://api.deepseek.com";
        deepSeekApiKeyField.text = "";
        deepSeekModelField.text = "deepseek-v4-pro";
        miniMaxBaseUrlField.text = "https://api.minimax.io/v1";
        miniMaxApiKeyField.text = "";
        miniMaxModelField.text = "MiniMax-M2.7";
        fireworksBaseUrlField.text = "https://api.fireworks.ai/inference/v1";
        fireworksApiKeyField.text = "";
        fireworksModelField.text = "accounts/fireworks/models/llama-v3p3-70b-instruct";
        googleBaseUrlField.text = "https://generativelanguage.googleapis.com/v1beta/openai/";
        googleApiKeyField.text = "";
        googleModelField.text = "gemini-3-flash-preview";
        openRouterBaseUrlField.text = "https://openrouter.ai/api/v1";
        openRouterApiKeyField.text = "";
        openRouterModelField.text = "openai/gpt-4o-mini";
        mistralBaseUrlField.text = "https://api.mistral.ai/v1";
        mistralApiKeyField.text = "";
        mistralModelField.text = "mistral-small-latest";
        cloudflareBaseUrlField.text = "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1";
        cloudflareApiKeyField.text = "";
        cloudflareModelField.text = "@cf/meta/llama-3.1-8b-instruct";
        nvidiaBaseUrlField.text = "https://integrate.api.nvidia.com/v1";
        nvidiaApiKeyField.text = "";
        nvidiaModelField.text = "meta/llama-3.1-70b-instruct";
        huggingFaceBaseUrlField.text = "https://router.huggingface.co/v1";
        huggingFaceApiKeyField.text = "";
        huggingFaceModelField.text = "openai/gpt-oss-120b:groq";
        xaiBaseUrlField.text = "https://api.x.ai/v1";
        xaiApiKeyField.text = "";
        xaiModelField.text = "grok-2-latest";
        lmStudioBaseUrlField.text = "http://localhost:1234/v1";
        lmStudioModelField.text = "";
        localBaseUrlField.text = "http://localhost:11434/v1";
        localModelField.text = "llama3.2";
        ollamaBaseUrlField.text = "http://localhost:11434/v1";
        ollamaModelField.text = "llama3.2";
        litellmBaseUrlField.text = "http://localhost:4000/v1";
        litellmApiKeyField.text = "";
        litellmModelField.text = "";
        openCodeToggle.checked = false;
        openCodeUrlField.text = "http://127.0.0.1:4096/v1";
        openCodeProviderValueField.text = "";
        openCodeModelValueField.text = "";
        openCodeStartCommandField.text = "nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 & echo OpenCode start command launched.";
        openCodeStopCommandField.text = "pkill -f opencode >/dev/null 2>&1 && echo OpenCode stop command launched. || echo No OpenCode process matched.";
        systemPromptArea.text = "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.";
        providerModelCandidates = [];
        openCodeProviderCandidates = [];
        openCodeModelCandidates = [];
        openCodeProviderModelMap = ({
        });
        discoveryStatus = "Settings reset to defaults.";
    }

    horizontalScrollBarPolicy: configZoom > 1.01 ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff
    Component.onCompleted: {
        if (plasmoid.configuration.appearanceMode === 3 || plasmoid.configuration.appearanceMode > 2)
            plasmoid.configuration.appearanceMode = 0;

        if (openCodeToggle.checked)
            refreshOpenCodeDiscovery();

        // Refresh memory usage
        var cmd = "python3 " + quoteForShell(getHelperPath()) + " get_memory_usage";
        utilityDs.connectSource(cmd + " #mem-usage-" + Date.now());

        // Mark page as fully initialised
        pageReady = true;
    }
    Component.onDestruction: {
        saveGeneralSettingsOnly();
        // Sync the current fields to KWallet before closing.
        kwalletStoreAll();
    }

    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        onWheel: function(event) {
            var step = event.angleDelta.y / 800;
            page.configZoom = Math.max(0.75, Math.min(1.5, page.configZoom + step));
            event.accepted = true;
        }
    }

    P5Support.DataSource {
    // keyringDs removed in favor of native DBus calls.
    }

    P5Support.DataSource {
        id: utilityDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var out = (data["stdout"] || "").trim();
            var err = (data["stderr"] || "").trim();
            if (sourceName.indexOf("kwallet-wallet-list") >= 0) {
                if (out.indexOf("__NO_QDBUS__") >= 0) {
                    availableWalletNames = [];
                    keyringStatus = "qdbus6 / qdbus is missing! KWallet requires Qt DBus tools. Please install 'qt6-tools' (or 'qttools' depending on your Linux distribution) to enable secure KWallet credentials storage.";
                    disconnectSource(sourceName);
                    return;
                }
                availableWalletNames = out === "" ? [] : out.split(/\n+/).filter(function(name) {
                    return name.trim() !== "";
                });
                maybeAdoptDetectedWalletName();
                if (availableWalletNames.length === 0)
                    keyringStatus = "No wallets detected yet. Create one or open KWallet first.";
                else
                    Qt.callLater(page.kwalletLoadAll);
            } else if (sourceName.indexOf("kwallet-refresh-all") >= 0) {
                console.log("[KAI-DEBUG] kwallet-refresh-all stdout:", out);
                console.log("[KAI-DEBUG] kwallet-refresh-all stderr:", err);
                if (out.indexOf("__KAI_BULK__:") < 0) {
                    console.log("[KAI-DEBUG] kwallet-refresh-all not finished yet, waiting...");
                    return ;
                }
                if (out === "__KAI_BULK__:NO_WALLET") {
                    keyringStatus = "Configured wallet not found. Pick a detected wallet and retry.";
                } else if (out === "__KAI_BULK__:OPEN_FAILED") {
                    keyringStatus = "KWallet did not open the selected wallet.";
                } else if (out === "__KAI_BULK__:NO_FOLDER") {
                    keyringStatus = "Wallet opened, but KDE AI Chat storage is not initialized yet.";
                } else {
                    var lines = out === "" ? [] : out.split(/\n+/);
                    var loaded = 0;
                    for (var i = 0; i < lines.length; i++) {
                        if (lines[i].indexOf("__KAI_SECRET__:") !== 0)
                            continue;

                        var rest = lines[i].slice("__KAI_SECRET__:".length);
                        var sep = rest.indexOf(":");
                        if (sep <= 0)
                            continue;

                        var targetId = rest.slice(0, sep);
                        var secretValue = rest.slice(sep + 1);
                        applyLoadedKey(targetId, secretValue);
                        if ((secretValue || "").trim() !== "")
                            loaded++;

                    }
                    keyringStatus = "KWallet refresh finished. Loaded " + loaded + " key(s).";
                }
            } else if (sourceName.indexOf("kwallet-create") >= 0) {
                if (out === "__KAI_INIT__:READY")
                    keyringStatus = "Wallet connection is ready for KDE AI Chat storage.";
                else if (out === "__KAI_INIT__:CREATED")
                    keyringStatus = "KDE AI Chat storage folder was created in the wallet.";
                else if (out === "__KAI_INIT__:OPEN_FAILED")
                    keyringStatus = "KWallet did not open the selected wallet. If the wallet does not exist, KDE should prompt to create it.";
                else
                    keyringStatus = out !== "" ? out : (err !== "" ? err : "Wallet initialization finished.");
                Qt.callLater(page.detectWallets);
            } else if (sourceName.indexOf("kwallet-status-check") >= 0) {
                if (out.indexOf("__KAI_STATUS__:NO_WALLET:") === 0) {
                    var walletList = out.slice("__KAI_STATUS__:NO_WALLET:".length).replace(/\n/g, ", ");
                    keyringStatus = walletList !== "" ? ("Configured wallet not found. Available wallets: " + walletList) : "Configured wallet not found.";
                } else if (out === "__KAI_STATUS__:OPEN_FAILED")
                    keyringStatus = "KWallet could not open the selected wallet.";
                else if (out === "__KAI_STATUS__:NO_FOLDER")
                    keyringStatus = "Wallet is open, but KDE AI Chat storage is not initialized yet. Click Create wallet.";
                else if (out === "__KAI_STATUS__:READY")
                    keyringStatus = "Wallet ready for KDE AI Chat.";
                else
                    keyringStatus = out !== "" ? out : (err !== "" ? err : "Wallet check finished.");
            } else if (sourceName.indexOf("mem-usage-") >= 0) {
                page.memRefreshing = false;
                if (out !== "") {
                    try {
                        var memData = JSON.parse(out);
                        page.memOpenCode = memData.opencode || 0;
                        page.memStt = memData.stt || 0;
                        page.memTts = memData.tts || 0;
                    } catch (e) {
                        console.warn("Failed to parse memory data:", e);
                    }
                }
            } else {
                discoveryStatus = out !== "" ? out : (err !== "" ? err : "Command finished.");
            }
            disconnectSource(sourceName);
        }
    }

    Item {
        id: zoomHost

        implicitWidth: 0
        implicitHeight: Math.ceil(formLayout.implicitHeight * page.configZoom)
        clip: true

        Kirigami.FormLayout {
            id: formLayout

            readonly property real boundedWidth: {
                var hostW = zoomHost.width;
                if (hostW <= 0)
                    return Kirigami.Units.gridUnit * 28;

                return Math.min(hostW / page.configZoom, Kirigami.Units.gridUnit * 32);
            }
            //* FormLayout treats preferredWidth 0 as "unset" and uses implicitWidth — cap fields to the form instead.
            readonly property real fieldMaxWidth: Math.max(Kirigami.Units.gridUnit * 12, boundedWidth)

            x: 0
            clip: true
            scale: page.configZoom
            transformOrigin: Item.TopLeft
            //* Single column: wideMode uses implicitWidth for grid width and centers it, which clips labels in narrow config dialogs.
            wideMode: false
            width: boundedWidth

            ColumnLayout {
                Kirigami.FormData.label: "Appearance:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.ComboBox {
                    id: appearanceModeCombo

                    Layout.fillWidth: true
                    Layout.maximumWidth: formLayout.fieldMaxWidth
                    model: ["Follow system", "Light mode", "Dark mode"]
                }

                Rectangle {
                    visible: showInteractiveGuidesToggle.checked
                    Layout.fillWidth: true
                    Layout.maximumWidth: formLayout.fieldMaxWidth
                    implicitHeight: appearanceGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                    radius: 5
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    border.width: 1

                    RowLayout {
                        id: appearanceGuideLayout
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.gridUnit * 0.6
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "help-hint"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                            Layout.alignment: Qt.AlignTop
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                            color: Kirigami.Theme.textColor
                            text: "<b>Appearance Modes:</b><br>" +
                                  "Light mode and Dark mode pin the widget to a bright or dark UI.<br>" +
                                  "<b>Follow system</b> uses your Plasma colors and updates with the desktop theme.<br><br>" +
                                  "<i>Note: These themes apply only to the chat widget popup, not this settings page.</i>"
                        }
                    }
                }

            }

            QQC2.CheckBox {
                id: playSoundToggle

                Kirigami.FormData.label: "Notification sound:"
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Play sound when AI finishes a response"
            }

            QQC2.CheckBox {
                id: showInteractiveGuidesToggle

                Kirigami.FormData.label: i18n("Interactive Guides:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                checked: plasmoid.configuration.showInteractiveGuides !== undefined ? plasmoid.configuration.showInteractiveGuides : true
                text: checked ? i18n("Guides visible — showing setup instructions") : i18n("Guides hidden")
                onToggled: {
                    plasmoid.configuration.showInteractiveGuides = checked;
                }
            }

            Rectangle {
                visible: showInteractiveGuidesToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                implicitHeight: generalGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                radius: 5
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                border.width: 1

                RowLayout {
                    id: generalGuideLayout
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.6
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "help-hint"
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                        Layout.alignment: Qt.AlignTop
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.RichText
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                        color: Kirigami.Theme.textColor
                        text: "<b>General Setup Guide</b><br><br>" +
                              "<b>Cloud Providers:</b> Select a provider (like OpenAI or Anthropic), enter your API key, and press <b>Save</b>. Then click <b>Refresh</b> to load available models.<br><br>" +
                              "<b>Local Providers:</b> Services like Ollama or LM Studio operate completely offline and do not require API keys.<br><br>" +
                              "<b>OpenCode Mode:</b> Use this only when you are connecting to your personal OpenCode local server."
                    }
                }
            }

            QQC2.CheckBox {
                id: openCodeToggle

                Kirigami.FormData.label: "OpenCode mode:"
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enable OpenCode mode"
                onCheckedChanged: {
                    if (checked)
                        refreshOpenCodeDiscovery();

                }
            }

            Kirigami.Separator {
                visible: !openCodeToggle.checked
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: "Provider"
            }

            QQC2.ComboBox {
                id: providerBox

                visible: !openCodeToggle.checked
                Kirigami.FormData.label: "Default provider:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                textRole: "text"
                valueRole: "value"
                model: [{
                    "value": "openai",
                    "text": "OpenAI"
                }, {
                    "value": "anthropic",
                    "text": "Anthropic"
                }, {
                    "value": "groq",
                    "text": "Groq"
                }, {
                    "value": "deepseek",
                    "text": "DeepSeek"
                }, {
                    "value": "minimax",
                    "text": "MiniMax"
                }, {
                    "value": "fireworks",
                    "text": "Fireworks AI"
                }, {
                    "value": "google",
                    "text": "Google Gemini"
                }, {
                    "value": "openrouter",
                    "text": "OpenRouter"
                }, {
                    "value": "mistral",
                    "text": "Mistral"
                }, {
                    "value": "cloudflare",
                    "text": "Cloudflare Workers AI"
                }, {
                    "value": "nvidia",
                    "text": "NVIDIA NIM"
                }, {
                    "value": "huggingface",
                    "text": "Hugging Face Router"
                }, {
                    "value": "xai",
                    "text": "xAI (Grok)"
                }, {
                    "value": "lmstudio",
                    "text": "LM Studio"
                }, {
                    "value": "local",
                    "text": "Local (OpenAI-compatible)"
                }, {
                    "value": "ollama",
                    "text": "Ollama"
                }, {
                    "value": "litellm",
                    "text": "LiteLLM Proxy"
                }]
                onActivated: {
                    providerModelCandidates = [];
                    discoveryStatus = "";
                }
            }

            QQC2.Button {
                visible: !openCodeToggle.checked
                Kirigami.FormData.label: "Model discovery:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Refresh models for active provider"
                enabled: !providerNeedsApiKey(providerBox.currentValue || "openai") || providerHasConfiguredKey(providerBox.currentValue || "openai")
                onClicked: refreshCurrentProviderModels()
            }

            QQC2.BusyIndicator {
                visible: !openCodeToggle.checked && openCodeBusy
                running: visible
                Kirigami.FormData.label: "Loading:"
            }

            QQC2.ComboBox {
                id: providerModelsCombo

                function syncText() {
                    var val = activeProviderModelValue();
                    var idx = providerModelCandidates.indexOf(val);
                    if (idx >= 0) {
                        currentIndex = idx;
                    } else {
                        currentIndex = -1;
                        editText = val;
                    }
                }

                visible: !openCodeToggle.checked && providerModelVisible(providerBox.currentValue || "openai")
                Kirigami.FormData.label: "Model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                editable: true
                model: providerModelCandidates
                Component.onCompleted: {
                    syncText();
                }
                onModelChanged: {
                    syncText();
                }
                onEditTextChanged: {
                    if (activeFocus)
                        applyDetectedModelToActiveProvider(editText);

                }
                onActivated: {
                    applyDetectedModelToActiveProvider(currentText);
                    editText = currentText;
                }
            }

            QQC2.Label {
                visible: discoveryStatus !== ""
                Kirigami.FormData.label: "Status:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: discoveryStatus
                wrapMode: Text.Wrap
                opacity: 0.8
            }

            Kirigami.Separator {
                visible: openCodeToggle.checked
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: "OpenCode"
            }

            QQC2.TextField {
                id: openCodeUrlField

                visible: openCodeToggle.checked
                Kirigami.FormData.label: "OpenCode URL:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://127.0.0.1:4096/v1"
            }

            Flow {
                visible: openCodeToggle.checked
                Kirigami.FormData.label: "OpenCode server:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: "Start server"
                    enabled: !openCodeBusy
                    onClicked: {
                        discoveryStatus = "Running OpenCode start command...";
                        var cmd = "sh -lc '" + shellEscape(openCodeStartCommandField.text || "nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 & echo OpenCode start command launched.") + "'";
                        utilityDs.connectSource(cmd + " #opencode-start");
                    }
                }

                QQC2.Button {
                    text: "Check server"
                    enabled: !openCodeBusy
                    onClicked: probeOpenCodeProviders(openCodeUrlField.text)
                }

                QQC2.Button {
                    text: "Refresh"
                    enabled: !openCodeBusy
                    onClicked: refreshOpenCodeDiscovery()
                }

                QQC2.Button {
                    text: "Kill server"
                    enabled: !openCodeBusy
                    onClicked: {
                        discoveryStatus = "Running OpenCode stop command...";
                        var cmd = "sh -lc '" + shellEscape(openCodeStopCommandField.text || "pkill -f opencode") + "'";
                        utilityDs.connectSource(cmd + " #opencode-stop");
                    }
                }

            }

            QQC2.BusyIndicator {
                visible: openCodeToggle.checked && openCodeBusy
                running: visible
                Kirigami.FormData.label: "Loading:"
            }

            QQC2.ComboBox {
                id: openCodeProvidersCombo

                visible: openCodeToggle.checked && openCodeProviderCandidates.length > 0
                Kirigami.FormData.label: "Providers:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                model: openCodeProviderCandidates
                onActivated: {
                    setOpenCodeProviderValue(currentText);
                    probeOpenCodeModels(openCodeUrlField.text, currentText);
                }
            }

            QQC2.Button {
                visible: openCodeToggle.checked
                Kirigami.FormData.label: "OpenCode models:"
                text: "Refresh models"
                onClicked: probeOpenCodeModels(openCodeUrlField.text, activeOpenCodeProvider())
            }

            QQC2.ComboBox {
                id: openCodeModelsCombo

                function syncText() {
                    var val = openCodeModelValueField.text || "";
                    var idx = openCodeModelCandidates.indexOf(val);
                    if (idx >= 0) {
                        currentIndex = idx;
                    } else {
                        currentIndex = -1;
                        editText = val;
                    }
                }

                visible: openCodeToggle.checked
                Kirigami.FormData.label: "Model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                editable: true
                model: openCodeModelCandidates
                Component.onCompleted: {
                    syncText();
                }
                onModelChanged: {
                    syncText();
                }
                onEditTextChanged: {
                    if (activeFocus)
                        setOpenCodeModelValue(editText);

                }
                onActivated: {
                    setOpenCodeModelValue(currentText);
                    editText = currentText;
                }
            }

            QQC2.TextField {
                visible: openCodeToggle.checked && (false)
                Kirigami.FormData.label: filteredOpenCodeModels.length > 0 ? "Custom model:" : "OpenCode model (optional):"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Enter your OpenCode model id"
                text: openCodeModelValueField.text
                onTextChanged: {
                    openCodeModelSearch = text;
                    updateFilteredOpenCodeModels(text);
                    setOpenCodeModelValue(text);
                }
            }

            QQC2.TextField {
                id: openCodeStartCommandField

                visible: false
            }

            QQC2.TextField {
                id: openCodeStopCommandField

                visible: false
            }

            QQC2.TextField {
                id: openCodeProviderValueField

                visible: false
                text: ""
            }

            QQC2.TextField {
                id: openCodeModelValueField

                visible: false
                text: ""
            }

            QQC2.TextField {
                id: walletNameField

                visible: false
                text: "kdeaichatwallet"
            }

            QQC2.TextField {
                id: baseUrlField

                Kirigami.FormData.label: "OpenAI URL:"
                visible: page.providerEnabled("openai")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.openai.com/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "OpenAI key:"
                visible: page.providerEnabled("openai")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: apiKeyField

                    Layout.fillWidth: true
                    Layout.maximumWidth: parent.width - apiKeyShowHide.implicitWidth - parent.spacing
                    echoMode: apiKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("openai", text);
                        page.refreshIfActiveProvider("openai");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: openaiSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("openai", apiKeyField.text);
                        page.refreshIfActiveProvider("openai");
                        saved = true;
                        openaiSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: apiKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("openai")
                Kirigami.FormData.label: "OpenAI model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the OpenAI API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: modelField

                Kirigami.FormData.label: "OpenAI model:"
                visible: page.providerModelVisible("openai") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "gpt-4o-mini"
                text: activeProviderModelValue()
                onTextChanged: setActiveProviderModelValue(text)
            }

            RowLayout {
                Kirigami.FormData.label: "Anthropic key:"
                visible: page.providerEnabled("anthropic")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: anthropicApiKeyField

                    Layout.fillWidth: true
                    echoMode: anthropicKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("anthropic", text);
                        page.refreshIfActiveProvider("anthropic");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: anthropicSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("anthropic", anthropicApiKeyField.text);
                        page.refreshIfActiveProvider("anthropic");
                        saved = true;
                        anthropicSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: anthropicKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("anthropic")
                Kirigami.FormData.label: "Anthropic model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Anthropic API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: anthropicModelField

                Kirigami.FormData.label: "Anthropic model:"
                visible: page.providerModelVisible("anthropic") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "claude-3-5-sonnet-latest"
            }

            QQC2.TextField {
                id: groqBaseUrlField

                Kirigami.FormData.label: "Groq URL:"
                visible: page.providerEnabled("groq")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.groq.com/openai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "Groq key:"
                visible: page.providerEnabled("groq")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: groqApiKeyField

                    Layout.fillWidth: true
                    echoMode: groqKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("groq", text);
                        page.refreshIfActiveProvider("groq");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: groqSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("groq", groqApiKeyField.text);
                        page.refreshIfActiveProvider("groq");
                        saved = true;
                        groqSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: groqKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("groq")
                Kirigami.FormData.label: "Groq model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Groq API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: groqModelField

                Kirigami.FormData.label: "Groq model:"
                visible: page.providerModelVisible("groq") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "llama-3.3-70b-versatile"
            }

            QQC2.TextField {
                id: deepSeekBaseUrlField

                Kirigami.FormData.label: "DeepSeek URL:"
                visible: page.providerEnabled("deepseek")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.deepseek.com"
            }

            RowLayout {
                Kirigami.FormData.label: "DeepSeek key:"
                visible: page.providerEnabled("deepseek")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: deepSeekApiKeyField

                    Layout.fillWidth: true
                    echoMode: deepSeekKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("deepseek", text);
                        page.refreshIfActiveProvider("deepseek");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: deepseekSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("deepseek", deepseekApiKeyField.text);
                        page.refreshIfActiveProvider("deepseek");
                        saved = true;
                        deepseekSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: deepSeekKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("deepseek")
                Kirigami.FormData.label: "DeepSeek model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the DeepSeek API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: deepSeekModelField

                Kirigami.FormData.label: "DeepSeek model:"
                visible: page.providerModelVisible("deepseek") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "deepseek-v4-pro"
            }

            QQC2.TextField {
                id: miniMaxBaseUrlField

                Kirigami.FormData.label: "MiniMax URL:"
                visible: page.providerEnabled("minimax")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.minimax.io/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "MiniMax key:"
                visible: page.providerEnabled("minimax")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: miniMaxApiKeyField

                    Layout.fillWidth: true
                    echoMode: miniMaxKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("minimax", text);
                        page.refreshIfActiveProvider("minimax");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: minimaxSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("minimax", minimaxApiKeyField.text);
                        page.refreshIfActiveProvider("minimax");
                        saved = true;
                        minimaxSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: miniMaxKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("minimax")
                Kirigami.FormData.label: "MiniMax model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the MiniMax API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: miniMaxModelField

                Kirigami.FormData.label: "MiniMax model:"
                visible: page.providerModelVisible("minimax") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "MiniMax-M2.7"
            }

            QQC2.TextField {
                id: fireworksBaseUrlField

                Kirigami.FormData.label: "Fireworks URL:"
                visible: page.providerEnabled("fireworks")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.fireworks.ai/inference/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "Fireworks key:"
                visible: page.providerEnabled("fireworks")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: fireworksApiKeyField

                    Layout.fillWidth: true
                    echoMode: fireworksKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("fireworks", text);
                        page.refreshIfActiveProvider("fireworks");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: fireworksSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("fireworks", fireworksApiKeyField.text);
                        page.refreshIfActiveProvider("fireworks");
                        saved = true;
                        fireworksSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: fireworksKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("fireworks")
                Kirigami.FormData.label: "Fireworks model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Fireworks API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: fireworksModelField

                Kirigami.FormData.label: "Fireworks model:"
                visible: page.providerModelVisible("fireworks") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "accounts/fireworks/models/llama-v3p3-70b-instruct"
            }

            QQC2.TextField {
                id: googleBaseUrlField

                Kirigami.FormData.label: "Google URL:"
                visible: page.providerEnabled("google")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://generativelanguage.googleapis.com/v1beta/openai/"
            }

            RowLayout {
                Kirigami.FormData.label: "Google key:"
                visible: page.providerEnabled("google")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: googleApiKeyField

                    Layout.fillWidth: true
                    echoMode: googleKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("google", text);
                        page.refreshIfActiveProvider("google");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: googleSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("google", googleApiKeyField.text);
                        page.refreshIfActiveProvider("google");
                        saved = true;
                        googleSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: googleKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("google")
                Kirigami.FormData.label: "Google model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Gemini API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: googleModelField

                Kirigami.FormData.label: "Google model:"
                visible: page.providerModelVisible("google") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "gemini-3-flash-preview"
            }

            QQC2.TextField {
                id: openRouterBaseUrlField

                Kirigami.FormData.label: "OpenRouter URL:"
                visible: page.providerEnabled("openrouter")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://openrouter.ai/api/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "OpenRouter key:"
                visible: page.providerEnabled("openrouter")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: openRouterApiKeyField

                    Layout.fillWidth: true
                    echoMode: openRouterKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("openrouter", text);
                        page.refreshIfActiveProvider("openrouter");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: openrouterSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("openrouter", openrouterApiKeyField.text);
                        page.refreshIfActiveProvider("openrouter");
                        saved = true;
                        openrouterSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: openRouterKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("openrouter")
                Kirigami.FormData.label: "OpenRouter model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the OpenRouter API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: openRouterModelField

                Kirigami.FormData.label: "OpenRouter model:"
                visible: page.providerModelVisible("openrouter") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "openai/gpt-4o-mini"
            }

            QQC2.TextField {
                id: mistralBaseUrlField

                Kirigami.FormData.label: "Mistral URL:"
                visible: page.providerEnabled("mistral")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.mistral.ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "Mistral key:"
                visible: page.providerEnabled("mistral")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: mistralApiKeyField

                    Layout.fillWidth: true
                    echoMode: mistralKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("mistral", text);
                        page.refreshIfActiveProvider("mistral");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: mistralSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("mistral", mistralApiKeyField.text);
                        page.refreshIfActiveProvider("mistral");
                        saved = true;
                        mistralSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: mistralKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("mistral")
                Kirigami.FormData.label: "Mistral model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Mistral API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: mistralModelField

                Kirigami.FormData.label: "Mistral model:"
                visible: page.providerModelVisible("mistral") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "mistral-small-latest"
            }

            QQC2.TextField {
                id: cloudflareBaseUrlField

                Kirigami.FormData.label: "Cloudflare URL:"
                visible: page.providerEnabled("cloudflare")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "Cloudflare key:"
                visible: page.providerEnabled("cloudflare")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: cloudflareApiKeyField

                    Layout.fillWidth: true
                    echoMode: cloudflareKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("cloudflare", text);
                        page.refreshIfActiveProvider("cloudflare");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: cloudflareSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("cloudflare", cloudflareApiKeyField.text);
                        page.refreshIfActiveProvider("cloudflare");
                        saved = true;
                        cloudflareSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: cloudflareKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("cloudflare")
                Kirigami.FormData.label: "Cloudflare model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Cloudflare API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: cloudflareModelField

                Kirigami.FormData.label: "Cloudflare model:"
                visible: page.providerModelVisible("cloudflare") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "@cf/meta/llama-3.1-8b-instruct"
            }

            QQC2.TextField {
                id: nvidiaBaseUrlField

                Kirigami.FormData.label: "NVIDIA NIM URL:"
                visible: page.providerEnabled("nvidia")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://integrate.api.nvidia.com/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "NVIDIA NIM key:"
                visible: page.providerEnabled("nvidia")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: nvidiaApiKeyField

                    Layout.fillWidth: true
                    echoMode: nvidiaKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("nvidia", text);
                        page.refreshIfActiveProvider("nvidia");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: nvidiaSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("nvidia", nvidiaApiKeyField.text);
                        page.refreshIfActiveProvider("nvidia");
                        saved = true;
                        nvidiaSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: nvidiaKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("nvidia")
                Kirigami.FormData.label: "NVIDIA NIM model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the NVIDIA NIM API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: nvidiaModelField

                Kirigami.FormData.label: "NVIDIA NIM model:"
                visible: page.providerModelVisible("nvidia") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "meta/llama-3.1-70b-instruct"
            }

            QQC2.TextField {
                id: huggingFaceBaseUrlField

                Kirigami.FormData.label: "HF URL:"
                visible: page.providerEnabled("huggingface")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://router.huggingface.co/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "HF token:"
                visible: page.providerEnabled("huggingface")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: huggingFaceApiKeyField

                    Layout.fillWidth: true
                    echoMode: huggingFaceKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("huggingface", text);
                        page.refreshIfActiveProvider("huggingface");
                    }
                }

                QQC2.Button {
                    id: huggingFaceKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("huggingface")
                Kirigami.FormData.label: "HF model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the Hugging Face token first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: huggingFaceModelField

                Kirigami.FormData.label: "HF model:"
                visible: page.providerModelVisible("huggingface") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "openai/gpt-oss-120b:groq"
            }

            QQC2.TextField {
                id: xaiBaseUrlField

                Kirigami.FormData.label: "xAI URL:"
                visible: page.providerEnabled("xai")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.x.ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "xAI key:"
                visible: page.providerEnabled("xai")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: xaiApiKeyField

                    Layout.fillWidth: true
                    echoMode: xaiKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("xai", text);
                        page.refreshIfActiveProvider("xai");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: xaiSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("xai", xaiApiKeyField.text);
                        page.refreshIfActiveProvider("xai");
                        saved = true;
                        xaiSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: xaiKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("xai")
                Kirigami.FormData.label: "xAI model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the xAI API key first, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: xaiModelField

                Kirigami.FormData.label: "xAI model:"
                visible: page.providerModelVisible("xai") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "grok-2-latest"
            }

            QQC2.TextField {
                id: lmStudioBaseUrlField

                Kirigami.FormData.label: "LM Studio URL:"
                visible: page.providerEnabled("lmstudio")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:1234/v1"
            }

            QQC2.TextField {
                id: lmStudioModelField

                Kirigami.FormData.label: "LM Studio model:"
                visible: page.providerModelVisible("lmstudio") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Load a model in LM Studio, then refresh models"
            }

            QQC2.TextField {
                id: localBaseUrlField

                Kirigami.FormData.label: "Local URL:"
                visible: page.providerEnabled("local")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:11434/v1"
            }

            QQC2.TextField {
                id: localModelField

                Kirigami.FormData.label: "Local model:"
                visible: page.providerModelVisible("local") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "llama3.2"
            }

            QQC2.TextField {
                id: ollamaBaseUrlField

                Kirigami.FormData.label: "Ollama URL:"
                visible: page.providerEnabled("ollama")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:11434/v1"
            }

            QQC2.TextField {
                id: ollamaModelField

                Kirigami.FormData.label: "Ollama model:"
                visible: page.providerModelVisible("ollama") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "llama3.2"
            }

            QQC2.TextField {
                id: litellmBaseUrlField

                Kirigami.FormData.label: "LiteLLM URL:"
                visible: page.providerEnabled("litellm")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:4000/v1"
            }

            RowLayout {
                Kirigami.FormData.label: "LiteLLM key:"
                visible: page.providerEnabled("litellm")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: litellmApiKeyField

                    Layout.fillWidth: true
                    echoMode: litellmKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("litellm", text);
                        page.refreshIfActiveProvider("litellm");
                    }
                }

                QQC2.Button {
                    property bool saved: false
                    text: saved ? "Saved!" : "Save"
                    icon.name: saved ? "dialog-ok" : "document-save"
                    
                    Timer {
                        id: litellmSaveTimer
                        interval: 2000
                        onTriggered: parent.saved = false
                    }
                    
                    onClicked: {
                        page.saveKey("litellm", litellmApiKeyField.text);
                        page.refreshIfActiveProvider("litellm");
                        saved = true;
                        litellmSaveTimer.start();
                    }
                }

                QQC2.Button {
                    id: litellmKeyShowHide

                    checkable: true
                    text: checked ? "Hide" : "Show"
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("litellm")
                Kirigami.FormData.label: "LiteLLM model:"
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Enter the LiteLLM API key first if required, then refresh models or type a model name."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: litellmModelField

                Kirigami.FormData.label: "LiteLLM model:"
                visible: page.providerModelVisible("litellm") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "gpt-4o-mini"
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: "Advanced"
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                text: "Settings are persisted automatically by KDE when you press Apply or OK."
                opacity: 0.8
            }

            QQC2.Button {
                Kirigami.FormData.label: "Reset settings:"
                text: "Reset to defaults"
                onClicked: page.resetToDefaults()
            }

        }

    }

}
