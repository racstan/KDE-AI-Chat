import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "translations.js" as Translations

KCM.SimpleKCM {
    id: page

    //* Ctrl+scroll zoom for the settings form (0.75–1.5).
    property real configZoom: 1
    property alias cfg_appDisplayName: appDisplayNameField.text
    property alias cfg_appearanceMode: appearanceModeCombo.currentIndex
    property alias cfg_keyStorageMode: storageModeCombo.currentIndex
    // Convenience computed for all KWallet-only visibility guards
    readonly property bool kwalletModeActive: cfg_keyStorageMode === 2
    property string cfg_provider: ""
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
    property alias cfg_qwenBaseUrl: qwenBaseUrlField.text
    property alias cfg_qwenApiKey: qwenApiKeyField.text
    property alias cfg_qwenModel: qwenModelField.text
    property alias cfg_moonshotBaseUrl: moonshotBaseUrlField.text
    property alias cfg_moonshotApiKey: moonshotApiKeyField.text
    property alias cfg_moonshotModel: moonshotModelField.text
    property alias cfg_mimoBaseUrl: mimoBaseUrlField.text
    property alias cfg_mimoApiKey: mimoApiKeyField.text
    property alias cfg_mimoModel: mimoModelField.text
    property alias cfg_maritacaBaseUrl: maritacaBaseUrlField.text
    property alias cfg_maritacaApiKey: maritacaApiKeyField.text
    property alias cfg_maritacaModel: maritacaModelField.text
    property string cfg_language: ""
    readonly property bool isLanguageEnglish: {
        var lang = cfg_language;
        if (lang === "") {
            var localeName = Qt.locale().name || "en";
            lang = localeName.split("_")[0];
        }
        return lang === "en";
    }
    property alias cfg_showInteractiveGuides: showGuidesToggle.checked
    property alias cfg_autoStartOpenCodeServer: autoStartOpenCodeToggle.checked
    property alias cfg_useOpenCode: openCodeToggle.checked
    property alias cfg_playNotificationSound: playSoundToggle.checked
    property alias cfg_openCodeUrl: openCodeUrlField.text
    property alias cfg_openCodeModel: openCodeModelValueField.text
    property alias cfg_openCodeProvider: openCodeProviderValueField.text
    property alias cfg_openCodeStartCommand: openCodeStartCommandField.text
    property alias cfg_openCodeStopCommand: openCodeStopCommandField.text
    property alias cfg_kwalletName: walletNameField.text
    property alias cfg_systemPrompt: systemPromptArea.text
    property alias cfg_memoryEnabled: memoryEnabledToggle.checked
    property alias cfg_userMemory: userMemoryArea.text
    property alias cfg_customHistoryPath: customHistoryPathField.text
    property alias cfg_schedulerEnabled: schedulerMasterSwitch.checked
    property alias cfg_schedulerAutoStart: schedAutoStartToggle.checked
    property alias cfg_executeMissedSchedules: executeMissedSchedulesToggle.checked
    property string cfg_preselectedChatId: ""
    property string cfg_preselectedChatName: ""
    property string keyringStatus: ""
    property string discoveryStatus: ""
    property string storageExportStatus: ""
    // ── Scheduler ──────────────────────────────────────────────────────────
    property bool schedulerDaemonRunning: false
    property string schedulerDataDir: ""
    property var schedulerList: []
    property var schedulerArchivedList: []
    property var schedulerHistory: []
    property string schedulerStatus: ""
    property bool schedSaving: false
    readonly property string schedulerDataPath: {
        var home = Qt.resolvedUrl("~").toString().replace("file://", "");
        if (home === "~")
            home = "";

        return home;
    }
    property var pendingOps: ({
    })
    property var availableWalletNames: []
    // Guard to prevent premature writes during KCM initialization (cfg_ aliases
    // are populated after the combo's onCurrentIndexChanged fires).
    property bool pageReady: false
    property bool keyringBusy: keyringDs.connectedSources.length > 0 || utilityDs.connectedSources.filter(function(sourceName) {
        return sourceName.indexOf("#kwallet-") >= 0;
    }).length > 0
    property bool openCodeBusy: utilityDs.connectedSources.filter(function(sourceName) {
        return sourceName.indexOf("#opencode-") >= 0;
    }).length > 0
    property var providerModelCandidates: []
    property var openCodeProviderCandidates: []
    property var openCodeModelCandidates: []
    property var openCodeProviderModelMap: ({
    })
    property string providerModelSearch: ""
    property string openCodeModelSearch: ""
    property var filteredProviderModels: []
    property var filteredOpenCodeModels: []
    readonly property string walletFolderName: "KaiChat"
    readonly property string walletAppId: "org.kde.plasma.kdeaichat"

    function translate(text) {
        return Translations.translate(text, cfg_language);
    }

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
        var configuredName = (walletNameField.text || "").trim();
        if (configuredName !== "")
            return configuredName;

        if (availableWalletNames.length > 0)
            return availableWalletNames[0];

        return "kdewallet";
    }

    function maybeAdoptDetectedWalletName() {
        if (availableWalletNames.length === 0)
            return ;

        var configured = (walletNameField.text || "").trim();
        if (configured === "") {
            walletNameField.text = availableWalletNames[0];
            return ;
        }
        for (var i = 0; i < availableWalletNames.length; i++) {
            if (availableWalletNames[i].toLowerCase() === configured.toLowerCase()) {
                walletNameField.text = availableWalletNames[i];
                return ;
            }
        }
    }

    function detectWallets() {
        utilityDs.connectSource("sh -lc \"if ! command -v qdbus6 >/dev/null 2>&1 && ! command -v qdbus >/dev/null 2>&1; then echo '__NO_QDBUS__'; else qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null || qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null; fi\" #kwallet-wallet-list");
    }

    function setActiveProviderModelValue(value) {
        currentProviderConfig().modelField.text = value || "";
    }

    function activeProviderModelValue() {
        return currentProviderConfig().modelField.text || "";
    }

    function walletReadCommand(walletName, keyName) {
        var escapedWallet = shellEscape(walletName);
        var escapedFolder = shellEscape(walletFolderName);
        var escapedKey = shellEscape(keyName);
        var escapedAppId = shellEscape(walletAppId);
        return "sh -lc '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "key='\''" + escapedKey + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "wallets=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null); " + "if ! printf %s \"$wallets\" | grep -Fxq \"$wallet\"; then printf \"__KAI_LOAD__:NO_WALLET\"; exit 0; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_LOAD__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; printf \"__KAI_LOAD__:NO_FOLDER\"; exit 0; fi; " + "hasEntry=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasEntry \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasEntry\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; printf \"__KAI_LOAD__:NO_ENTRY\"; exit 0; fi; " + "secret=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.readPassword \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null); " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "printf \"__KAI_SECRET__:%s\" \"$secret\"'";
    }

    function walletWriteCommand(walletName, keyName, value) {
        var escapedWallet = shellEscape(walletName);
        var escapedFolder = shellEscape(walletFolderName);
        var escapedKey = shellEscape(keyName);
        var escapedValue = shellEscape(value);
        var escapedAppId = shellEscape(walletAppId);
        return "sh -lc '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "key='\''" + escapedKey + "'\''; " + "value='\''" + escapedValue + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_STORE__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.createFolder \"$handle\" \"$folder\" \"$appid\" >/dev/null 2>&1; fi; " + "result=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.writePassword \"$handle\" \"$folder\" \"$key\" \"$value\" \"$appid\" 2>/dev/null | tail -n 1); " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "printf \"__KAI_STORE__:%s\" \"$result\"'";
    }

    function walletInitCommand(walletName) {
        var escapedWallet = shellEscape(walletName);
        var escapedFolder = shellEscape(walletFolderName);
        var escapedAppId = shellEscape(walletAppId);
        return "sh -lc '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_INIT__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" = true ]; then printf \"__KAI_INIT__:READY\"; else created=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.createFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); if [ \"$created\" = true ]; then printf \"__KAI_INIT__:CREATED\"; else printf \"__KAI_INIT__:CREATE_FAILED\"; fi; fi; " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1'";
    }

    function walletStatusCommand(walletName) {
        var escapedWallet = shellEscape(walletName);
        var escapedFolder = shellEscape(walletFolderName);
        var escapedAppId = shellEscape(walletAppId);
        return "sh -lc '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "wallets=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null); " + "if ! printf %s \"$wallets\" | grep -Fxq \"$wallet\"; then printf \"__KAI_STATUS__:NO_WALLET:%s\" \"$wallets\"; exit 0; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_STATUS__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "if [ \"$hasFolder\" = true ]; then printf \"__KAI_STATUS__:READY\"; else printf \"__KAI_STATUS__:NO_FOLDER\"; fi'";
    }

    function walletBulkReadCommand(walletName) {
        var escapedWallet = shellEscape(walletName);
        var escapedFolder = shellEscape(walletFolderName);
        var escapedAppId = shellEscape(walletAppId);
        return "sh -lc '" + "wallet='\''" + escapedWallet + "'\''; " + "folder='\''" + escapedFolder + "'\''; " + "appid='\''" + escapedAppId + "'\''; " + "qdbus_cmd=\"qdbus6\"; if ! command -v qdbus6 >/dev/null 2>&1; then qdbus_cmd=\"qdbus\"; fi; " + "wallets=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets 2>/dev/null); " + "if ! printf %s \"$wallets\" | grep -Fxq \"$wallet\"; then printf \"__KAI_BULK__:NO_WALLET\"; exit 0; fi; " + "handle=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open \"$wallet\" 0 \"$appid\" 2>/dev/null | tail -n 1); " + "if [ -z \"$handle\" ] || [ \"$handle\" -lt 0 ] 2>/dev/null; then printf \"__KAI_BULK__:OPEN_FAILED\"; exit 0; fi; " + "hasFolder=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasFolder \"$handle\" \"$folder\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasFolder\" != true ]; then $qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; printf \"__KAI_BULK__:NO_FOLDER\"; exit 0; fi; " + "for target in openai anthropic groq deepseek minimax fireworks google openrouter mistral cloudflare nvidia huggingface xai litellm qwen moonshot mimo maritaca; do " + "key=\"kai-chat-${target}-api-key\"; " + "hasEntry=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.hasEntry \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null | tail -n 1); " + "if [ \"$hasEntry\" = true ]; then secret=$($qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.readPassword \"$handle\" \"$folder\" \"$key\" \"$appid\" 2>/dev/null); printf \"__KAI_SECRET__:%s:%s\\n\" \"$target\" \"$secret\"; fi; " + "done; " + "$qdbus_cmd org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.close \"$handle\" false \"$appid\" >/dev/null 2>&1; " + "printf \"__KAI_BULK__:DONE\"'";
    }

    function shellEscape(s) {
        return (s || "").replace(/'/g, "'\\''");
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

        if (providerId === "qwen")
            return (qwenApiKeyField.text || "").trim() !== "";

        if (providerId === "moonshot")
            return (moonshotApiKeyField.text || "").trim() !== "";

        if (providerId === "mimo")
            return (mimoApiKeyField.text || "").trim() !== "";

        if (providerId === "maritaca")
            return (maritacaApiKeyField.text || "").trim() !== "";

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

        if (p === "qwen")
            return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": qwenBaseUrlField.text,
            "apiKey": qwenApiKeyField.text,
            "modelField": qwenModelField
        };

        if (p === "moonshot")
            return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": moonshotBaseUrlField.text,
            "apiKey": moonshotApiKeyField.text,
            "modelField": moonshotModelField
        };

        if (p === "mimo")
            return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": mimoBaseUrlField.text,
            "apiKey": mimoApiKeyField.text,
            "modelField": mimoModelField
        };

        if (p === "maritaca")
            return {
            "id": p,
            "type": "openai-compat",
            "baseUrl": maritacaBaseUrlField.text,
            "apiKey": maritacaApiKeyField.text,
            "modelField": maritacaModelField
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

    function startOpenCodeServerAutomatically() {
        discoveryStatus = "Starting OpenCode server automatically...";
        var startCmd = openCodeStartCommandField.text || "nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 &";
        var cmd = "sh -lc '" + shellEscape(startCmd) + "'";
        utilityDs.connectSource(cmd + " #opencode-autostart");
        // After a short delay, attempt discovery again
        openCodeAutoStartTimer.restart();
    }

    function checkAndAutoStartOpenCodeServer() {
        var url = openCodeServerRoot(openCodeUrlField.text) + "/config/providers";
        discoveryStatus = "Checking OpenCode server...";
        requestJson(url, {
        }, function(obj) {
            // Server is already running — just do normal discovery
            refreshOpenCodeDiscovery();
        }, function(err) {
            // Server not reachable — auto-start it
            if (autoStartOpenCodeToggle.checked)
                startOpenCodeServerAutomatically();
            else
                discoveryStatus = "OpenCode server check failed: " + err + ". Click \"Start server\" or enable Auto-start.";
        });
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
            return ;

        if (!isBulk)
            cancelKeyringOps();

        var walletName = effectiveWalletName();
        var keyName = "kai-chat-" + targetId + "-api-key";
        var cmd = walletWriteCommand(walletName, keyName, value);
        var ops = page.pendingOps;
        ops[cmd] = {
            "mode": "store",
            "target": targetId,
            "bulk": !!isBulk
        };
        page.pendingOps = ops;
        keyringDs.connectSource(cmd);
    }

    function saveKey(targetId, value) {
        var val = (value || "").trim();
        if (cfg_keyStorageMode === 1)
            syncKeysToDisk();
        else if (cfg_keyStorageMode === 2)
            kwalletStore(targetId, val, false);
    }

    function kwalletLoad(targetId, isBulk) {
        if (!isBulk)
            cancelKeyringOps();

        var walletName = effectiveWalletName();
        var keyName = "kai-chat-" + targetId + "-api-key";
        var cmd = walletReadCommand(walletName, keyName);
        var ops = page.pendingOps;
        ops[cmd] = {
            "mode": "load",
            "target": targetId,
            "bulk": !!isBulk
        };
        page.pendingOps = ops;
        keyringDs.connectSource(cmd);
    }

    function applyLoadedKey(targetId, secretValue) {
        var normalized = (secretValue || "").trim();
        var lower = normalized.toLowerCase();
        if (normalized === "" || normalized.indexOf("__KAI_") === 0)
            return ;

        if (lower.indexOf("not found") >= 0)
            return ;

        if (lower.indexOf("does not exist") >= 0)
            return ;

        if (lower.indexOf("could not open") >= 0)
            return ;

        if (lower.indexOf("wallet") >= 0)
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
        else if (targetId === "qwen")
            qwenApiKeyField.text = normalized;
        else if (targetId === "moonshot")
            moonshotApiKeyField.text = normalized;
        else if (targetId === "mimo")
            mimoApiKeyField.text = normalized;
        else if (targetId === "maritaca")
            maritacaApiKeyField.text = normalized;
        var after = apiKeyForTarget(targetId);
        if (before !== after && providerBox.currentValue === targetId)
            refreshCurrentProviderModels();

    }

    function keyTargetIds() {
        return ["openai", "anthropic", "groq", "deepseek", "minimax", "fireworks", "google", "openrouter", "mistral", "cloudflare", "nvidia", "huggingface", "xai", "litellm", "qwen", "moonshot", "mimo", "maritaca"];
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

        if (targetId === "qwen")
            return qwenApiKeyField.text;

        if (targetId === "moonshot")
            return moonshotApiKeyField.text;

        if (targetId === "mimo")
            return mimoApiKeyField.text;

        if (targetId === "maritaca")
            return maritacaApiKeyField.text;

        return "";
    }

    function kwalletLoadAll() {
        cancelKeyringOps();
        var walletName = effectiveWalletName();
        console.log("[KAI-DEBUG] kwalletLoadAll walletName:", walletName);
        var cmd = walletBulkReadCommand(walletName) + " #kwallet-refresh-all";
        console.log("[KAI-DEBUG] kwalletLoadAll command:", cmd);
        keyringStatus = "Refreshing API keys from KWallet...";
        utilityDs.connectSource(cmd);
    }

    function kwalletStoreAll() {
        cancelKeyringOps();
        var ids = keyTargetIds();
        var count = 0;
        for (var i = 0; i < ids.length; i++) {
            var value = (apiKeyForTarget(ids[i]) || "").trim();
            if (value === "")
                continue;

            kwalletStore(ids[i], value, true);
            count++;
        }
        keyringStatus = count > 0 ? ("Synced the above key as well as other keys (" + count + " total).") : "No API keys to sync.";
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
        qwenApiKeyField.text = "";
        moonshotApiKeyField.text = "";
        mimoApiKeyField.text = "";
        maritacaApiKeyField.text = "";
    }

    function base64Encode(str) {
        try {
            return Qt.btoa(unescape(encodeURIComponent(str)));
        } catch (e) {
            console.log("base64Encode error:", e);
            return "";
        }
    }

    function loadKeysFromPlainConfig() {
        utilityDs.connectSource("python3 -c \"import configparser, json; config = configparser.ConfigParser(); config.optionxform = str; config.read('/home/home/.config/kdeaichatrc'); print(json.dumps(dict(config['General']) if 'General' in config else {}))\" #plainconfig-load");
    }

    function applyPlainConfigKeys(keys) {
        apiKeyField.text = keys["apiKey"] || "";
        anthropicApiKeyField.text = keys["anthropicApiKey"] || "";
        groqApiKeyField.text = keys["groqApiKey"] || "";
        deepSeekApiKeyField.text = keys["deepSeekApiKey"] || "";
        miniMaxApiKeyField.text = keys["miniMaxApiKey"] || "";
        fireworksApiKeyField.text = keys["fireworksApiKey"] || "";
        googleApiKeyField.text = keys["googleApiKey"] || "";
        openRouterApiKeyField.text = keys["openRouterApiKey"] || "";
        mistralApiKeyField.text = keys["mistralApiKey"] || "";
        cloudflareApiKeyField.text = keys["cloudflareApiKey"] || "";
        nvidiaApiKeyField.text = keys["nvidiaApiKey"] || "";
        huggingFaceApiKeyField.text = keys["huggingFaceApiKey"] || "";
        xaiApiKeyField.text = keys["xaiApiKey"] || "";
        litellmApiKeyField.text = keys["litellmApiKey"] || "";
        qwenApiKeyField.text = keys["qwenApiKey"] || "";
        moonshotApiKeyField.text = keys["moonshotApiKey"] || "";
        mimoApiKeyField.text = keys["mimoApiKey"] || "";
        maritacaApiKeyField.text = keys["maritacaApiKey"] || "";
    }

    function writeKeysToDiskAndOpen() {
        var payload = {
            "apiKey": apiKeyField.text,
            "anthropicApiKey": anthropicApiKeyField.text,
            "groqApiKey": groqApiKeyField.text,
            "deepSeekApiKey": deepSeekApiKeyField.text,
            "miniMaxApiKey": miniMaxApiKeyField.text,
            "fireworksApiKey": fireworksApiKeyField.text,
            "googleApiKey": googleApiKeyField.text,
            "openRouterApiKey": openRouterApiKeyField.text,
            "mistralApiKey": mistralApiKeyField.text,
            "cloudflareApiKey": cloudflareApiKeyField.text,
            "nvidiaApiKey": nvidiaApiKeyField.text,
            "huggingFaceApiKey": huggingFaceApiKeyField.text,
            "xaiApiKey": xaiApiKeyField.text,
            "litellmApiKey": litellmApiKeyField.text,
            "qwenApiKey": qwenApiKeyField.text,
            "moonshotApiKey": moonshotApiKeyField.text,
            "mimoApiKey": mimoApiKeyField.text,
            "maritacaApiKey": maritacaApiKeyField.text
        };
        var b64Str = base64Encode(JSON.stringify(payload));
        var py = "import configparser, json, base64; data = json.loads(base64.b64decode('" + b64Str + "').decode('utf-8')); config = configparser.ConfigParser(); config.optionxform = str; config.read('/home/home/.config/kdeaichatrc'); config['General'] = config['General'] if 'General' in config else {}; [config['General'].__setitem__(k, str(v)) for k, v in data.items()]; f=open('/home/home/.config/kdeaichatrc', 'w'); config.write(f); f.close()";
        var b64Py = base64Encode(py);
        var cmd = "python3 -c \"import base64; exec(base64.b64decode('" + b64Py + "').decode('utf-8'))\" && xdg-open ~/.config/kdeaichatrc #open-config";
        utilityDs.connectSource(cmd);
    }

    function syncKeysToDisk() {
        // Write current key fields to ~/.config/kdeaichatrc (plain-config extra copy).
        // cfg_ aliases handle saving to the Plasma config automatically on OK/Apply.
        var payload = {
            "apiKey": apiKeyField.text,
            "anthropicApiKey": anthropicApiKeyField.text,
            "groqApiKey": groqApiKeyField.text,
            "deepSeekApiKey": deepSeekApiKeyField.text,
            "miniMaxApiKey": miniMaxApiKeyField.text,
            "fireworksApiKey": fireworksApiKeyField.text,
            "googleApiKey": googleApiKeyField.text,
            "openRouterApiKey": openRouterApiKeyField.text,
            "mistralApiKey": mistralApiKeyField.text,
            "cloudflareApiKey": cloudflareApiKeyField.text,
            "nvidiaApiKey": nvidiaApiKeyField.text,
            "huggingFaceApiKey": huggingFaceApiKeyField.text,
            "xaiApiKey": xaiApiKeyField.text,
            "litellmApiKey": litellmApiKeyField.text,
            "qwenApiKey": qwenApiKeyField.text,
            "moonshotApiKey": moonshotApiKeyField.text,
            "mimoApiKey": mimoApiKeyField.text,
            "maritacaApiKey": maritacaApiKeyField.text
        };
        var b64Str = base64Encode(JSON.stringify(payload));
        var py = "import configparser, json, base64; data = json.loads(base64.b64decode('" + b64Str + "').decode('utf-8')); config = configparser.ConfigParser(); config.optionxform = str; config.read('/home/home/.config/kdeaichatrc'); config['General'] = config['General'] if 'General' in config else {}; [config['General'].__setitem__(k, str(v)) for k, v in data.items()]; f=open('/home/home/.config/kdeaichatrc', 'w'); config.write(f); f.close()";
        var b64Py = base64Encode(py);
        var cmd = "python3 -c \"import base64; exec(base64.b64decode('" + b64Py + "').decode('utf-8'))\"";
        utilityDs.connectSource(cmd + " #plainconfig-sync");
    }

    function clearKeysFromDisk() {
        var py = [
            "import configparser",
            "config = configparser.ConfigParser()",
            "config.optionxform = str",
            "config.read('/home/home/.config/kdeaichatrc')",
            "if 'General' in config:",
            "    for k in ['apiKey', 'anthropicApiKey', 'groqApiKey', 'deepSeekApiKey', 'miniMaxApiKey', 'fireworksApiKey', 'googleApiKey', 'openRouterApiKey', 'mistralApiKey', 'cloudflareApiKey', 'nvidiaApiKey', 'huggingFaceApiKey', 'xaiApiKey', 'litellmApiKey', 'qwenApiKey', 'moonshotApiKey', 'mimoApiKey', 'maritacaApiKey']:",
            "        config['General'].pop(k, None)",
            "f = open('/home/home/.config/kdeaichatrc', 'w')",
            "config.write(f)",
            "f.close()"
        ].join("\n");
        var b64Py = base64Encode(py);
        var cmd = "python3 -c \"import base64; exec(base64.b64decode('" + b64Py + "').decode('utf-8'))\"";
        utilityDs.connectSource(cmd + " #plainconfig-clear");
        plasmoid.configuration.apiKey = "";
        plasmoid.configuration.anthropicApiKey = "";
        plasmoid.configuration.groqApiKey = "";
        plasmoid.configuration.deepSeekApiKey = "";
        plasmoid.configuration.miniMaxApiKey = "";
        plasmoid.configuration.fireworksApiKey = "";
        plasmoid.configuration.googleApiKey = "";
        plasmoid.configuration.openRouterApiKey = "";
        plasmoid.configuration.mistralApiKey = "";
        plasmoid.configuration.cloudflareApiKey = "";
        plasmoid.configuration.nvidiaApiKey = "";
        plasmoid.configuration.huggingFaceApiKey = "";
        plasmoid.configuration.xaiApiKey = "";
        plasmoid.configuration.litellmApiKey = "";
        plasmoid.configuration.qwenApiKey = "";
        plasmoid.configuration.moonshotApiKey = "";
        plasmoid.configuration.mimoApiKey = "";
        plasmoid.configuration.maritacaApiKey = "";
    }

    function saveGeneralSettingsOnly() {
        plasmoid.configuration.appDisplayName = appDisplayNameField.text;
        plasmoid.configuration.appearanceMode = appearanceModeCombo.currentIndex;
        plasmoid.configuration.keyStorageMode = cfg_keyStorageMode;
        plasmoid.configuration.provider = cfg_provider;
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
        plasmoid.configuration.qwenBaseUrl = qwenBaseUrlField.text;
        plasmoid.configuration.qwenApiKey = qwenApiKeyField.text;
        plasmoid.configuration.qwenModel = qwenModelField.text;
        plasmoid.configuration.moonshotBaseUrl = moonshotBaseUrlField.text;
        plasmoid.configuration.moonshotApiKey = moonshotApiKeyField.text;
        plasmoid.configuration.moonshotModel = moonshotModelField.text;
        plasmoid.configuration.mimoBaseUrl = mimoBaseUrlField.text;
        plasmoid.configuration.mimoApiKey = mimoApiKeyField.text;
        plasmoid.configuration.mimoModel = mimoModelField.text;
        plasmoid.configuration.maritacaBaseUrl = maritacaBaseUrlField.text;
        plasmoid.configuration.maritacaApiKey = maritacaApiKeyField.text;
        plasmoid.configuration.maritacaModel = maritacaModelField.text;
        plasmoid.configuration.language = cfg_language || "";
        plasmoid.configuration.showInteractiveGuides = showGuidesToggle.checked;
        plasmoid.configuration.autoStartOpenCodeServer = autoStartOpenCodeToggle.checked;
        plasmoid.configuration.useOpenCode = openCodeToggle.checked;
        plasmoid.configuration.playNotificationSound = playSoundToggle.checked;
        plasmoid.configuration.openCodeUrl = openCodeUrlField.text;
        plasmoid.configuration.openCodeModel = openCodeModelValueField.text;
        plasmoid.configuration.openCodeProvider = openCodeProviderValueField.text;
        plasmoid.configuration.openCodeStartCommand = openCodeStartCommandField.text;
        plasmoid.configuration.openCodeStopCommand = openCodeStopCommandField.text;
        plasmoid.configuration.kwalletName = walletNameField.text;
        plasmoid.configuration.systemPrompt = systemPromptArea.text;
        plasmoid.configuration.memoryEnabled = memoryEnabledToggle.checked;
        plasmoid.configuration.userMemory = userMemoryArea.text;
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
        appDisplayNameField.text = "KDE AI Chat";
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
        qwenBaseUrlField.text = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1";
        qwenApiKeyField.text = "";
        qwenModelField.text = "qwen-max";
        moonshotBaseUrlField.text = "https://api.moonshot.ai/v1";
        moonshotApiKeyField.text = "";
        moonshotModelField.text = "moonshot-v1-8k";
        mimoBaseUrlField.text = "https://api.xiaomimimo.com/v1";
        mimoApiKeyField.text = "";
        mimoModelField.text = "mimo-v2-pro";
        maritacaBaseUrlField.text = "https://chat.maritaca.ai/api";
        maritacaApiKeyField.text = "";
        maritacaModelField.text = "sabia-4";
        languageCombo.currentIndex = 0;
        showGuidesToggle.checked = true;
        autoStartOpenCodeToggle.checked = false;
        openCodeToggle.checked = false;
        openCodeUrlField.text = "http://127.0.0.1:4096/v1";
        openCodeProviderValueField.text = "";
        openCodeModelValueField.text = "";
        openCodeStartCommandField.text = "nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 & echo OpenCode start command launched.";
        openCodeStopCommandField.text = "pkill -f opencode >/dev/null 2>&1 && echo OpenCode stop command launched. || echo No OpenCode process matched.";
        walletNameField.text = availableWalletNames.length > 0 ? availableWalletNames[0] : "kdewallet";
        systemPromptArea.text = "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.";
        memoryEnabledToggle.checked = false;
        userMemoryArea.text = "";
        customHistoryPathField.text = "~/.config";
        providerModelCandidates = [];
        openCodeProviderCandidates = [];
        openCodeModelCandidates = [];
        openCodeProviderModelMap = ({
        });
        discoveryStatus = "Settings reset to defaults.";
    }

    // ── Scheduler helpers ──────────────────────────────────────────────────────
    function schedAutoSetup() {
        var srcPath = String(Qt.resolvedUrl("../scripts/kde-ai-scheduler.py")).replace("file://", "");
        var pyScript = "import os, shutil\n" + "src = '" + srcPath + "'\n" + "dest = os.path.expanduser('~/.local/share/kdeaichat/kde-ai-scheduler.py')\n" + "os.makedirs(os.path.dirname(dest), exist_ok=True)\n" + "os.makedirs(os.path.expanduser('~/.local/share/kdeaichat/results'), exist_ok=True)\n" + "if os.path.exists(src):\n" + "    shutil.copy2(src, dest)\n" + "    os.chmod(dest, 0o755)\n" + "sjson = os.path.expanduser('~/.local/share/kdeaichat/schedules.json')\n" + "if not os.path.exists(sjson):\n" + "    with open(sjson, 'w') as f:\n" + "        f.write('{\"version\":1,\"schedules\":[]}')\n" + "    os.chmod(sjson, 0o600)\n" + "sdir = os.path.expanduser('~/.config/systemd/user')\n" + "os.makedirs(sdir, exist_ok=True)\n" + "sfile = sdir + '/kde-ai-scheduler.service'\n" + "content = '[Unit]\\nDescription=KDE AI Chat Scheduler Daemon\\nAfter=network-online.target\\nWants=network-online.target\\n\\n[Service]\\nType=simple\\nExecStart=/usr/bin/python3 %h/.local/share/kdeaichat/kde-ai-scheduler.py\\nRestart=on-failure\\nRestartSec=30\\nStandardOutput=journal\\nStandardError=journal\\nExecReload=/bin/kill -HUP $MAINPID\\nKillMode=process\\n\\n[Install]\\nWantedBy=default.target\\n'\n" + "with open(sfile, 'w') as f: f.write(content)\n" + "os.system('systemctl --user daemon-reload')\n" + "if os.system('systemctl --user is-enabled kde-ai-scheduler.service >/dev/null 2>&1') == 0:\n" + "    print('AUTO_ENABLED')\n" + "else:\n" + "    print('AUTO_DISABLED')\n";
        var b64 = base64Encode(pyScript);
        var cmd = "python3 -c \"import base64; exec(base64.b64decode('" + b64 + "').decode('utf-8'))\"";
        utilityDs.connectSource("sh -lc '" + cmd + "' #sched-auto-setup");
    }

    function pollSchedulerState() {
        utilityDs.connectSource("sh -lc 'pgrep -f kde-ai-scheduler.py > /dev/null 2>&1 && echo SCHED_RUNNING || echo SCHED_STOPPED' #sched-poll-" + Date.now());
    }

    function schedLoadSchedules() {
        var cmd = "cat ~/.local/share/kdeaichat/schedules.json 2>/dev/null || echo '{\"schedules\":[],\"history\":[]}'";
        utilityDs.connectSource("sh -lc '" + cmd + "' #sched-load");
    }

    function schedSaveSchedules(items) {
        page.schedulerList = items;
        page.schedSaveAll();
    }

    function schedSaveAll() {
        page.schedSaving = true;
        var all = [];
        // Add active
        for (var i = 0; i < page.schedulerList.length; i++) {
            var s = Object.assign({}, page.schedulerList[i]);
            s.archived = false;
            all.push(s);
        }
        // Add archived
        for (var j = 0; j < page.schedulerArchivedList.length; j++) {
            var sa = Object.assign({}, page.schedulerArchivedList[j]);
            sa.archived = true;
            all.push(sa);
        }
        var payload = {
            "version": 1,
            "schedules": all,
            "history": page.schedulerHistory,
            "settings": {
                "executeMissedSchedules": !!executeMissedSchedulesToggle.checked
            }
        };
        var b64 = base64Encode(JSON.stringify(payload));
        var py = "import base64,json,os; d=base64.b64decode('" + b64 + "'); " +
                 "p=os.path.expanduser('~/.local/share/kdeaichat'); os.makedirs(p,exist_ok=True); " +
                 "f=open(p+'/schedules.json','w',encoding='utf-8'); f.write(d.decode('utf-8')); f.close(); print('SCHED_SAVE_OK')";
        var b64Py = base64Encode(py);
        var cmd = "python3 -c \"import base64; exec(base64.b64decode('" + b64Py + "').decode('utf-8'))\"";
        utilityDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-save");
    }

    function schedTriggerNow(index) {
        var copy = page.schedulerList.slice();
        if (index < 0 || index >= copy.length)
            return ;

        var s = JSON.parse(JSON.stringify(copy[index]));
        s.triggerNow = true;
        copy[index] = s;
        page.schedulerList = copy;
        page.schedSaveAll();
    }

    function schedMakeUuid() {
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
            var r = Math.random() * 16 | 0;
            return (c === "x" ? r : (r & 3 | 8)).toString(16);
        });
    }

    function openPrefilledScheduleDialog(pId, pName) {
        if (!pId || pId === "")
            return;
        var now = new Date();
        now.setMinutes(now.getMinutes() + 5);
        scheduleDialog.draft = {
            "id": page.schedMakeUuid(),
            "name": "",
            "enabled": true,
            "chatId": pId,
            "chatName": pName || "Chat",
            "message": "",
            "taskType": "single",
            "startDate": now.toISOString(),
            "schedType": "days",
            "schedEvery": 1,
            "schedTime": "09:00",
            "schedDays": [1],
            "schedDayOfMonth": 1,
            "limitEnabled": false,
            "limitCount": 5,
            "notify": true,
            "createdAt": new Date().toISOString()
        };
        scheduleDialog.editingIndex = -2;
        scheduleDialog.open();

        // Clear configuration values immediately so it doesn't pop up again next time!
        if (typeof page.cfg_preselectedChatId !== "undefined") {
            page.cfg_preselectedChatId = "";
            page.cfg_preselectedChatName = "";
        }
        if (plasmoid.configuration && "preselectedChatId" in plasmoid.configuration) {
            plasmoid.configuration.preselectedChatId = "";
            plasmoid.configuration.preselectedChatName = "";
        }
    }

    function schedDefaultBaseUrl(provider) {
        var urls = {
            "openai": "https://api.openai.com/v1",
            "anthropic": "https://api.anthropic.com/v1",
            "groq": "https://api.groq.com/openai/v1",
            "google": "https://generativelanguage.googleapis.com/v1beta/openai/",
            "deepseek": "https://api.deepseek.com",
            "mistral": "https://api.mistral.ai/v1",
            "openrouter": "https://openrouter.ai/api/v1",
            "xai": "https://api.x.ai/v1",
            "nvidia": "https://integrate.api.nvidia.com/v1",
            "fireworks": "https://api.fireworks.ai/inference/v1",
            "minimax": "https://api.minimax.io/v1",
            "cloudflare": "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1",
            "huggingface": "https://router.huggingface.co/v1",
            "ollama": "http://localhost:11434/v1",
            "lmstudio": "http://localhost:1234/v1",
            "local": "http://localhost:11434/v1",
            "litellm": "http://localhost:4000/v1",
            "qwen": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
            "moonshot": "https://api.moonshot.ai/v1",
            "mimo": "https://api.xiaomimimo.com/v1",
            "maritaca": "https://chat.maritaca.ai/api"
        };
        return urls[provider] || "https://api.openai.com/v1";
    }

    function schedHumanCron(expr) {
        if (!expr)
            return "No schedule";

        var parts = expr.trim().split(/\s+/);
        if (parts.length !== 5)
            return expr;

        var min = parts[0], hr = parts[1], dom = parts[2], mon = parts[3], dow = parts[4];
        if (min === "0" && hr !== "*" && dom === "*" && mon === "*") {
            var h = parseInt(hr), ampm = h >= 12 ? "PM" : "AM", h12 = h % 12 || 12;
            var dayStr = dow === "*" ? "every day" : dow === "1-5" ? "weekdays" : dow === "6,0" || dow === "0,6" ? "weekends" : "on selected days";
            return "Daily at " + h12 + ":00 " + ampm + " " + dayStr;
        }
        if (hr.startsWith && hr.startsWith("*/"))
            return "Every " + hr.slice(2) + " hours";

        return expr;
    }

    horizontalScrollBarPolicy: configZoom > 1.01 ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff
    Component.onCompleted: {
        if (plasmoid.configuration.appearanceMode === 3 || plasmoid.configuration.appearanceMode > 2)
            plasmoid.configuration.appearanceMode = 0;

        // cfg_ aliases already load the Plasma-stored values automatically.
        // For KWallet mode, trigger wallet detection to populate the fields.
        // For session-only mode, wipe the fields so stale cfg values aren't used.
        if (!openCodeToggle.checked && plasmoid.configuration.keyStorageMode === 2)
            detectWallets();
        else if (plasmoid.configuration.keyStorageMode === 0)
            clearAllApiKeyFields();
        if (openCodeToggle.checked) {
            var savedProvider = openCodeProviderValueField.text || "";
            var savedModel = openCodeModelValueField.text || "";
            if (savedProvider) {
                openCodeProviderCandidates = [savedProvider];
                if (savedModel) {
                    var mmap = {};
                    mmap[savedProvider] = [savedModel];
                    openCodeProviderModelMap = mmap;
                    openCodeModelCandidates = [savedModel];
                }
            }
            if (plasmoid.configuration.autoStartOpenCodeServer)
                checkAndAutoStartOpenCodeServer();
            else
                refreshOpenCodeDiscovery();
        }
        // Mark page as fully initialised — cfg_ aliases are now populated.
        // Any storage-mode handler that fires before this point is a no-op
        // for write operations so we don't flush empty fields to disk.
        pageReady = true;
        // Load existing schedules so the count badge shows immediately.
        schedLoadSchedules();
        // Run scheduler auto deployment & systemd check
        schedAutoSetup();
        // Poll immediately so the status badge updates instantly
        pollSchedulerState();
        // If opened from chat via "Create Schedule", immediately open the scheduling dialog prefilled
        var pId = "";
        var pName = "Chat";
        if (typeof page.cfg_preselectedChatId !== "undefined" && page.cfg_preselectedChatId !== "") {
            pId = page.cfg_preselectedChatId;
            pName = page.cfg_preselectedChatName || "Chat";
        } else if (plasmoid.configuration && "preselectedChatId" in plasmoid.configuration && plasmoid.configuration["preselectedChatId"] !== "") {
            pId = plasmoid.configuration["preselectedChatId"];
            pName = plasmoid.configuration["preselectedChatName"] || "Chat";
        }
        if (pId !== "") {
            openPrefilledScheduleDialog(pId, pName);
        }
    }

    Connections {
        target: plasmoid.configuration
        function onPreselectedChatIdChanged() {
            var pId = plasmoid.configuration.preselectedChatId;
            if (pId && pId !== "") {
                var pName = plasmoid.configuration.preselectedChatName || "Chat";
                openPrefilledScheduleDialog(pId, pName);
            }
        }
    }
    Component.onDestruction: {
        saveGeneralSettingsOnly();
        // cfg_ aliases are auto-saved by KCM on OK/Apply — no async work needed here.
        // For KWallet mode, sync the current fields to KWallet before closing.
        // For Plain Config mode, persist keys to disk on close as well.
        if (plasmoid.configuration.keyStorageMode === 2)
            kwalletStoreAll();
        else if (plasmoid.configuration.keyStorageMode === 1)
            syncKeysToDisk();
        else if (plasmoid.configuration.keyStorageMode === 0)
            clearKeysFromDisk();
    }

    Timer {
        id: openCodeAutoStartTimer

        interval: 2500
        repeat: false
        onTriggered: refreshOpenCodeDiscovery()
    }

    // ── Schedule Management Dialog (human-friendly) ────────────────────────────
    ScheduleDialog {
        id: scheduleDialog
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
        id: keyringDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim();
            var stderr = (data["stderr"] || "").trim();
            var op = page.pendingOps[sourceName];
            if (op) {
                var copy = page.pendingOps;
                delete copy[sourceName];
                page.pendingOps = copy;
            }
            if (!op) {
                disconnectSource(sourceName);
                return ;
            }
            if (op.mode === "load") {
                if (stdout.indexOf("__KAI_SECRET__:") === 0) {
                    var loadedValue = stdout.slice("__KAI_SECRET__:".length);
                    page.applyLoadedKey(op.target, loadedValue);
                    page.keyringStatus = op.bulk ? "Refreshing API keys from KWallet..." : ("Loaded key for " + op.target + " from KWallet.");
                } else if (!op.bulk) {
                    if (stdout === "__KAI_LOAD__:NO_WALLET")
                        page.keyringStatus = "Configured wallet not found. Use Detect wallets or Create wallet.";
                    else if (stdout === "__KAI_LOAD__:OPEN_FAILED")
                        page.keyringStatus = "KWallet did not open the selected wallet.";
                    else if (stdout === "__KAI_LOAD__:NO_FOLDER")
                        page.keyringStatus = "Wallet opened, but KDE AI Chat storage is not initialized yet. Click Create wallet first.";
                    else if (stdout === "__KAI_LOAD__:NO_ENTRY")
                        page.keyringStatus = "No saved key for " + op.target + " in KWallet.";
                    else if (stderr !== "")
                        page.keyringStatus = "KWallet (" + op.target + "): " + stderr;
                    else
                        page.keyringStatus = "No saved key for " + op.target + " in KWallet.";
                }
            } else {
                if (!op.bulk) {
                    if (stdout === "__KAI_STORE__:OPEN_FAILED")
                        page.keyringStatus = "KWallet did not open the selected wallet.";
                    else if (stdout.indexOf("__KAI_STORE__:") === 0)
                        page.keyringStatus = "Saved key for " + (op.target || "provider") + " to KWallet.";
                    else if (stderr !== "")
                        page.keyringStatus = "KWallet error: " + stderr;
                    else
                        page.keyringStatus = "Saved key for " + (op.target || "provider") + " to KWallet.";
                }
            }
            disconnectSource(sourceName);
        }
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
                    return ;
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
            } else if (sourceName.indexOf("plainconfig-load") >= 0) {
                try {
                    var keys = JSON.parse(out);
                    applyPlainConfigKeys(keys);
                    keyringStatus = "Keys successfully reloaded from the physical configuration file.";
                } catch (e) {
                    console.log("Error parsing plain config: " + e);
                    keyringStatus = "Error parsing config file: " + e;
                }
            } else if (sourceName.indexOf("plainconfig-sync") >= 0) {
                if (err !== "")
                    keyringStatus = "Error saving to config file: " + err;

            } else if (sourceName.indexOf("sched-poll-") >= 0) {
                page.schedulerDaemonRunning = (out === "SCHED_RUNNING");
                if (!page.schedulerDaemonRunning && page.schedulerStatus === "Restarting…")
                    page.schedulerStatus = "Stopped";
            } else if (sourceName.indexOf("sched-start") >= 0) {
                page.schedulerStatus = ""; // badge shows state, no separate text needed
                // Re-poll immediately to confirm daemon is up
                Qt.callLater(pollSchedulerState);
            } else if (sourceName.indexOf("sched-stop") >= 0) {
                page.schedulerDaemonRunning = false;
                page.schedulerStatus = "Stopped";
                Qt.callLater(pollSchedulerState);
            } else if (sourceName.indexOf("sched-hup") >= 0) {
                page.schedulerStatus = "Schedules reloaded (SIGHUP sent).";
            } else if (sourceName.indexOf("storage-export-") >= 0) {
                page.storageExportStatus = (out.trim() === "OK" || err === "") ? "✓ Exported!" : "Export failed";
                exportStatusTimer.restart();
            } else if (sourceName.indexOf("sched-enable") >= 0) {
                page.schedulerStatus = out.indexOf("SCHED_ENABLE_OK") >= 0 ? "Auto-start updated." : (err || out);
            } else if (sourceName.indexOf("sched-auto-setup") >= 0) {
                if (out.indexOf("AUTO_ENABLED") >= 0)
                    schedAutoStartToggle.checked = true;
                else if (out.indexOf("AUTO_DISABLED") >= 0)
                    schedAutoStartToggle.checked = false;
            } else if (sourceName.indexOf("sched-load") >= 0) {
                if (out !== "") {
                    try {
                        var parsed = JSON.parse(out);
                        var allSchedules = parsed.schedules || [];
                        var active = [];
                        var archived = [];
                        for (var i = 0; i < allSchedules.length; i++) {
                            if (allSchedules[i]) {
                                if (allSchedules[i].archived) {
                                    archived.push(allSchedules[i]);
                                } else {
                                    active.push(allSchedules[i]);
                                }
                            }
                        }
                        page.schedulerList = active;
                        page.schedulerArchivedList = archived;
                        page.schedulerHistory = parsed.history || [];
                    } catch (e) {
                        page.schedulerList = [];
                        page.schedulerArchivedList = [];
                        page.schedulerHistory = [];
                    }
                }
            } else if (sourceName.indexOf("sched-save") >= 0) {
                page.schedSaving = false;
                page.schedulerStatus = "Schedules saved.";
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
            readonly property string guideText: {
                return translate("<b>Appearance, Language &amp; Notifications Guide:</b><br/>" + "• <b>Appearance:</b> Use the <b>Appearance</b> dropdown to choose <i>Follow system</i>, <i>Light mode</i>, or <i>Dark mode</i> for the chat popup.<br/>" + "• <b>Language:</b> Use the <b>Language</b> dropdown to change the UI language of the chat popup. <i>Follow system language</i> uses your system locale automatically.<br/>" + "• <b>Notification sound:</b> Tick <b>Play sound when AI finishes a response</b> to hear an alert after every reply.<br/>" + "• <b>Interactive guides:</b> Toggle <b>Turn on interactive guides</b> to show/hide these setup cards throughout the settings.<br/>" + "• <b>User Memory:</b> In the <b>Behavior</b> section, enable <b>User Memory</b> and write facts (your name, preferences, context) the AI should always remember — injected into every prompt.<br/>" + "• <b>Schedules:</b> Use the <b>Schedules</b> tool to schedule automated questions. Type <code>/schedule</code> inside any chat to list or create automated prompts.");
            }
            readonly property string providerGuideText: {
                if (openCodeToggle.checked)
                    return translate("<b>OpenCode Setup Guide:</b><br/>" + "1. Select <b>OpenCode Mode (Local Coding Server)</b> under Operating Mode.<br/>" + "2. Scroll down to the <b>OpenCode</b> section and enter the server URL (default: <code>http://127.0.0.1:4096</code>).<br/>" + "3. Click <b>Start Server</b> to launch the local OpenCode server in the background.<br/>" + "4. Click <b>Check Server</b> to verify it is online.<br/>" + "5. Once online, the available providers/models dropdowns will auto-populate.<br/>" + "6. Click <b>Apply</b>/<b>OK</b> to save and start using local coding assistance.");

                var provider = providerBox.currentValue || "openai";
                if (provider === "openai")
                    return translate("<b>OpenAI Setup Guide:</b><br/>" + "1. Get your API key at <b>platform.openai.com → API Keys</b> (starts with <code>sk-</code>).<br/>" + "2. Paste it into the <b>OpenAI key</b> field below.<br/>" + "3. Choose a model from the <b>OpenAI model</b> dropdown or type one (e.g. <code>gpt-4o</code>, <code>gpt-4o-mini</code>).<br/>" + "4. (Optional) Override the base URL only if using a compatible proxy.<br/>" + "5. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "anthropic")
                    return translate("<b>Anthropic Setup Guide:</b><br/>" + "1. Get your API key at <b>console.anthropic.com → API Keys</b> (starts with <code>sk-ant-</code>).<br/>" + "2. Paste it into the <b>Anthropic key</b> field below.<br/>" + "3. Choose a model (e.g. <code>claude-opus-4-5</code>, <code>claude-3-5-sonnet-latest</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "groq")
                    return translate("<b>Groq Setup Guide:</b><br/>" + "1. Get your free API key at <b>console.groq.com → API Keys</b>.<br/>" + "2. Paste it into the <b>Groq key</b> field below.<br/>" + "3. Choose a model (e.g. <code>llama-3.3-70b-versatile</code>, <code>gemma2-9b-it</code>) — Groq inference is extremely fast.<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "deepseek")
                    return translate("<b>DeepSeek Setup Guide:</b><br/>" + "1. Get your API key at <b>platform.deepseek.com → API Keys</b>.<br/>" + "2. Paste it into the <b>DeepSeek key</b> field below.<br/>" + "3. Choose a model (e.g. <code>deepseek-chat</code> or <code>deepseek-reasoner</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "minimax")
                    return translate("<b>MiniMax Setup Guide:</b><br/>" + "1. Get your API key at <b>www.minimaxi.com → API Key</b>.<br/>" + "2. Paste it into the <b>MiniMax key</b> field below.<br/>" + "3. Choose a model (e.g. <code>MiniMax-M2.7</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "fireworks")
                    return translate("<b>Fireworks AI Setup Guide:</b><br/>" + "1. Get your API key at <b>fireworks.ai → Account → API Keys</b>.<br/>" + "2. Paste it into the <b>Fireworks key</b> field below.<br/>" + "3. Choose a model (e.g. <code>accounts/fireworks/models/llama-v3p3-70b-instruct</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "google")
                    return translate("<b>Google Gemini Setup Guide:</b><br/>" + "1. Get your free API key at <b>aistudio.google.com → Get API Key</b>.<br/>" + "2. Paste it into the <b>Google key</b> field below.<br/>" + "3. Choose a model (e.g. <code>gemini-2.5-flash-preview-05-20</code>, <code>gemini-2.0-flash</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "openrouter")
                    return translate("<b>OpenRouter Setup Guide:</b><br/>" + "1. Get your API key at <b>openrouter.ai → Keys</b>.<br/>" + "2. Paste it into the <b>OpenRouter key</b> field below.<br/>" + "3. Choose any model from 100+ providers (e.g. <code>openai/gpt-4o-mini</code>, <code>google/gemini-flash-1.5</code>, <code>openrouter/auto</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "mistral")
                    return translate("<b>Mistral Setup Guide:</b><br/>" + "1. Get your API key at <b>console.mistral.ai → API Keys</b>.<br/>" + "2. Paste it into the <b>Mistral key</b> field below.<br/>" + "3. Choose a model (e.g. <code>mistral-small-latest</code>, <code>mistral-large-latest</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "cloudflare")
                    return translate("<b>Cloudflare Workers AI Setup Guide:</b><br/>" + "1. Log in to <b>dash.cloudflare.com → AI → Workers AI</b>.<br/>" + "2. Copy your <b>Account ID</b> from the right sidebar and replace <code>YOUR_ACCOUNT_ID</code> in the <b>Cloudflare URL</b> field below.<br/>" + "3. Create an API Token (with Workers AI permission) at <b>dash.cloudflare.com → Profile → API Tokens</b> and paste it into the <b>Cloudflare key</b> field.<br/>" + "4. Choose a model (e.g. <code>@cf/meta/llama-3.1-8b-instruct</code>).<br/>" + "5. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "nvidia")
                    return translate("<b>NVIDIA NIM Setup Guide:</b><br/>" + "1. Get your API key at <b>build.nvidia.com → Get API Key</b>.<br/>" + "2. Paste it into the <b>NVIDIA key</b> field below.<br/>" + "3. Choose a NIM model (e.g. <code>meta/llama-3.1-70b-instruct</code>, <code>nvidia/nemotron-4-340b-instruct</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "huggingface")
                    return translate("<b>Hugging Face Router Setup Guide:</b><br/>" + "1. Get your access token at <b>huggingface.co → Settings → Access Tokens</b> (use a token with Inference permissions).<br/>" + "2. Paste it into the <b>Hugging Face key</b> field below.<br/>" + "3. Enter a supported inference model (e.g. <code>openai/gpt-oss-120b:groq</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "xai")
                    return translate("<b>xAI (Grok) Setup Guide:</b><br/>" + "1. Get your API key at <b>console.x.ai → API Keys</b>.<br/>" + "2. Paste it into the <b>xAI key</b> field below.<br/>" + "3. Choose a model (e.g. <code>grok-3-mini</code>, <code>grok-2-latest</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "lmstudio")
                    return translate("<b>LM Studio Setup Guide:</b><br/>" + "1. Download and open <b>LM Studio</b> (lmstudio.ai) — no API key needed.<br/>" + "2. In LM Studio, go to the <b>Local Server</b> tab and load a model.<br/>" + "3. Click <b>Start Server</b> in LM Studio (default URL: <code>http://localhost:1234/v1</code>).<br/>" + "4. Enter the loaded model name in the <b>LM Studio model</b> field below.<br/>" + "5. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "local")
                    return translate("<b>Local Server (OpenAI-compatible) Setup Guide:</b><br/>" + "1. Start your local server (e.g. <b>vLLM</b>, <b>llama.cpp</b>, <b>Jan</b>) — no API key needed.<br/>" + "2. Enter the server's base URL in the <b>Local URL</b> field below (e.g. <code>http://localhost:8000/v1</code>).<br/>" + "3. Enter the model identifier your server is serving in the <b>Local model</b> field.<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "ollama")
                    return translate("<b>Ollama Setup Guide:</b><br/>" + "1. Install Ollama from <b>ollama.com</b> and run it — no API key needed.<br/>" + "2. Pull a model by running <code>ollama pull llama3.2</code> in a terminal.<br/>" + "3. Ollama starts automatically (default URL: <code>http://localhost:11434</code>).<br/>" + "4. Verify/update the <b>Ollama URL</b> field below and enter your model name (e.g. <code>llama3.2</code>).<br/>" + "5. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "litellm")
                    return translate("<b>LiteLLM Proxy Setup Guide:</b><br/>" + "1. Install LiteLLM: <code>pip install litellm</code> — no API key needed for the proxy itself.<br/>" + "2. Start your proxy: <code>litellm --model ollama/llama3.2</code> (or your preferred model).<br/>" + "3. Enter the proxy URL in the <b>LiteLLM URL</b> field below (default: <code>http://localhost:4000</code>).<br/>" + "4. Enter the model identifier in the <b>LiteLLM model</b> field.<br/>" + "5. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "qwen")
                    return translate("<b>Qwen (Alibaba Cloud) Setup Guide:</b><br/>" + "1. Register at <b>dashscope.aliyuncs.com</b> and go to <b>API Keys</b>.<br/>" + "2. Paste your key into the <b>Qwen key</b> field below.<br/>" + "3. Choose a model (e.g. <code>qwen-max</code>, <code>qwen-plus</code>, <code>qwen-turbo</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "moonshot")
                    return translate("<b>Moonshot AI (Kimi) Setup Guide:</b><br/>" + "1. Get your API key at <b>platform.moonshot.cn → API Keys</b>.<br/>" + "2. Paste it into the <b>Moonshot key</b> field below.<br/>" + "3. Choose a model (e.g. <code>moonshot-v1-8k</code>, <code>moonshot-v1-32k</code>, <code>moonshot-v1-128k</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "mimo")
                    return translate("<b>MiMo (Xiaomi) Setup Guide:</b><br/>" + "1. Get access at <b>api.xiaomimimo.com</b> and copy your API key.<br/>" + "2. Paste it into the <b>MiMo key</b> field below.<br/>" + "3. Choose a model (e.g. <code>mimo-v2-pro</code>, <code>mimo-v2</code>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
                else if (provider === "maritaca")
                    return translate("<b>Maritaca AI (Sabiá) Setup Guide:</b><br/>" + "1. Get your API key at <b>chat.maritaca.ai → Settings → API Keys</b>.<br/>" + "2. Paste it into the <b>Maritaca key</b> field below.<br/>" + "3. Choose a model (e.g. <code>sabia-4</code> — optimised for Portuguese).<br/>" + "4. The default URL <code>https://chat.maritaca.ai/api</code> is correct — do not change it.<br/>" + "5. Click <b>Apply</b>/<b>OK</b> to save.");
                return translate("<b>Provider Setup Guide:</b> Select a provider from the <b>Default provider</b> dropdown above to see setup instructions.");
            }
            readonly property string apiGuideText: {
                var storageIdx = storageModeCombo.currentIndex;
                if (storageIdx === 0)
                    return translate("<b>API Key Storage Guide:</b><br/>" + "• Current mode: <b>🔒 Session-only memory</b>.<br/>" + "• Enter your API keys in the provider fields below. No extra steps needed — keys are held in memory only.<br/>" + "• Keys are wiped completely when the widget closes. You must re-enter them every session.");
                else if (storageIdx === 1)
                    return translate("<b>API Key Storage Guide:</b><br/>" + "• Current mode: <b>📄 Plain config file</b> (unencrypted).<br/>" + "• Enter your keys in the provider fields below, then click <b>Apply</b>/<b>OK</b> to save them to <code>~/.config/kdeaichatrc</code>.<br/>" + "• (Optional) Click <b>Reload from config file</b> if you edited the file externally.<br/>" + "• (Optional) Click <b>Open config file</b> to view or paste keys directly into the file.<br/>" + "• Security: Keys are stored as plain text — suitable for single-user machines only.");
                else if (storageIdx === 2)
                    return translate("<b>API Key Storage Guide:</b><br/>" + "• Current mode: <b>🔑 KWallet</b> (encrypted).<br/>" + "• Click <b>Detect wallets</b> to find available KDE wallets.<br/>" + "• If none are found, click <b>Create wallet</b> — KWallet will prompt for a password to create one.<br/>" + "• Select your wallet from the <b>Wallet name</b> dropdown, enter your keys, then click <b>Sync to KWallet</b>.<br/>" + "• (Optional) Click <b>Launch KWalletManager</b> to inspect or manage your wallet via the system app.<br/>" + "• Security: Keys are fully encrypted. Best for shared or multi-user systems.");
                return "";
            }
            readonly property string otherSettingsGuideText: {
                return translate("<b>Other Settings Guide:</b><br/>• <b>App name:</b> Change the display name shown in the widget title bar. After clicking Apply/OK, restart the shell with the command shown to apply it.<br/>• <b>System prompt:</b> Set a default system instruction for every chat session (e.g. <i>\"You are a helpful Linux assistant.\"</i>). Leave blank to use the default.<br/>• <b>Chat storage path (beta):</b> Choose a folder to save your chat history. Click <b>Browse...</b> to pick a folder, or type a path directly. History is saved as <code>kdeaichat_history.json</code> inside that folder. Default is <code>~/.config</code>.<br/>• <b>Reset to defaults:</b> Click <b>Reset to defaults</b> to restore all settings to their original values.");
            }
            readonly property string schedulerGuideText: {
                if (!schedulerMasterSwitch.checked) {
                    return translate("<b>Schedules Guide:</b><br/>" +
                        "The scheduler runs in the background. At the time you choose, it automatically sends a message into your chat and the AI replies.<br/><br/>" +
                        "• <b>Status: Stopped</b>.<br/>" +
                        "• <b>Action:</b> Toggle the <b>Scheduler switch</b> below to <b>ON</b> to boot the background daemon.");
                }

                if (!page.schedulerDaemonRunning) {
                    return translate("<b>Schedules Guide:</b><br/>" +
                        "• <b>Status: Starting up...</b><br/>" +
                        "• The scheduler daemon is starting in the background. Once initialized, the status indicator will show <b>Active</b>.<br/>" +
                        "• (Optional) Make sure to toggle <b>Auto-start at login</b> to <b>ON</b> if you want automated schedules to trigger even when you don't open settings.");
                }

                var count = page.schedulerList.length;
                if (count === 0) {
                    return translate("<b>Schedules Guide:</b><br/>" +
                        "• <b>Status: Active &amp; running!</b><br/>" +
                        "• The scheduler is connected and monitoring. But you have <b>0 schedules configured</b>.<br/>" +
                        "• <b>Action:</b> Click <b>Create Schedule</b> below to set up your first automated daily or one-time prompt!");
                }

                var enabledCount = 0;
                for (var i = 0; i < count; i++) {
                    if (page.schedulerList[i] && page.schedulerList[i].enabled) {
                        enabledCount++;
                    }
                }

                return translate("<b>Schedules Guide:</b><br/>• <b>Status: Active &amp; running!</b><br/>• You have <b>%1 schedule(s) configured</b> (%2 enabled).<br/>• The background service will run automatically. Click <b>Manage Schedules</b> to edit or delete any task.<br/>• <i>Pro-Tip:</i> You can also schedule prompts directly from the chat box by typing <code>/schedule</code>!").arg(count).arg(enabledCount);
            }


            x: 0
            clip: true
            scale: page.configZoom
            transformOrigin: Item.TopLeft
            //* Single column: wideMode uses implicitWidth for grid width and centers it, which clips labels in narrow config dialogs.
            wideMode: false
            width: boundedWidth

            RowLayout {
                visible: showGuidesToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.gridUnit
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: translate("General Guide")

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: guideLayout.implicitHeight + Kirigami.Units.gridUnit
                    radius: 5
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    border.width: 1

                    RowLayout {
                        id: guideLayout

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
                            text: formLayout.guideText
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                            color: Kirigami.Theme.textColor
                        }

                    }

                }

            }

            ColumnLayout {
                Kirigami.FormData.label: translate("Appearance:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.ComboBox {
                    id: appearanceModeCombo

                    Layout.fillWidth: true
                    Layout.maximumWidth: formLayout.fieldMaxWidth
                    model: [translate("Follow system"), translate("Light mode"), translate("Dark mode")]
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    Layout.maximumWidth: formLayout.fieldMaxWidth
                    wrapMode: Text.Wrap
                    opacity: 0.72
                    font: Kirigami.Theme.smallFont
                    text: translate("Choose whether the chat widget follows your system theme or is pinned to light/dark mode.")
                }

            }

            ColumnLayout {
                Kirigami.FormData.label: translate("Language:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.ComboBox {
                    id: languageCombo

                    Layout.fillWidth: true
                    Layout.maximumWidth: formLayout.fieldMaxWidth
                    textRole: "text"
                    valueRole: "value"
                    model: [{
                        "value": "",
                        "text": translate("Choose system language")
                    }, {
                        "value": "en",
                        "text": "English"
                    }, {
                        "value": "ar",
                        "text": "Arabic (عربي)"
                    }, {
                        "value": "zh",
                        "text": "Chinese (中文)"
                    }, {
                        "value": "fr",
                        "text": "French (Français)"
                    }, {
                        "value": "de",
                        "text": "German (Deutsch)"
                    }, {
                        "value": "hi",
                        "text": "Hindi (हिंदी)"
                    }, {
                        "value": "it",
                        "text": "Italian (Italiano)"
                    }, {
                        "value": "ja",
                        "text": "Japanese (日本語)"
                    }, {
                        "value": "pt",
                        "text": "Portuguese (Português)"
                    }, {
                        "value": "ru",
                        "text": "Russian (Русский)"
                    }, {
                        "value": "es",
                        "text": "Spanish (Español)"
                    }]
                    currentIndex: {
                        for (var i = 0; i < model.length; i++) {
                            if (model[i].value === cfg_language)
                                return i;

                        }
                        return 0;
                    }
                    onActivated: {
                        cfg_language = currentValue;
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    Layout.maximumWidth: formLayout.fieldMaxWidth
                    wrapMode: Text.Wrap
                    opacity: 0.72
                    font: Kirigami.Theme.smallFont
                    text: translate("Choose the display language for the widget interface.")
                }

                QQC2.Label {
                    visible: !page.isLanguageEnglish
                    Layout.fillWidth: true
                    Layout.maximumWidth: formLayout.fieldMaxWidth
                    wrapMode: Text.Wrap
                    color: Kirigami.Theme.neutralColor
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    text: translate("This plasmoid is being built in English so there maybe errors in translation. Switch to English language if any problem arises.")
                }

            }

            QQC2.CheckBox {
                id: playSoundToggle

                Kirigami.FormData.label: translate("Notification sound:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Play sound when AI finishes a response")
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: translate("Plays a sound notification when the AI assistant completes its response.")
            }

            QQC2.CheckBox {
                id: showGuidesToggle

                Kirigami.FormData.label: translate("Interactive Guides:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Turn on interactive guides (Recommended)")
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: translate("Displays detailed setup and configuration guides at the top of the settings page.")
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: translate("Provider & Mode")
            }

            RowLayout {
                visible: showGuidesToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.gridUnit
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: openCodeToggle.checked ? translate("OpenCode Guide") : translate("Provider Guide")

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: providerGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                    radius: 5
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    border.width: 1

                    RowLayout {
                        id: providerGuideLayout

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
                            text: formLayout.providerGuideText
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                            color: Kirigami.Theme.textColor
                        }

                    }

                }

            }

            QQC2.CheckBox {
                id: normalModeToggle

                Kirigami.FormData.label: translate("Operating mode:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Normal Mode (Cloud & Local API Providers)")
                checked: !openCodeToggle.checked
                onClicked: {
                    if (checked)
                        openCodeToggle.checked = false;
                    else
                        checked = true;
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: translate("Use cloud-based (OpenAI, Anthropic, Gemini, Groq, DeepSeek, etc.) or local API providers (Ollama, LM Studio, LiteLLM) to power your chat. Select your provider and configure API keys below.")
            }

            QQC2.CheckBox {
                id: openCodeToggle

                Kirigami.FormData.label: translate("")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("OpenCode Mode (Local Coding Server)")
                onClicked: {
                    if (checked)
                        normalModeToggle.checked = false;
                    else
                        checked = true;
                }
                onCheckedChanged: {
                    if (checked) {
                        normalModeToggle.checked = false;
                        checkAndAutoStartOpenCodeServer();
                    } else {
                        normalModeToggle.checked = true;
                        if (cfg_keyStorageMode === 2 && availableWalletNames.length === 0)
                            detectWallets();

                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: translate("Use your local offline OpenCode agent server for secure, private developer assistance and system scripting without sending data to the cloud.")
            }

            QQC2.ComboBox {
                id: providerBox

                visible: !openCodeToggle.checked
                Kirigami.FormData.label: translate("Default provider:")
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
                    "text": "Fireworks"
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
                    "text": "Hugging Face"
                }, {
                    "value": "xai",
                    "text": "xAI Grok"
                }, {
                    "value": "lmstudio",
                    "text": "LM Studio"
                }, {
                    "value": "local",
                    "text": "Local / OpenAI-compatible"
                }, {
                    "value": "ollama",
                    "text": "Ollama"
                }, {
                    "value": "litellm",
                    "text": "LiteLLM"
                }, {
                    "value": "qwen",
                    "text": "Alibaba Qwen"
                }, {
                    "value": "moonshot",
                    "text": "Moonshot AI"
                }, {
                    "value": "mimo",
                    "text": "Xiaomi MiMo"
                }, {
                    "value": "maritaca",
                    "text": "Maritaca AI"
                }]
                currentIndex: {
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].value === cfg_provider)
                            return i;

                    }
                    return 0;
                }
                onActivated: {
                    cfg_provider = currentValue;
                    providerModelCandidates = [];
                    discoveryStatus = "";
                }
            }

            QQC2.Label {
                visible: !openCodeToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: translate("Select the AI backend provider that you want to use for standard chat modes.")
            }

            QQC2.Button {
                visible: !openCodeToggle.checked
                Kirigami.FormData.label: translate("Model discovery:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Refresh")
                enabled: !providerNeedsApiKey(providerBox.currentValue || "openai") || providerHasConfiguredKey(providerBox.currentValue || "openai")
                onClicked: refreshCurrentProviderModels()
            }

            QQC2.Label {
                visible: !openCodeToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: translate("Queries the selected provider API to dynamically fetch and populate the list of available model names.")
            }

            QQC2.BusyIndicator {
                visible: !openCodeToggle.checked && openCodeBusy
                running: visible
                Kirigami.FormData.label: translate("Loading:")
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
                Kirigami.FormData.label: translate("Model:")
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
                Kirigami.FormData.label: translate("Status:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: {
                    if (discoveryStatus.indexOf("check failed") >= 0 || discoveryStatus.indexOf("error") >= 0 || discoveryStatus.indexOf("Network error") >= 0)
                        return discoveryStatus + (openCodeToggle.checked ? " → Click \"Start server\" or \"Refresh\" to retry." : "");

                    return discoveryStatus;
                }
                wrapMode: Text.Wrap
                opacity: 0.8
                color: (discoveryStatus.indexOf("check failed") >= 0 || discoveryStatus.indexOf("error") >= 0 || discoveryStatus.indexOf("Network error") >= 0) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            }

            Kirigami.Separator {
                visible: openCodeToggle.checked
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: translate("OpenCode")
            }

            QQC2.TextField {
                id: openCodeUrlField

                visible: openCodeToggle.checked
                Kirigami.FormData.label: translate("OpenCode URL:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://127.0.0.1:4096/v1"
            }

            QQC2.Label {
                visible: openCodeToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: translate("Address of the running OpenCode server. Default: http://127.0.0.1:4096/v1.")
            }

            QQC2.CheckBox {
                id: autoStartOpenCodeToggle

                visible: openCodeToggle.checked
                Kirigami.FormData.label: translate("Auto-start server:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Automatically start OpenCode when settings open")
            }

            QQC2.Label {
                visible: openCodeToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: translate("Runs the start command automatically each time the settings panel is opened (uses the Start command below).")
            }

            Flow {
                visible: openCodeToggle.checked
                Kirigami.FormData.label: translate("OpenCode server:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: translate("Start server")
                    enabled: !openCodeBusy
                    onClicked: {
                        discoveryStatus = "Running OpenCode start command...";
                        var cmd = "sh -lc '" + shellEscape(openCodeStartCommandField.text || "nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 & echo OpenCode start command launched.") + "'";
                        utilityDs.connectSource(cmd + " #opencode-start");
                    }
                }

                QQC2.Button {
                    text: translate("Check / Refresh")
                    enabled: !openCodeBusy
                    onClicked: refreshOpenCodeDiscovery()
                }

                QQC2.Button {
                    text: translate("Kill server")
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
                Kirigami.FormData.label: translate("Loading:")
            }

            QQC2.ComboBox {
                id: openCodeProvidersCombo

                visible: openCodeToggle.checked && openCodeProviderCandidates.length > 0
                Kirigami.FormData.label: translate("Providers:")
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
                Kirigami.FormData.label: translate("OpenCode models:")
                text: translate("Refresh models")
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
                Kirigami.FormData.label: translate("Model:")
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

                Kirigami.FormData.label: translate("OpenAI URL:")
                visible: page.providerEnabled("openai")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.openai.com/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("OpenAI key:")
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
                    id: apiKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("openai")
                Kirigami.FormData.label: translate("OpenAI model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the OpenAI API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: modelField

                Kirigami.FormData.label: translate("OpenAI model:")
                visible: page.providerModelVisible("openai") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "gpt-4o-mini"
                text: activeProviderModelValue()
                onTextChanged: setActiveProviderModelValue(text)
            }

            RowLayout {
                Kirigami.FormData.label: translate("Anthropic key:")
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
                    id: anthropicKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("anthropic")
                Kirigami.FormData.label: translate("Anthropic model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Anthropic API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: anthropicModelField

                Kirigami.FormData.label: translate("Anthropic model:")
                visible: page.providerModelVisible("anthropic") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "claude-3-5-sonnet-latest"
            }

            QQC2.TextField {
                id: groqBaseUrlField

                Kirigami.FormData.label: translate("Groq URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.groq.com/openai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("Groq key:")
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
                    id: groqKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("groq")
                Kirigami.FormData.label: translate("Groq model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Groq API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: groqModelField

                Kirigami.FormData.label: translate("Groq model:")
                visible: page.providerModelVisible("groq") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "llama-3.3-70b-versatile"
            }

            QQC2.TextField {
                id: deepSeekBaseUrlField

                Kirigami.FormData.label: translate("DeepSeek URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.deepseek.com"
            }

            RowLayout {
                Kirigami.FormData.label: translate("DeepSeek key:")
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
                    id: deepSeekKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("deepseek")
                Kirigami.FormData.label: translate("DeepSeek model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the DeepSeek API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: deepSeekModelField

                Kirigami.FormData.label: translate("DeepSeek model:")
                visible: page.providerModelVisible("deepseek") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "deepseek-v4-pro"
            }

            QQC2.TextField {
                id: miniMaxBaseUrlField

                Kirigami.FormData.label: translate("MiniMax URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.minimax.io/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("MiniMax key:")
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
                    id: miniMaxKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("minimax")
                Kirigami.FormData.label: translate("MiniMax model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the MiniMax API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: miniMaxModelField

                Kirigami.FormData.label: translate("MiniMax model:")
                visible: page.providerModelVisible("minimax") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "MiniMax-M2.7"
            }

            QQC2.TextField {
                id: fireworksBaseUrlField

                Kirigami.FormData.label: translate("Fireworks URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.fireworks.ai/inference/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("Fireworks key:")
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
                    id: fireworksKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("fireworks")
                Kirigami.FormData.label: translate("Fireworks model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Fireworks API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: fireworksModelField

                Kirigami.FormData.label: translate("Fireworks model:")
                visible: page.providerModelVisible("fireworks") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "accounts/fireworks/models/llama-v3p3-70b-instruct"
            }

            QQC2.TextField {
                id: googleBaseUrlField

                Kirigami.FormData.label: translate("Google URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://generativelanguage.googleapis.com/v1beta/openai/"
            }

            RowLayout {
                Kirigami.FormData.label: translate("Google key:")
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
                    id: googleKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("google")
                Kirigami.FormData.label: translate("Google model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Gemini API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: googleModelField

                Kirigami.FormData.label: translate("Google model:")
                visible: page.providerModelVisible("google") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "gemini-3-flash-preview"
            }

            QQC2.TextField {
                id: openRouterBaseUrlField

                Kirigami.FormData.label: translate("OpenRouter URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://openrouter.ai/api/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("OpenRouter key:")
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
                    id: openRouterKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("openrouter")
                Kirigami.FormData.label: translate("OpenRouter model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the OpenRouter API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: openRouterModelField

                Kirigami.FormData.label: translate("OpenRouter model:")
                visible: page.providerModelVisible("openrouter") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "openai/gpt-4o-mini"
            }

            QQC2.TextField {
                id: mistralBaseUrlField

                Kirigami.FormData.label: translate("Mistral URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.mistral.ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("Mistral key:")
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
                    id: mistralKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("mistral")
                Kirigami.FormData.label: translate("Mistral model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Mistral API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: mistralModelField

                Kirigami.FormData.label: translate("Mistral model:")
                visible: page.providerModelVisible("mistral") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "mistral-small-latest"
            }

            QQC2.TextField {
                id: cloudflareBaseUrlField

                Kirigami.FormData.label: translate("Cloudflare URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("Cloudflare key:")
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
                    id: cloudflareKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("cloudflare")
                Kirigami.FormData.label: translate("Cloudflare model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Cloudflare API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: cloudflareModelField

                Kirigami.FormData.label: translate("Cloudflare model:")
                visible: page.providerModelVisible("cloudflare") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "@cf/meta/llama-3.1-8b-instruct"
            }

            QQC2.TextField {
                id: nvidiaBaseUrlField

                Kirigami.FormData.label: translate("NVIDIA NIM URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://integrate.api.nvidia.com/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("NVIDIA NIM key:")
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
                    id: nvidiaKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("nvidia")
                Kirigami.FormData.label: translate("NVIDIA NIM model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the NVIDIA NIM API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: nvidiaModelField

                Kirigami.FormData.label: translate("NVIDIA NIM model:")
                visible: page.providerModelVisible("nvidia") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "meta/llama-3.1-70b-instruct"
            }

            QQC2.TextField {
                id: huggingFaceBaseUrlField

                Kirigami.FormData.label: translate("HF URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://router.huggingface.co/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("HF token:")
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
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("huggingface")
                Kirigami.FormData.label: translate("HF model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Hugging Face token first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: huggingFaceModelField

                Kirigami.FormData.label: translate("HF model:")
                visible: page.providerModelVisible("huggingface") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "openai/gpt-oss-120b:groq"
            }

            QQC2.TextField {
                id: xaiBaseUrlField

                Kirigami.FormData.label: translate("xAI URL:")
                visible: false
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.x.ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("xAI key:")
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
                    id: xaiKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("xai")
                Kirigami.FormData.label: translate("xAI model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the xAI API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: xaiModelField

                Kirigami.FormData.label: translate("xAI model:")
                visible: page.providerModelVisible("xai") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "grok-2-latest"
            }

            QQC2.TextField {
                id: lmStudioBaseUrlField

                Kirigami.FormData.label: translate("LM Studio URL:")
                visible: page.providerEnabled("lmstudio")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:1234/v1"
            }

            QQC2.TextField {
                id: lmStudioModelField

                Kirigami.FormData.label: translate("LM Studio model:")
                visible: page.providerModelVisible("lmstudio") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "Load a model in LM Studio, then refresh models"
            }

            QQC2.TextField {
                id: localBaseUrlField

                Kirigami.FormData.label: translate("Local URL:")
                visible: page.providerEnabled("local")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:11434/v1"
            }

            QQC2.TextField {
                id: localModelField

                Kirigami.FormData.label: translate("Local model:")
                visible: page.providerModelVisible("local") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "llama3.2"
            }

            QQC2.TextField {
                id: ollamaBaseUrlField

                Kirigami.FormData.label: translate("Ollama URL:")
                visible: page.providerEnabled("ollama")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:11434/v1"
            }

            QQC2.TextField {
                id: ollamaModelField

                Kirigami.FormData.label: translate("Ollama model:")
                visible: page.providerModelVisible("ollama") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "llama3.2"
            }

            QQC2.TextField {
                id: litellmBaseUrlField

                Kirigami.FormData.label: translate("LiteLLM URL:")
                visible: page.providerEnabled("litellm")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "http://localhost:4000/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("LiteLLM key:")
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
                    id: litellmKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("litellm")
                Kirigami.FormData.label: translate("LiteLLM model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the LiteLLM API key first if required, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: litellmModelField

                Kirigami.FormData.label: translate("LiteLLM model:")
                visible: page.providerModelVisible("litellm") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "gpt-4o-mini"
            }

            // ── Qwen (Alibaba Cloud) ──
            QQC2.TextField {
                id: qwenBaseUrlField

                visible: false
                Kirigami.FormData.label: translate("Qwen URL:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("Qwen key:")
                visible: page.providerEnabled("qwen")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: qwenApiKeyField

                    Layout.fillWidth: true
                    Layout.maximumWidth: parent.width - qwenKeyShowHide.implicitWidth - parent.spacing
                    echoMode: qwenKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("qwen", text);
                        page.refreshIfActiveProvider("qwen");
                    }
                }

                QQC2.Button {
                    id: qwenKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerEnabled("qwen")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: "Get your API key at dashscope.aliyuncs.com. Supports qwen-max, qwen-plus, qwen-turbo."
            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("qwen")
                Kirigami.FormData.label: translate("Qwen model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Qwen API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: qwenModelField

                Kirigami.FormData.label: translate("Qwen model:")
                visible: page.providerModelVisible("qwen") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "qwen-max"
            }

            // ── Moonshot AI ──
            QQC2.TextField {
                id: moonshotBaseUrlField

                visible: false
                Kirigami.FormData.label: translate("Moonshot URL:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.moonshot.ai/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("Moonshot key:")
                visible: page.providerEnabled("moonshot")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: moonshotApiKeyField

                    Layout.fillWidth: true
                    Layout.maximumWidth: parent.width - moonshotKeyShowHide.implicitWidth - parent.spacing
                    echoMode: moonshotKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("moonshot", text);
                        page.refreshIfActiveProvider("moonshot");
                    }
                }

                QQC2.Button {
                    id: moonshotKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerEnabled("moonshot")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: "Get your API key at platform.moonshot.ai. Supports moonshot-v1-8k, moonshot-v1-32k."
            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("moonshot")
                Kirigami.FormData.label: translate("Moonshot model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Moonshot API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: moonshotModelField

                Kirigami.FormData.label: translate("Moonshot model:")
                visible: page.providerModelVisible("moonshot") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "moonshot-v1-8k"
            }

            // ── Xiaomi MiMo ──
            QQC2.TextField {
                id: mimoBaseUrlField

                visible: false
                Kirigami.FormData.label: translate("MiMo URL:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://api.xiaomimimo.com/v1"
            }

            RowLayout {
                Kirigami.FormData.label: translate("MiMo key:")
                visible: page.providerEnabled("mimo")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: mimoApiKeyField

                    Layout.fillWidth: true
                    Layout.maximumWidth: parent.width - mimoKeyShowHide.implicitWidth - parent.spacing
                    echoMode: mimoKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("mimo", text);
                        page.refreshIfActiveProvider("mimo");
                    }
                }

                QQC2.Button {
                    id: mimoKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerEnabled("mimo")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: "Get your API key at xiaomimimo.com. Supports mimo-v2-pro and other MiMo models."
            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("mimo")
                Kirigami.FormData.label: translate("MiMo model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the MiMo API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: mimoModelField

                Kirigami.FormData.label: translate("MiMo model:")
                visible: page.providerModelVisible("mimo") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "mimo-v2-pro"
            }

            // ── Maritaca AI ──
            QQC2.TextField {
                id: maritacaBaseUrlField

                visible: false
                Kirigami.FormData.label: translate("Maritaca URL:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "https://chat.maritaca.ai/api"
            }

            RowLayout {
                Kirigami.FormData.label: translate("Maritaca key:")
                visible: page.providerEnabled("maritaca")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    id: maritacaApiKeyField

                    Layout.fillWidth: true
                    Layout.maximumWidth: parent.width - maritacaKeyShowHide.implicitWidth - parent.spacing
                    echoMode: maritacaKeyShowHide.checked ? TextInput.Normal : TextInput.Password
                    onEditingFinished: {
                        page.saveKey("maritaca", text);
                        page.refreshIfActiveProvider("maritaca");
                    }
                }

                QQC2.Button {
                    id: maritacaKeyShowHide

                    checkable: true
                    text: checked ? translate("Hide") : translate("Show")
                }

            }

            QQC2.Label {
                visible: page.providerEnabled("maritaca")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: "Get your API key at chat.maritaca.ai. Default model: sabia-4 (Portuguese-optimised)."
            }

            QQC2.Label {
                visible: page.providerNeedsKeyHintVisible("maritaca")
                Kirigami.FormData.label: translate("Maritaca model:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Enter the Maritaca API key first, then refresh models or type a model name.")
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.TextField {
                id: maritacaModelField

                Kirigami.FormData.label: translate("Maritaca model:")
                visible: page.providerModelVisible("maritaca") && (false)
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                placeholderText: "sabia-4"
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: translate("Behavior")
            }

            QQC2.ScrollView {
                id: systemPromptScrollView

                Kirigami.FormData.label: translate("System prompt:")
                implicitHeight: Kirigami.Units.gridUnit * 5
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                Layout.maximumHeight: Kirigami.Units.gridUnit * 5
                clip: true

                QQC2.TextArea {
                    id: systemPromptArea

                    width: systemPromptScrollView.availableWidth
                    wrapMode: Text.Wrap
                    placeholderText: "You are KDE AI Chat, a precise and helpful assistant."
                    background: null
                    padding: Kirigami.Units.smallSpacing + 2
                }

                background: Rectangle {
                    color: Kirigami.Theme.backgroundColor
                    radius: 4
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                    border.width: 1
                }

            }

            QQC2.Label {
                Kirigami.FormData.label: translate("")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: "Sets a default instruction sent to the AI at the start of every conversation. Leave blank for the built-in default."
            }

            QQC2.CheckBox {
                id: memoryEnabledToggle

                Kirigami.FormData.label: translate("User Memory:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: memoryEnabledToggle.checked ? "Enabled — memory is injected into every prompt" : "Disabled"
            }

            QQC2.Label {
                Kirigami.FormData.label: translate("")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: "Write facts you want the AI to always remember — your name, preferences, context. Injected at the start of every prompt when enabled."
            }

            QQC2.ScrollView {
                id: userMemoryScrollView

                visible: memoryEnabledToggle.checked
                implicitHeight: Kirigami.Units.gridUnit * 6
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                Layout.preferredHeight: Kirigami.Units.gridUnit * 6
                Layout.maximumHeight: Kirigami.Units.gridUnit * 6
                clip: true

                QQC2.TextArea {
                    id: userMemoryArea

                    width: userMemoryScrollView.availableWidth
                    wrapMode: Text.Wrap
                    placeholderText: "E.g., My name is Alex. I use KDE Plasma 6. I prefer Python for scripting. Always be concise."
                    background: null
                    padding: Kirigami.Units.smallSpacing + 2
                }

                background: Rectangle {
                    color: Kirigami.Theme.backgroundColor
                    radius: 4
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                    border.width: 1
                }

            }

            QQC2.Label {
                visible: memoryEnabledToggle.checked
                Kirigami.FormData.label: translate("")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: "Memory is saved with your settings (Apply/OK). It persists across sessions and is prepended to the system prompt."
            }

            Kirigami.Separator {
                visible: !openCodeToggle.checked
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: translate("API Key Storage")
            }

            RowLayout {
                visible: !openCodeToggle.checked && showGuidesToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.gridUnit
                Kirigami.FormData.label: translate("Storage Guide")

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: apiGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                    radius: 5
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    border.width: 1

                    RowLayout {
                        id: apiGuideLayout

                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.gridUnit * 0.6
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "security-high"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                            Layout.alignment: Qt.AlignTop
                        }

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: formLayout.apiGuideText
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                            color: Kirigami.Theme.textColor
                        }

                    }

                }

            }

            QQC2.Label {
                visible: !openCodeToggle.checked
                Kirigami.FormData.label: translate("Storage mode:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Choose how your API keys are stored between sessions:"
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.ComboBox {
                id: storageModeCombo

                visible: !openCodeToggle.checked
                Kirigami.FormData.label: translate("Storage mode:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                model: ["🔒 Session only (forget keys on close)", "📄 Plain config (save to ~/.config/kdeaichatrc)", "🔑 KWallet (secure encrypted storage)"]
                onCurrentIndexChanged: {
                    // Guard: do not write anything during KCM initialisation;
                    // cfg_ aliases may not be populated yet at that point.
                    if (!page.pageReady)
                        return ;

                    keyringStatus = "";
                    if (currentIndex === 1) {
                        page.syncKeysToDisk();
                        keyringStatus = "Switched to Plain Config. Current keys synced to config file.";
                    } else if (currentIndex === 2) {
                        if (availableWalletNames.length === 0)
                            detectWallets();

                    }
                }
            }

            RowLayout {
                visible: !openCodeToggle.checked && storageModeCombo.currentIndex === 1
                Kirigami.FormData.label: translate("Config actions:")
                Layout.fillWidth: true

                QQC2.Button {
                    text: "Reload from config file"
                    onClicked: loadKeysFromPlainConfig()
                }

                QQC2.Button {
                    text: "Open config file"
                    onClicked: writeKeysToDiskAndOpen()
                }

            }

            QQC2.Label {
                visible: !openCodeToggle.checked && storageModeCombo.currentIndex === 2
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "Keys are encrypted and stored via DBus in your system KWallet. Recommended for shared or multi-user machines."
                wrapMode: Text.Wrap
                opacity: 0.75
            }

            QQC2.ComboBox {
                visible: !openCodeToggle.checked && kwalletModeActive && availableWalletNames.length > 0
                Kirigami.FormData.label: translate("Wallet name:")
                Layout.fillWidth: true
                model: availableWalletNames
                currentIndex: availableWalletNames.indexOf(walletNameField.text)
                onActivated: {
                    if (currentIndex >= 0)
                        walletNameField.text = currentText;

                }
            }

            QQC2.TextField {
                visible: !openCodeToggle.checked && kwalletModeActive && availableWalletNames.length === 0
                Kirigami.FormData.label: translate("Wallet name:")
                Layout.fillWidth: true
                text: walletNameField.text
                placeholderText: "kdewallet"
                onTextChanged: walletNameField.text = text
            }

            QQC2.Label {
                visible: !openCodeToggle.checked && kwalletModeActive && availableWalletNames.length > 0
                Kirigami.FormData.label: translate("Detected wallets:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: availableWalletNames.join(", ")
                wrapMode: Text.Wrap
                opacity: 0.8
            }

            QQC2.Label {
                visible: !openCodeToggle.checked && kwalletModeActive
                Kirigami.FormData.label: translate("Wallet info:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: "KWallet controls wallet creation and password policy. A new wallet name may trigger KDE to create or unlock that wallet, depending on your system wallet settings."
                wrapMode: Text.Wrap
                opacity: 0.8
            }

            RowLayout {
                visible: !openCodeToggle.checked && kwalletModeActive
                Kirigami.FormData.label: translate("Wallet actions:")
                Layout.fillWidth: true

                QQC2.Button {
                    text: "Detect wallets"
                    enabled: !keyringBusy
                    onClicked: detectWallets()
                }

                QQC2.Button {
                    text: "Launch KWalletManager"
                    onClicked: {
                        utilityDs.connectSource("kwalletmanager6 || kwalletmanager5 || kwalletmanager #launch-kwallet");
                    }
                }

                QQC2.Button {
                    text: "Create wallet"
                    visible: availableWalletNames.length === 0
                    enabled: !keyringBusy
                    onClicked: {
                        cancelKeyringOps();
                        var walletName = effectiveWalletName();
                        keyringStatus = "Requesting wallet creation/open: " + walletName + "...";
                        utilityDs.connectSource(walletInitCommand(walletName) + " #kwallet-create");
                    }
                }

            }

            QQC2.Button {
                visible: !openCodeToggle.checked && kwalletModeActive
                Kirigami.FormData.label: translate("Wallet status:")
                text: "Check wallet status"
                enabled: !keyringBusy
                onClicked: {
                    cancelKeyringOps();
                    keyringStatus = "Checking wallet status...";
                    utilityDs.connectSource(walletStatusCommand(effectiveWalletName()) + " #kwallet-status-check");
                }
            }

            RowLayout {
                visible: !openCodeToggle.checked && kwalletModeActive
                Kirigami.FormData.label: translate("KWallet sync:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.Button {
                    text: "Refresh from KWallet"
                    enabled: !keyringBusy
                    onClicked: page.kwalletLoadAll()
                }

                QQC2.Button {
                    text: "Sync to KWallet"
                    enabled: !keyringBusy
                    onClicked: page.kwalletStoreAll()
                }

            }

            QQC2.BusyIndicator {
                visible: !openCodeToggle.checked && kwalletModeActive && keyringBusy
                running: visible
                Kirigami.FormData.label: translate("Working:")
            }

            QQC2.Label {
                visible: !openCodeToggle.checked && keyringStatus !== ""
                Kirigami.FormData.label: translate("Status:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: keyringStatus
                wrapMode: Text.Wrap
                opacity: 0.8
            }

            // ─────────────────────────────────────────────────────────────
            // SCHEDULES SECTION
            // ─────────────────────────────────────────────────────────────
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: translate("Scheduler")
            }

            // Interactive guide
            RowLayout {
                visible: showGuidesToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.gridUnit
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: translate("Schedules Guide")

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: schedGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                    radius: 5
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    border.width: 1

                    RowLayout {
                        id: schedGuideLayout

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
                            id: schedGuideLabel

                            Layout.fillWidth: true
                            text: formLayout.schedulerGuideText
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                            color: Kirigami.Theme.textColor
                        }

                    }

                }

            }

            // Auto-start at login (separate setting)
            QQC2.Switch {
                id: schedAutoStartToggle

                Kirigami.FormData.label: translate("Auto-start at login:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: schedAutoStartToggle.checked ? translate("Scheduler starts automatically when you log in") : translate("Off — start manually each session")
                checked: false
                onCheckedChanged: {
                    if (!page.pageReady)
                        return ;

                    var verb = checked ? "enable" : "disable";
                    utilityDs.connectSource("sh -lc 'systemctl --user " + verb + " kde-ai-scheduler.service 2>&1; echo SCHED_ENABLE_OK' #sched-enable");
                }
            }

            QQC2.Switch {
                id: executeMissedSchedulesToggle

                Kirigami.FormData.label: translate("Missed schedules:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: translate("Execute missed schedules")
                checked: false
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                textFormat: Text.RichText
                text: translate("When the PC is turned off and then it restarts, if any schedule was missed in that period, should it execute one after another? <font color=\"#ff4444\"><b>(Highly not recommended)</b></font>")
                wrapMode: Text.Wrap
                opacity: 0.7
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
            }

            // Master ON/OFF switch
            QQC2.Switch {
                id: schedulerMasterSwitch

                Kirigami.FormData.label: translate("Scheduler:")
                text: schedulerMasterSwitch.checked ? translate("ON — scheduler is running") : translate("OFF — scheduler is stopped")
                checked: false
                onCheckedChanged: {
                    if (!page.pageReady)
                        return ;

                    if (checked) {
                        page.schedulerStatus = "Starting…";
                        var cmd = "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py 2>/dev/null; sleep 0.5; " + "python3 ~/.local/share/kdeaichat/kde-ai-scheduler.py &) ; " + "echo SCHED_START_OK";
                        utilityDs.connectSource("sh -lc '" + cmd + "' #sched-start-" + Date.now());
                    } else {
                        page.schedulerStatus = "Stopping…";
                        var cmd = "systemctl --user stop kde-ai-scheduler.service 2>/dev/null; pkill -f kde-ai-scheduler.py 2>/dev/null; echo SCHED_STOP_OK";
                        utilityDs.connectSource("sh -lc '" + cmd + "' #sched-stop-" + Date.now());
                    }
                    schedPollTimer.restart();
                    // Immediately trigger a poll check to reflect the start/stop actions
                    pollSchedulerState();
                }
            }

            // Status row (matching the standard layout of other settings)
            RowLayout {
                visible: schedulerMasterSwitch.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                Kirigami.FormData.label: translate("Status:")
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    id: schedDotLabel
                    text: page.schedulerDaemonRunning ? translate("Active") : (page.schedulerStatus !== "" ? translate(page.schedulerStatus) : translate("Starting…"))
                    color: page.schedulerDaemonRunning ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                    font.bold: true
                }

                QQC2.Button {
                    text: page.schedulerDaemonRunning ? translate("Restart") : translate("Force Start")
                    icon.name: page.schedulerDaemonRunning ? "view-refresh" : "media-playback-start"
                    onClicked: {
                        page.schedulerStatus = page.schedulerDaemonRunning ? "Restarting…" : "Starting…";
                        page.schedulerDaemonRunning = false;
                        var cmd = "(systemctl --user is-active --quiet kde-ai-scheduler.service && systemctl --user restart kde-ai-scheduler.service) || " + "systemctl --user enable --now kde-ai-scheduler.service 2>&1 || " + "(pkill -f kde-ai-scheduler.py; sleep 0.5; " + "nohup python3 ~/.local/share/kdeaichat/kde-ai-scheduler.py >/dev/null 2>&1 &) ; " + "echo SCHED_START_OK";
                        utilityDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "' #sched-start-" + Date.now());
                        schedPollTimer.restart();
                    }
                }

                QQC2.Button {
                    text: translate("Stop")
                    icon.name: "media-playback-stop"
                    visible: page.schedulerDaemonRunning || page.schedulerStatus !== ""
                    onClicked: {
                        page.schedulerStatus = "Stopping…";
                        var cmd = "systemctl --user stop kde-ai-scheduler.service 2>/dev/null; pkill -f kde-ai-scheduler.py 2>/dev/null; echo SCHED_STOP_OK";
                        utilityDs.connectSource("sh -lc '" + cmd + "' #sched-stop-" + Date.now());
                        schedPollTimer.restart();
                    }
                }

            }

            // Schedules management row
            RowLayout {
                visible: schedulerMasterSwitch.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                Kirigami.FormData.label: translate("Schedules:")
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: translate("Create Schedule")
                    icon.name: "list-add"
                    highlighted: true
                    Layout.fillWidth: true
                    onClicked: {
                        var now = new Date();
                        now.setMinutes(now.getMinutes() + 5);
                        scheduleDialog.draft = {
                            "id": page.schedMakeUuid(),
                            "name": "",
                            "enabled": true,
                            "chatId": "",
                            "chatName": "",
                            "message": "",
                            "taskType": "single",
                            "startDate": now.toISOString(),
                            "schedType": "days",
                            "schedEvery": 1,
                            "schedTime": "09:00",
                            "schedDays": [1],
                            "schedDayOfMonth": 1,
                            "limitEnabled": false,
                            "limitCount": 5,
                            "notify": true,
                            "createdAt": new Date().toISOString()
                        };
                        scheduleDialog.editingIndex = -2;
                        scheduleDialog.open();
                    }
                }

                QQC2.Button {
                    text: translate("Manage Schedules")
                    icon.name: "appointment-new"
                    Layout.fillWidth: true
                    onClicked: {
                        scheduleDialog.editingIndex = -1;
                        scheduleDialog.open();
                    }
                }

                QQC2.Button {
                    text: translate("Open Schedules File")
                    icon.name: "document-open"
                    Layout.fillWidth: true
                    onClicked: {
                        utilityDs.connectSource("xdg-open ~/.local/share/kdeaichat/schedules.json || kde-open ~/.local/share/kdeaichat/schedules.json || kwrite ~/.local/share/kdeaichat/schedules.json || kate ~/.local/share/kdeaichat/schedules.json || nano ~/.local/share/kdeaichat/schedules.json #open-sched-file");
                    }
                }

            }

            // Quick preview removed as per request - schedules are listed only in Manage Schedules dialog


            // Background poll timer — only checks daemon running status.
            // Schedule list sync is handled by schedulerPollTimer in main.qml.
            Timer {
                id: schedPollTimer

                interval: 30000
                repeat: true
                running: schedulerMasterSwitch.checked
                onTriggered: {
                    pollSchedulerState();
                }
            }

            // ─────────────────────────────────────────────────────────────
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: translate("Other settings")
            }

            RowLayout {
                visible: showGuidesToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.gridUnit
                Kirigami.FormData.label: translate("Settings Guide")

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: otherGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                    radius: 5
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    border.width: 1

                    RowLayout {
                        id: otherGuideLayout

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
                            text: formLayout.otherSettingsGuideText
                            wrapMode: Text.Wrap
                            textFormat: Text.RichText
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                            color: Kirigami.Theme.textColor
                        }

                    }

                }

            }

            QQC2.TextField {
                id: appDisplayNameField

                Kirigami.FormData.label: translate("App name:")
                placeholderText: "KDE AI Chat"
                onTextChanged: {
                    if (text !== (plasmoid.configuration.appDisplayName || "KDE AI Chat"))
                        page.discoveryStatus = "Tip: After changing the app name and pressing Apply/OK, restart plasmashell with: systemctl --user restart plasma-plasmashell.service";

                }
            }

            // ── Chat Storage Path ─────────────────────────────────────────────────
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: translate("Chat Storage")
            }

            RowLayout {
                Kirigami.FormData.label: translate("Save chats to:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: customHistoryPathField
                    Layout.fillWidth: true
                    placeholderText: "Default (~/.config)"
                }

                QQC2.Button {
                    text: "Browse…"
                    icon.name: "folder-open"
                    onClicked: folderDialog.open()
                }

            }

            // Status / info bar
            Rectangle {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                visible: customHistoryPathField.text.trim() !== ""
                implicitHeight: storageInfoRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: 5
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2)
                border.width: 1

                RowLayout {
                    id: storageInfoRow
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "folder-sync"
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                        Layout.alignment: Qt.AlignVCenter
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
                        text: {
                            var p = customHistoryPathField.text.trim();
                            if (p === "") return "";
                            var file = p.endsWith("/") ? p + "kdeaichat_history.json" : p + "/kdeaichat_history.json";
                            return "Chats will be saved to: <b>" + file + "</b><br/>" +
                                   "Your existing chats are <b>automatically exported</b> when you press Apply / OK.";
                        }
                        textFormat: Text.RichText
                    }
                }
            }

            // Buttons row: Export Now + Open folder
            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                visible: customHistoryPathField.text.trim() !== ""
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    id: exportNowBtn
                    text: page.storageExportStatus !== "" ? page.storageExportStatus : "Export Now"
                    icon.name: "document-export"
                    enabled: customHistoryPathField.text.trim() !== "" && page.storageExportStatus === ""
                    onClicked: {
                        page.storageExportStatus = "Exporting…";
                        var dir = customHistoryPathField.text.trim();
                        var file = dir.endsWith("/") ? dir + "kdeaichat_history.json" : dir + "/kdeaichat_history.json";
                        var jsonStr = plasmoid.configuration.chatSessionsJson || "[]";
                        // Base64-encode to avoid shell quoting issues
                        var b64 = Qt.btoa(jsonStr);
                        var cmd = "python3 -c \"import base64, os; path=os.path.expanduser('" +
                            file.replace(/'/g, "\\'") + "'); os.makedirs(os.path.dirname(path), exist_ok=True); " +
                            "open(path, 'w', encoding='utf-8').write(base64.b64decode('" + b64 + "').decode('utf-8')); print('OK')\"";
                        utilityDs.connectSource(cmd + " #storage-export-" + Date.now());
                        exportStatusTimer.restart();
                    }
                }

                QQC2.Button {
                    text: "Open Folder"
                    icon.name: "folder-open"
                    visible: customHistoryPathField.text.trim() !== ""
                    onClicked: {
                        var dir = customHistoryPathField.text.trim();
                        utilityDs.connectSource("xdg-open " + dir + " #open-storage-dir");
                    }
                }

                QQC2.Button {
                    text: "Clear Path"
                    icon.name: "edit-clear"
                    visible: customHistoryPathField.text.trim() !== ""
                    onClicked: {
                        customHistoryPathField.text = "";
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.7
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
                text: customHistoryPathField.text.trim() === ""
                    ? "💾 Chats are saved in the default KDE config location. Select a folder above to store them elsewhere (e.g. a synced cloud drive)."
                    : "⚠️ <b>Beta feature.</b> After changing this path, press <b>Apply</b> or <b>OK</b> — your chats will automatically be exported to the new location."
                textFormat: Text.RichText
            }

            // Hidden export timer to reset button label
            Timer {
                id: exportStatusTimer
                interval: 2500
                repeat: false
                onTriggered: page.storageExportStatus = ""
            }

            RowLayout {
                visible: page.discoveryStatus.indexOf("systemctl") >= 0
                Kirigami.FormData.label: translate("Next step:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth

                QQC2.TextField {
                    Layout.fillWidth: true
                    readOnly: true
                    text: "systemctl --user restart plasma-plasmashell.service"
                    selectByMouse: true
                }

                QQC2.Button {
                    text: "Copy"
                    onClicked: {
                        copyToClipboard("systemctl --user restart plasma-plasmashell.service");
                        page.discoveryStatus = "Command copied to clipboard!";
                    }
                }

            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                text: "Settings are persisted automatically by KDE when you press Apply or OK."
                opacity: 0.8
            }

            QQC2.Button {
                Kirigami.FormData.label: translate("Reset settings:")
                text: "Reset to defaults"
                onClicked: page.resetToDefaults()
            }

        }

    }

    FolderDialog {
        id: folderDialog

        title: "Select Chat History Directory"
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            if (path.length > 1 && path.slice(-1) === "/")
                path = path.slice(0, -1);

            customHistoryPathField.text = path;
        }
    }

}
