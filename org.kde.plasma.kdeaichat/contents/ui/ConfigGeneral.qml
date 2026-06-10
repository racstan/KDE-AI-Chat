import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "translations.js" as Translations
import "ProviderService.js" as ProviderService
import "WalletService.js" as WalletService
import "Security.js" as Sec
import "ConfigGeneralLogic.js" as ConfigGeneralLogic

// LINKAGE RELATIONSHIPS:
// - ConfigGeneral.qml: The main settings page UI for the Plasmoid.
// - Linked to ConfigGeneralLogic.js (imported as ConfigGeneralLogic):
//   Holds all JavaScript configuration management, model building, and service handling logic to keep ConfigGeneral.qml modular.
//   Functions in ConfigGeneralLogic.js accept a reference to the page instance to query component properties and execute state modifications.

QQC2.ScrollView {
    id: page

    contentWidth: availableWidth
    contentHeight: zoomHost.implicitHeight

    property bool debugMode: false
    function debugLog() {
        return ConfigGeneralLogic.debugLog();
    }

    //* Ctrl+scroll zoom for the settings form (0.75–1.5).
    property real configZoom: 1
    property alias cfg_appDisplayName: advancedSection.appDisplayName
    property alias cfg_appearanceMode: generalSection.appearanceMode
    property alias cfg_keyStorageMode: generalSection.storageMode
    property alias cfg_kwalletAutoPrompt: generalSection.kwalletAutoPrompt
    // Convenience computed for all KWallet-only visibility guards
    readonly property bool kwalletModeActive: cfg_keyStorageMode === 2
    property string cfg_provider: ""
    property alias cfg_baseUrl: keys1.baseUrl
    property alias cfg_apiKey: keys1.apiKey
    property alias cfg_model: keys1.model
    property alias cfg_anthropicApiKey: keys1.anthropicApiKey
    property alias cfg_anthropicModel: keys1.anthropicModel
    property alias cfg_groqBaseUrl: keys1.groqBaseUrl
    property alias cfg_groqApiKey: keys1.groqApiKey
    property alias cfg_groqModel: keys1.groqModel
    property alias cfg_deepSeekBaseUrl: keys1.deepSeekBaseUrl
    property alias cfg_deepSeekApiKey: keys1.deepSeekApiKey
    property alias cfg_deepSeekModel: keys1.deepSeekModel
    property alias cfg_miniMaxBaseUrl: keys1.miniMaxBaseUrl
    property alias cfg_miniMaxApiKey: keys1.miniMaxApiKey
    property alias cfg_miniMaxModel: keys1.miniMaxModel
    property alias cfg_fireworksBaseUrl: keys1.fireworksBaseUrl
    property alias cfg_fireworksApiKey: keys1.fireworksApiKey
    property alias cfg_fireworksModel: keys1.fireworksModel
    property alias cfg_googleBaseUrl: keys1.googleBaseUrl
    property alias cfg_googleApiKey: keys1.googleApiKey
    property alias cfg_googleModel: keys1.googleModel
    property alias cfg_openRouterBaseUrl: keys1.openRouterBaseUrl
    property alias cfg_openRouterApiKey: keys1.openRouterApiKey
    property alias cfg_openRouterModel: keys1.openRouterModel
    property alias cfg_mistralBaseUrl: keys1.mistralBaseUrl
    property alias cfg_mistralApiKey: keys1.mistralApiKey
    property alias cfg_mistralModel: keys1.mistralModel
    property alias cfg_cloudflareBaseUrl: keys1.cloudflareBaseUrl
    property alias cfg_cloudflareApiKey: keys1.cloudflareApiKey
    property alias cfg_cloudflareModel: keys1.cloudflareModel
    property alias cfg_nvidiaBaseUrl: keys1.nvidiaBaseUrl
    property alias cfg_nvidiaApiKey: keys1.nvidiaApiKey
    property alias cfg_nvidiaModel: keys1.nvidiaModel
    property alias cfg_huggingFaceBaseUrl: keys1.huggingFaceBaseUrl
    property alias cfg_huggingFaceApiKey: keys1.huggingFaceApiKey
    property alias cfg_huggingFaceModel: keys1.huggingFaceModel
    property alias cfg_xaiBaseUrl: keys2.xaiBaseUrl
    property alias cfg_xaiApiKey: keys2.xaiApiKey
    property alias cfg_xaiModel: keys2.xaiModel
    property alias cfg_lmStudioBaseUrl: keys2.lmStudioBaseUrl
    property alias cfg_lmStudioModel: keys2.lmStudioModel
    property alias cfg_localBaseUrl: keys2.localBaseUrl
    property alias cfg_localModel: keys2.localModel
    property alias cfg_ollamaBaseUrl: keys2.ollamaBaseUrl
    property alias cfg_ollamaModel: keys2.ollamaModel
    property alias cfg_litellmBaseUrl: keys2.litellmBaseUrl
    property alias cfg_litellmApiKey: keys2.litellmApiKey
    property alias cfg_litellmModel: keys2.litellmModel
    property alias cfg_qwenBaseUrl: keys2.qwenBaseUrl
    property alias cfg_qwenApiKey: keys2.qwenApiKey
    property alias cfg_qwenModel: keys2.qwenModel
    property alias cfg_moonshotBaseUrl: keys2.moonshotBaseUrl
    property alias cfg_moonshotApiKey: keys2.moonshotApiKey
    property alias cfg_moonshotModel: keys2.moonshotModel
    property alias cfg_mimoBaseUrl: keys2.mimoBaseUrl
    property alias cfg_mimoApiKey: keys2.mimoApiKey
    property alias cfg_mimoModel: keys2.mimoModel
    property alias cfg_maritacaBaseUrl: keys2.maritacaBaseUrl
    property alias cfg_maritacaApiKey: keys2.maritacaApiKey
    property alias cfg_maritacaModel: keys2.maritacaModel
    property string cfg_language: ""
    readonly property bool isLanguageEnglish: {
        let lang = cfg_language;
        if (lang === "") {
            let localeName = Qt.locale().name || "en";
            lang = localeName.split("_")[0];
        }
        return lang === "en";
    }
    property alias cfg_showInteractiveGuides: generalSection.showGuides
    property alias cfg_autoStartOpenCodeServer: openCodeSection.autoStartOpenCode
    property alias cfg_useOpenCode: generalSection.openCode
    property alias cfg_playNotificationSound: generalSection.playSound
    property alias cfg_openCodeUrl: openCodeSection.openCodeUrl
    property alias cfg_openCodeModel: openCodeSection.openCodeModelValue
    property alias cfg_openCodeProvider: openCodeSection.openCodeProviderValue
    property alias cfg_openCodeStartCommand: openCodeSection.openCodeStartCommand
    property alias cfg_openCodeStopCommand: openCodeSection.openCodeStopCommand
    property alias cfg_openCodeAutoKill: openCodeSection.openCodeAutoKill
    property alias cfg_openCodeAutoKillMinutes: openCodeSection.openCodeAutoKillMinutes
    property alias cfg_kwalletName: generalSection.walletName
    property alias cfg_systemPrompt: advancedSection.systemPrompt
    property alias cfg_memoryEnabled: advancedSection.memoryEnabled
    property alias cfg_userMemory: advancedSection.userMemory
    property alias cfg_globalContextEnabled: advancedSection.globalContextEnabled
    property alias cfg_globalContextLimit: advancedSection.globalContextLimit
    property alias cfg_globalContextAutoCompact: advancedSection.globalContextAutoCompact
    property alias cfg_globalContextCompactThreshold: advancedSection.globalContextCompactThreshold
    property alias cfg_customHistoryPath: advancedSection.customHistoryPath
    property alias cfg_schedulerEnabled: advancedSection.schedulerEnabled
    property alias cfg_schedulerAutoStart: advancedSection.schedulerAutoStart
    property alias cfg_executeMissedSchedules: advancedSection.executeMissedSchedules
    property string cfg_preselectedChatId: ""
    property string cfg_preselectedChatName: ""
    property string cfg_chatSessionsJson: "[]"
    property int cfg_customPopupWidth: 0
    property int cfg_customPopupHeight: 0
    property string cfg_lastSessionId: ""
    property string cfg_openRouterReferer: ""
    property string cfg_openRouterTitle: ""
    property string cfg_keyToggleSearch: ""
    property string cfg_keyNewChat: ""
    property string cfg_keyToggleHistory: ""
    property string cfg_keySettings: ""
    property string cfg_keyFocusInput: ""
    property string cfg_keyClearInput: ""
    property string cfg_keyToggleSearchSidebar: ""
    property string cfg_keyNextSession: ""
    property string cfg_keyPrevSession: ""
    property string cfg_keyRefresh: ""
    property string cfg_keyCopyLastReply: ""
    property string keyringStatus: ""

    // ── Layout metrics exposed so section files can read them via `page` ──
    // These are computed once here and propagated down so all sub-FormLayouts
    // size their fields identically.
    readonly property real configBoundedWidth: {
        let hostW = zoomHost ? zoomHost.width : 0;
        if (hostW <= 0)
            return Kirigami.Units.gridUnit * 28;
        return Math.min(hostW / page.configZoom, Kirigami.Units.gridUnit * 32);
    }
    readonly property real configFieldMaxWidth: Math.max(Kirigami.Units.gridUnit * 12, configBoundedWidth)
    // Compat aliases so section files that use page.boundedWidth / page.fieldMaxWidth keep working
    readonly property alias boundedWidth: page.configBoundedWidth
    readonly property alias fieldMaxWidth: page.configFieldMaxWidth
    property string discoveryStatus: ""
    property string storageExportStatus: ""
    property string openCodeSessionsStatus: ""
    property var runningOpenCodeSessions: []
    property bool runningOpenCodeSessionsVisible: false
    // ── Memory Usage ───────────────────────────────────────────────────────
    property bool memRefreshing: false
    property int memPlasma: 0
    property int memScheduler: 0
    property int memOpenCode: 0
    // ── Scheduler ──────────────────────────────────────────────────────────
    property bool schedulerDaemonRunning: false
    property string schedulerDataDir: ""
    property var schedulerList: []
    property var schedulerArchivedList: []
    property var schedulerHistory: []
    property string schedulerStatus: ""
    property bool schedSaving: false
    readonly property string configFilePath: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/kdeaichatrc"
    readonly property string dataDirPath: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/kdeaichat"
    readonly property string schedulesFilePath: dataDirPath + "/schedules.json"
    readonly property string schedulerScriptPath: dataDirPath + "/kde-ai-scheduler.py"
    property var pendingOps: ({
    })
    property var availableWalletNames: []
    // Guard to prevent premature writes during KCM initialization (cfg_ aliases
    // are populated after the combo's onCurrentIndexChanged fires).
    property bool pageReady: false
    property bool keyringBusy: keyringDs.connectedSources.length > 0 || utilityDs.connectedSources.filter(function(sourceName) {
        return sourceName.indexOf("#kwallet-") >= 0;
    }).length > 0

    // Mirrors the plasmoid root kwalletPermanentlyFailed / kwalletFailReason state
    // so the settings UI can show the banner and the Refresh button can reset it.
    // We read directly from plasmoid here; main.qml is the authoritative store.
    readonly property bool kwalletSyncPermanentlyFailed: {
        try { return plasmoid.self ? plasmoid.self.kwalletPermanentlyFailed : false; } catch(e) { return false; }
    }
    readonly property string kwalletSyncFailReason: {
        try { return plasmoid.self ? plasmoid.self.kwalletFailReason : ""; } catch(e) { return ""; }
    }
    function resetKwalletFailState() {
        try {
            if (plasmoid.self && typeof plasmoid.self.resetKwalletFailState === "function") {
                plasmoid.self.resetKwalletFailState();
            }
        } catch(e) {
            console.error("resetKwalletFailState error:", e);
        }
    }

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
    // --- Compatibility Aliases for ConfigGeneralLogic.js ---
    readonly property alias generalSection: generalSection
    readonly property alias openCodeSection: openCodeSection
    readonly property alias providersSection: providersSection
    readonly property alias keys1: keys1
    readonly property alias keys2: keys2
    readonly property alias advancedSection: advancedSection
    readonly property alias scheduleDialog: scheduleDialog

    readonly property alias walletNameField: generalSection.walletNameField
    readonly property alias providerBox: providersSection.providerBox
    readonly property alias openCodeProviderValueField: openCodeSection.openCodeProviderValueField
    readonly property alias openCodeProviderBox: openCodeSection.openCodeProviderBox
    readonly property alias openCodeModelValueField: openCodeSection.openCodeModelValueField
    readonly property alias openCodeUrlField: openCodeSection.openCodeUrlField
    readonly property alias openCodeStartCommandField: openCodeSection.openCodeStartCommandField
    readonly property alias openCodeStopCommandField: openCodeSection.openCodeStopCommandField
    readonly property alias openCodeAutoKillToggle: openCodeSection.openCodeAutoKillToggle
    readonly property alias openCodeAutoKillMinutesSpin: openCodeSection.openCodeAutoKillMinutesSpin
    readonly property alias autoStartOpenCodeToggle: openCodeSection.autoStartOpenCodeToggle
    readonly property alias showGuidesToggle: generalSection.showGuidesToggle
    readonly property alias openCodeToggle: generalSection.openCodeToggle
    readonly property alias playSoundToggle: generalSection.playSoundToggle
    readonly property alias storageModeCombo: generalSection.storageModeCombo
    readonly property alias appearanceModeCombo: generalSection.appearanceModeCombo

    // DataSources
    readonly property alias utilityDs: utilityDs
    readonly property alias keyringDs: keyringDs
    readonly property alias appDisplayNameField: advancedSection.appDisplayNameField
    readonly property alias systemPromptArea: advancedSection.systemPromptArea
    readonly property alias memoryEnabledToggle: advancedSection.memoryEnabledToggle
    readonly property alias userMemoryArea: advancedSection.userMemoryArea
    readonly property alias globalContextEnabledToggle: advancedSection.globalContextEnabledToggle
    readonly property alias globalContextLimitSpin: advancedSection.globalContextLimitSpin
    readonly property alias globalContextAutoCompactToggle: advancedSection.globalContextAutoCompactToggle
    readonly property alias globalContextCompactThresholdSpin: advancedSection.globalContextCompactThresholdSpin
    readonly property alias customHistoryPathField: advancedSection.customHistoryPathField
    readonly property alias schedulerMasterSwitch: advancedSection.schedulerMasterSwitch
    readonly property alias schedAutoStartToggle: advancedSection.schedAutoStartToggle
    readonly property alias executeMissedSchedulesToggle: advancedSection.executeMissedSchedulesToggle

    // Provider fields compatibility — keys1 and keys2 are now top-level siblings in zoomHost
    readonly property alias baseUrlField: keys1.baseUrlField
    readonly property alias apiKeyField: keys1.apiKeyField
    readonly property alias modelField: keys1.modelField
    readonly property alias anthropicApiKeyField: keys1.anthropicApiKeyField
    readonly property alias anthropicModelField: keys1.anthropicModelField
    readonly property alias groqBaseUrlField: keys1.groqBaseUrlField
    readonly property alias groqApiKeyField: keys1.groqApiKeyField
    readonly property alias groqModelField: keys1.groqModelField
    readonly property alias deepSeekBaseUrlField: keys1.deepSeekBaseUrlField
    readonly property alias deepSeekApiKeyField: keys1.deepSeekApiKeyField
    readonly property alias deepSeekModelField: keys1.deepSeekModelField
    readonly property alias miniMaxBaseUrlField: keys1.miniMaxBaseUrlField
    readonly property alias miniMaxApiKeyField: keys1.miniMaxApiKeyField
    readonly property alias miniMaxModelField: keys1.miniMaxModelField
    readonly property alias fireworksBaseUrlField: keys1.fireworksBaseUrlField
    readonly property alias fireworksApiKeyField: keys1.fireworksApiKeyField
    readonly property alias fireworksModelField: keys1.fireworksModelField
    readonly property alias googleBaseUrlField: keys1.googleBaseUrlField
    readonly property alias googleApiKeyField: keys1.googleApiKeyField
    readonly property alias googleModelField: keys1.googleModelField
    readonly property alias openRouterBaseUrlField: keys1.openRouterBaseUrlField
    readonly property alias openRouterApiKeyField: keys1.openRouterApiKeyField
    readonly property alias openRouterModelField: keys1.openRouterModelField
    readonly property alias mistralBaseUrlField: keys1.mistralBaseUrlField
    readonly property alias mistralApiKeyField: keys1.mistralApiKeyField
    readonly property alias mistralModelField: keys1.mistralModelField
    readonly property alias cloudflareBaseUrlField: keys1.cloudflareBaseUrlField
    readonly property alias cloudflareApiKeyField: keys1.cloudflareApiKeyField
    readonly property alias cloudflareModelField: keys1.cloudflareModelField
    readonly property alias nvidiaBaseUrlField: keys1.nvidiaBaseUrlField
    readonly property alias nvidiaApiKeyField: keys1.nvidiaApiKeyField
    readonly property alias nvidiaModelField: keys1.nvidiaModelField
    readonly property alias huggingFaceBaseUrlField: keys1.huggingFaceBaseUrlField
    readonly property alias huggingFaceApiKeyField: keys1.huggingFaceApiKeyField
    readonly property alias huggingFaceModelField: keys1.huggingFaceModelField
    readonly property alias xaiBaseUrlField: keys2.xaiBaseUrlField
    readonly property alias xaiApiKeyField: keys2.xaiApiKeyField
    readonly property alias xaiModelField: keys2.xaiModelField
    readonly property alias lmStudioBaseUrlField: keys2.lmStudioBaseUrlField
    readonly property alias lmStudioModelField: keys2.lmStudioModelField
    readonly property alias localBaseUrlField: keys2.localBaseUrlField
    readonly property alias localModelField: keys2.localModelField
    readonly property alias ollamaBaseUrlField: keys2.ollamaBaseUrlField
    readonly property alias ollamaModelField: keys2.ollamaModelField
    readonly property alias litellmBaseUrlField: keys2.litellmBaseUrlField
    readonly property alias litellmApiKeyField: keys2.litellmApiKeyField
    readonly property alias litellmModelField: keys2.litellmModelField
    readonly property alias qwenBaseUrlField: keys2.qwenBaseUrlField
    readonly property alias qwenApiKeyField: keys2.qwenApiKeyField
    readonly property alias qwenModelField: keys2.qwenModelField
    readonly property alias moonshotBaseUrlField: keys2.moonshotBaseUrlField
    readonly property alias moonshotApiKeyField: keys2.moonshotApiKeyField
    readonly property alias moonshotModelField: keys2.moonshotModelField
    readonly property alias mimoBaseUrlField: keys2.mimoBaseUrlField
    readonly property alias mimoApiKeyField: keys2.mimoApiKeyField
    readonly property alias mimoModelField: keys2.mimoModelField
    readonly property alias maritacaBaseUrlField: keys2.maritacaBaseUrlField
    readonly property alias maritacaApiKeyField: keys2.maritacaApiKeyField
    readonly property alias maritacaModelField: keys2.maritacaModelField


    readonly property string guideText: translate("<b>Appearance, Language &amp; Notifications Guide:</b><br/>" + "• <b>Appearance:</b> Use the <b>Appearance</b> dropdown to choose <i>Follow system</i>, <i>Light mode</i>, or <i>Dark mode</i> for the chat popup.<br/>" + "• <b>Language:</b> Use the <b>Language</b> dropdown to change the UI language of the chat popup. <i>Follow system language</i> uses your system locale automatically.<br/>" + "• <b>Notification sound:</b> Tick <b>Play sound when AI finishes a response</b> to hear an alert after every reply.<br/>" + "• <b>Interactive guides:</b> Toggle <b>Turn on interactive guides</b> to show/hide these setup cards throughout the settings.<br/>" + "• <b>Chat features:</b> Press <b>Ctrl+F</b> to search the active conversation. Click <b>Quote</b> on any message to reply inline. Use <b>Regenerate</b> to get a shorter or longer version of any AI response.<br/>" + "• <b>Session sidebar:</b> Search, sort, and filter conversations. New chats are auto-named for easy identification.<br/>" + "• <b>Global Memory &amp; Global Context:</b> In the <b>Behavior</b> section, configure memory, set the context limit (default: 1), and enable auto-compacting.<br/>" + "• <b>Schedules:</b> Use the <b>Schedules</b> tool to schedule automated questions. Type <code>/schedule</code> inside any chat to list or create automated prompts.")

    readonly property string behaviorGuideText: translate("<b>Behavior &amp; Context Guide:</b><br/>" +
        "• <b>System prompt:</b> Set a default instruction template for the AI (e.g., <i>\"Be extremely concise\"</i>).<br/>" +
        "• <b>Global Memory:</b> Write facts the AI should remember across all conversations.<br/>" +
        "• <b>Global Context:</b> Limit how many past messages the AI sees to control token usage (default limit is 1). Each chat has the ability to modify the context for that chat; if nothing is specified there, this global context config is used.<br/>" +
        "• <b>Context Compacting:</b> Automatically summarize older messages in the background to save context window tokens. A confirmation prompt appears before compaction runs.")

    readonly property string providerGuideText: {
        if (cfg_useOpenCode)
            return translate("<b>OpenCode Setup Guide:</b><br/>" + "1. Select <b>OpenCode Mode (Uses Opencode)</b> under Operating Mode.<br/>" + "2. Scroll down to the <b>OpenCode</b> section and enter the server URL (default: <code>http://127.0.0.1:4096</code>).<br/>" + "3. Click <b>Start Server</b> to launch the local OpenCode server in the background.<br/>" + "4. Click <b>Check Server</b> to verify it is online.<br/>" + "5. Once online, the available providers/models dropdowns will auto-populate.<br/>" + "6. (Optional) Enable <b>Auto-kill session</b> and set the inactivity delay to stop the OpenCode server to save memory when not in use. It will automatically restart when you type a message in the chat.<br/>" + "7. Click <b>Apply</b>/<b>OK</b> to save and start using local coding assistance.");

        let provider = cfg_provider || "openai";
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
            return translate("<b>MiMo (Xiaomi) Setup Guide:</b><br/>" + "1. Get access at <b>api.xiaomimimo.com</b> and copy your API key.<br/>" + "2. Paste it into the <b>MiMo key</b> field below.<br/>" + "3. Choose a model (e.g. <code>mimo-v2-pro</code>, <code>mimo-v2</b>).<br/>" + "4. Click <b>Apply</b>/<b>OK</b> to save.");
        else if (provider === "maritaca")
            return translate("<b>Maritaca AI (Sabiá) Setup Guide:</b><br/>" + "1. Get your API key at <b>chat.maritaca.ai → Settings → API Keys</b>.<br/>" + "2. Paste it into the <b>Maritaca key</b> field below.<br/>" + "3. Choose a model (e.g. <code>sabia-4</code> — optimised for Portuguese).<br/>" + "4. The default URL <code>https://chat.maritaca.ai/api</code> is correct — do not change it.<br/>" + "5. Click <b>Apply</b>/<b>OK</b> to save.");
        return translate("<b>Provider Setup Guide:</b> Select a provider from the <b>Default provider</b> dropdown above to see setup instructions.");
    }

    readonly property string apiGuideText: {
        let storageIdx = cfg_keyStorageMode;
        if (storageIdx === 0)
            return translate("<b>API Key Storage Guide:</b><br/>" + "• Current mode: <b>🔒 Session-only memory</b>.<br/>" + "• Enter your API keys in the provider fields below. No extra steps needed — keys are held in memory only.<br/>" + "• Keys are wiped completely when the widget closes. You must re-entered them every session.");
        else if (storageIdx === 1)
            return translate("<b>API Key Storage Guide:</b><br/>" + "• Current mode: <b>📄 Plain config file</b> (unencrypted).<br/>" + "• Enter your keys in the provider fields below, then click <b>Apply</b>/<b>OK</b> to save them to <code>~/.config/kdeaichatrc</code>.<br/>" + "• (Optional) Click <b>Reload from config file</b> if you edited the file externally.<br/>" + "• (Optional) Click <b>Open config file</b> to view or paste keys directly into the file.<br/>" + "• Security: Keys are stored as plain text — suitable for single-user machines only.");
        else if (storageIdx === 2)
            return translate("<b>API Key Storage Guide:</b><br/>" + "• Current mode: <b>🔑 KWallet</b> (encrypted).<br/>" + "• Click <b>Detect wallets</b> to find available KDE wallets.<br/>" + "• If none are found, click <b>Create wallet</b> — KWallet will prompt for a password to create one.<br/>" + "• Select your wallet from the <b>Wallet name</b> dropdown, enter your keys, then click <b>Sync to KWallet</b>.<br/>" + "• (Optional) Click <b>Launch KWalletManager</b> to inspect or manage your wallet via the system app.<br/>" + "• Security: Keys are fully encrypted. Best for shared or multi-user systems.");
        return "";
    }

    readonly property string otherSettingsGuideText: translate("<b>Other Settings Guide:</b><br/>• <b>Keyboard Shortcuts:</b> Customize keyboard shortcuts in the <b>Shortcuts</b> tab. Configure hotkeys for all common actions — search, new chat, export, regenerate, and more.<br/>• <b>App name:</b> Change the display name shown in the widget title bar. After clicking Apply/OK, restart the shell with the command shown to apply it.<br/>• <b>System prompt:</b> Set a default system instruction for every chat session (e.g. <i>\"You are a helpful Linux assistant.\"</i>). Leave blank to use the default.<br/>• <b>Chat storage path (beta):</b> Choose a folder to save your chat history. Click <b>Browse...</b> to pick a folder, or type a path directly. History is saved as <code>kdeaichat_history.json</code> inside that folder. Default is <code>~/.config</code>.<br/>• <b>Reset to defaults:</b> Click <b>Reset to defaults</b> to restore all settings to their original values.")

    readonly property string schedulerGuideText: {
        if (!cfg_schedulerEnabled) {
            return translate("<b>Schedules Guide:</b><br/>" +
                "The scheduler runs in the background. At the time you choose, it automatically sends a message into your chat and the AI replies.<br/><br/>" +
                "• <b>Status: Stopped</b>.<br/>" +
                "• <b>Action:</b> Toggle the <b>Scheduler switch</b> below to <b>ON</b> to boot the background daemon.");
        }

        if (!schedulerDaemonRunning) {
            return translate("<b>Schedules Guide:</b><br/>" +
                "• <b>Status: Starting up...</b><br/>" +
                "• The scheduler daemon is starting in the background. Once initialized, the status indicator will show <b>Active</b>.<br/>" +
                "• (Optional) Make sure to toggle <b>Auto-start at login</b> to <b>ON</b> if you want automated schedules to trigger even when you don't open settings.");
        }

        let count = schedulerList.length;
        if (count === 0) {
            return translate("<b>Schedules Guide:</b><br/>" +
                "• <b>Status: Active &amp; running!</b><br/>" +
                "• The scheduler is connected and monitoring. But you have <b>0 schedules configured</b>.<br/>" +
                "• <b>Action:</b> Click <b>Create Schedule</b> below to set up your first automated daily or one-time prompt!");
        }

        let enabledCount = 0;
        for (let i = 0; i < count; i++) {
            if (schedulerList[i] && schedulerList[i].enabled) {
                enabledCount++;
            }
        }

        return translate("<b>Schedules Guide:</b><br/>• <b>Status: Active &amp; running!</b><br/>• You have <b>%1 schedule(s) configured</b> (%2 enabled).<br/>• The background service will run automatically. Click <b>Manage Schedules</b> to edit or delete tasks, view executed run history logs, and customize history retention limits.<br/>• <i>Pro-Tip:</i> You can also schedule prompts directly from the chat box by typing <code>/schedule</code>!").arg(count).arg(enabledCount);
    }

    function translate(text) {
        return ConfigGeneralLogic.translate(text);
    }

    function updateFilteredProviderModels(searchText) {
        return ConfigGeneralLogic.updateFilteredProviderModels(searchText);
    }

    function updateFilteredOpenCodeModels(searchText) {
        return ConfigGeneralLogic.updateFilteredOpenCodeModels(searchText);
    }

    function effectiveWalletName() {
        return ConfigGeneralLogic.effectiveWalletName();
    }

    function maybeAdoptDetectedWalletName() {
        return ConfigGeneralLogic.maybeAdoptDetectedWalletName();
    }

    function detectWallets() {
        return ConfigGeneralLogic.detectWallets();
    }

    function setActiveProviderModelValue(value) {
        return ConfigGeneralLogic.setActiveProviderModelValue(value);
    }

    function activeProviderModelValue() {
        return ConfigGeneralLogic.activeProviderModelValue();
    }

    function walletReadCommand(walletName, keyName) {
        return ConfigGeneralLogic.walletReadCommand(walletName, keyName);
    }

    function walletWriteCommand(walletName, keyName, value) {
        return ConfigGeneralLogic.walletWriteCommand(walletName, keyName, value);
    }

    function walletInitCommand(walletName) {
        return ConfigGeneralLogic.walletInitCommand(walletName);
    }

    function walletStatusCommand(walletName) {
        return ConfigGeneralLogic.walletStatusCommand(walletName);
    }

    function walletBulkReadCommand(walletName) {
        return ConfigGeneralLogic.walletBulkReadCommand(walletName);
    }

    function shellEscape(s) {
        return ConfigGeneralLogic.shellEscape(s);
    }

    function copyToClipboard(textValue) {
        return ConfigGeneralLogic.copyToClipboard(textValue);
    }

    function providerEnabled(providerId) {
        return ConfigGeneralLogic.providerEnabled(providerId);
    }

    function providerNeedsApiKey(providerId) {
        return ConfigGeneralLogic.providerNeedsApiKey(providerId);
    }

    function providerHasConfiguredKey(providerId) {
        return ConfigGeneralLogic.providerHasConfiguredKey(providerId);
    }

    function refreshIfActiveProvider(providerId) {
        return ConfigGeneralLogic.refreshIfActiveProvider(providerId);
    }

    function providerModelVisible(providerId) {
        return ConfigGeneralLogic.providerModelVisible(providerId);
    }

    function providerNeedsKeyHintVisible(providerId) {
        return ConfigGeneralLogic.providerNeedsKeyHintVisible(providerId);
    }

    function currentProviderDisplayName() {
        return ConfigGeneralLogic.currentProviderDisplayName();
    }

    function currentProviderConfig() {
        return ConfigGeneralLogic.currentProviderConfig();
    }

    function makeOpenAiModelsUrl(baseUrl) {
        return ConfigGeneralLogic.makeOpenAiModelsUrl(baseUrl);
    }

    function parseModelIds(responseObj) {
        return ConfigGeneralLogic.parseModelIds(responseObj);
    }

    function requestJson(url, headers, onSuccess, onError) {
        return ConfigGeneralLogic.requestJson(url, headers, onSuccess, onError);
    }

    function refreshCurrentProviderModels() {
        return ConfigGeneralLogic.refreshCurrentProviderModels();
    }

    function applyDetectedModelToActiveProvider(modelId) {
        return ConfigGeneralLogic.applyDetectedModelToActiveProvider(modelId);
    }

    function activeOpenCodeProvider() {
        return ConfigGeneralLogic.activeOpenCodeProvider();
    }

    function setOpenCodeProviderValue(v) {
        return ConfigGeneralLogic.setOpenCodeProviderValue(v);
    }

    function setOpenCodeModelValue(v) {
        return ConfigGeneralLogic.setOpenCodeModelValue(v);
    }

    function openCodeServerRoot(baseUrl) {
        return ConfigGeneralLogic.openCodeServerRoot(baseUrl);
    }

    function parseOpenCodeProviderModels(providerObj) {
        return ConfigGeneralLogic.parseOpenCodeProviderModels(providerObj);
    }

    function syncOpenCodeProviderSelection(providerId, preferredModel) {
        return ConfigGeneralLogic.syncOpenCodeProviderSelection(providerId, preferredModel);
    }

    function refreshOpenCodeDiscovery() {
        return ConfigGeneralLogic.refreshOpenCodeDiscovery();
    }

    function startOpenCodeServerAutomatically() {
        return ConfigGeneralLogic.startOpenCodeServerAutomatically();
    }

    function checkAndAutoStartOpenCodeServer() {
        return ConfigGeneralLogic.checkAndAutoStartOpenCodeServer();
    }

    function probeOpenCodeProviders(baseUrl) {
        return ConfigGeneralLogic.probeOpenCodeProviders(baseUrl);
    }

    function probeOpenCodeModels(baseUrl, providerId) {
        return ConfigGeneralLogic.probeOpenCodeModels(baseUrl, providerId);
    }

    function refreshRunningOpenCodeSessions() {
        return ConfigGeneralLogic.refreshRunningOpenCodeSessions();
    }

    function loadSessionsList(urlSessions, statusMap) {
        return ConfigGeneralLogic.loadSessionsList(urlSessions, statusMap);
    }

    function killRunningOpenCodeSession(sessionId) {
        return ConfigGeneralLogic.killRunningOpenCodeSession(sessionId);
    }

    function kwalletStore(targetId, value, isBulk) {
        return ConfigGeneralLogic.kwalletStore(targetId, value, isBulk);
    }

    function saveKey(targetId, value) {
        return ConfigGeneralLogic.saveKey(targetId, value);
    }

    function kwalletLoad(targetId, isBulk) {
        return ConfigGeneralLogic.kwalletLoad(targetId, isBulk);
    }

    function applyLoadedKey(targetId, secretValue) {
        return ConfigGeneralLogic.applyLoadedKey(targetId, secretValue);
    }

    function keyTargetIds() {
        return ConfigGeneralLogic.keyTargetIds();
    }

    function apiKeyForTarget(targetId) {
        return ConfigGeneralLogic.apiKeyForTarget(targetId);
    }

    function kwalletLoadAll(autoPrompt) {
        return ConfigGeneralLogic.kwalletLoadAll(autoPrompt);
    }

    function kwalletStoreAll(autoPrompt) {
        return ConfigGeneralLogic.kwalletStoreAll(autoPrompt);
    }

    function clearAllApiKeyFields() {
        return ConfigGeneralLogic.clearAllApiKeyFields();
    }

    function base64Encode(str) {
        return ConfigGeneralLogic.base64Encode(str);
    }

    function getHelperPath() {
        return ConfigGeneralLogic.getHelperPath();
    }

    function loadKeysFromPlainConfig() {
        return ConfigGeneralLogic.loadKeysFromPlainConfig();
    }

    function applyPlainConfigKeys(keys) {
        return ConfigGeneralLogic.applyPlainConfigKeys(keys);
    }

    function writeKeysToDiskAndOpen() {
        return ConfigGeneralLogic.writeKeysToDiskAndOpen();
    }

    function syncKeysToDisk() {
        return ConfigGeneralLogic.syncKeysToDisk();
    }

    function clearKeysFromDisk() {
        return ConfigGeneralLogic.clearKeysFromDisk();
    }

    function saveGeneralSettingsOnly() {
        return ConfigGeneralLogic.saveGeneralSettingsOnly();
    }

    function cancelKeyringOps() {
        return ConfigGeneralLogic.cancelKeyringOps();
    }

    function resetToDefaults() {
        return ConfigGeneralLogic.resetToDefaults();
    }

    // ── Scheduler helpers ──────────────────────────────────────────────────────
    property string _lastSchedSetupPayload: ""
    function schedAutoSetup() {
        return ConfigGeneralLogic.schedAutoSetup();
    }

    function pollSchedulerState() {
        return ConfigGeneralLogic.pollSchedulerState();
    }

    function schedLoadSchedules() {
        return ConfigGeneralLogic.schedLoadSchedules();
    }

    function schedSaveSchedules(items) {
        return ConfigGeneralLogic.schedSaveSchedules(items);
    }

    function getHistoryLimitValue() {
        return ConfigGeneralLogic.getHistoryLimitValue();
    }

    function schedSaveAll() {
        return ConfigGeneralLogic.schedSaveAll();
    }

    function schedTriggerNow(index) {
        return ConfigGeneralLogic.schedTriggerNow(index);
    }

    function schedMakeUuid() {
        return ConfigGeneralLogic.schedMakeUuid();
    }

    function openPrefilledScheduleDialog(pId, pName) {
        return ConfigGeneralLogic.openPrefilledScheduleDialog(pId, pName);
    }

    function schedDefaultBaseUrl(provider) {
        return ConfigGeneralLogic.schedDefaultBaseUrl(provider);
    }

    function schedHumanCron(expr) {
        return ConfigGeneralLogic.schedHumanCron(expr);
    }

    onVisibleChanged: {
        if (visible) {
            if (!openCodeToggle.checked && plasmoid.configuration.keyStorageMode === 2) {
                detectWallets();
            }
        }
    }

    QQC2.ScrollBar.horizontal.policy: configZoom > 1.01 ? QQC2.ScrollBar.AsNeeded : QQC2.ScrollBar.AlwaysOff
    Component.onCompleted: {
        if (plasmoid.configuration.appearanceMode === 3 || plasmoid.configuration.appearanceMode > 2)
            plasmoid.configuration.appearanceMode = 0;

        // cfg_ aliases already load the Plasma-stored values automatically.
        // For KWallet mode, trigger wallet detection to populate the fields.
        // For session-only mode, wipe the fields so stale cfg values aren't used.
        if (!openCodeToggle.checked && plasmoid.configuration.keyStorageMode === 2 && page.visible)
            detectWallets();
        else if (plasmoid.configuration.keyStorageMode === 0)
            clearAllApiKeyFields();
        if (openCodeToggle.checked) {
            let savedProvider = openCodeProviderValueField.text || "";
            let savedModel = openCodeModelValueField.text || "";
            if (savedProvider) {
                openCodeProviderCandidates = [savedProvider];
                if (savedModel) {
                    let mmap = {};
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
        let pId = "";
        let pName = "Chat";
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

    /*
    Connections {
        target: plasmoid.configuration
        function onPreselectedChatIdChanged() {
            let pId = plasmoid.configuration.preselectedChatId;
            if (pId && pId !== "") {
                let pName = plasmoid.configuration.preselectedChatName || "Chat";
                openPrefilledScheduleDialog(pId, pName);
            }
        }
    }
    */
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
    // page: page is required — QML component files do NOT inherit id-namespace
    // from the parent file. Without this, all page.xxx calls inside ScheduleDialog
    // would resolve to undefined.
    ScheduleDialog {
        id: scheduleDialog
        page: page
    }

    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        onWheel: function(event) {
            let step = event.angleDelta.y / 800;
            page.configZoom = Math.max(0.75, Math.min(1.5, page.configZoom + step));
            event.accepted = true;
        }
    }

    P5Support.DataSource {
        id: keyringDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "").trim();
            let stderr = (data["stderr"] || "").trim();
            let op = page.pendingOps[sourceName];
            if (op) {
                let copy = page.pendingOps;
                delete copy[sourceName];
                page.pendingOps = copy;
            }
            if (!op) {
                disconnectSource(sourceName);
                return ;
            }
            if (op.mode === "load") {
                if (stdout.indexOf("__KAI_SECRET__:") === 0) {
                    let loadedValue = stdout.slice("__KAI_SECRET__:".length);
                    page.applyLoadedKey(op.target, loadedValue);
                    page.keyringStatus = op.bulk ? "Refreshing API keys from KWallet..." : ("Loaded key for " + op.target + " from KWallet.");
                    try { if (plasmoid.self) plasmoid.self.kwalletOpenAttempts = 0; } catch(e) {}
                } else if (!op.bulk) {
                    if (stdout === "__KAI_LOAD__:NO_WALLET") {
                        page.keyringStatus = "Configured wallet not found. Use Detect wallets or Create wallet.";
                    } else if (stdout === "__KAI_LOAD__:OPEN_FAILED") {
                        page.keyringStatus = "KWallet did not open the selected wallet.";
                        try {
                            if (plasmoid.self) {
                                plasmoid.self.kwalletOpenAttempts++;
                                if (plasmoid.self.kwalletOpenAttempts >= 3) {
                                    let reason = "KWallet sync failed (3 attempts) possibly due to wrong password. Please click 'Refresh from KWallet' to retry.";
                                    plasmoid.self.kwalletPermanentlyFailed = true;
                                    plasmoid.self.kwalletFailReason = reason;
                                }
                            }
                        } catch(e) {}
                    } else if (stdout === "__KAI_LOAD__:NO_FOLDER") {
                        page.keyringStatus = "Wallet opened, but KDE AI Chat storage is not initialized yet. Click Create wallet first.";
                    } else if (stdout === "__KAI_LOAD__:NO_ENTRY") {
                        page.keyringStatus = "No saved key for " + op.target + " in KWallet.";
                    } else if (stderr !== "") {
                        page.keyringStatus = "KWallet (" + op.target + "): " + stderr;
                    } else {
                        page.keyringStatus = "No saved key for " + op.target + " in KWallet.";
                    }
                }
            } else if (op.mode === "bulk_store") {
                if (stdout === "__KAI_BULK_STORE__:OPEN_FAILED") {
                    page.keyringStatus = "KWallet did not open the selected wallet.";
                    try {
                        if (plasmoid.self) {
                            plasmoid.self.kwalletOpenAttempts++;
                            if (plasmoid.self.kwalletOpenAttempts >= 3) {
                                let reason = "KWallet sync failed (3 attempts) possibly due to wrong password. Please click 'Refresh from KWallet' to retry.";
                                plasmoid.self.kwalletPermanentlyFailed = true;
                                plasmoid.self.kwalletFailReason = reason;
                            }
                        }
                    } catch(e) {}
                } else if (stdout === "__KAI_BULK_STORE__:NOT_UNLOCKED") {
                    page.keyringStatus = "KWallet is locked/closed. Manual sync required.";
                } else if (stdout.indexOf("__KAI_BULK_STORE__:DONE") === 0) {
                    page.keyringStatus = "Synced all API keys to KWallet.";
                    try { if (plasmoid.self) { plasmoid.self.kwalletOpenAttempts = 0; plasmoid.self.kwalletPermanentlyFailed = false; } } catch(e) {}
                } else if (stderr !== "") {
                    page.keyringStatus = "KWallet error: " + stderr;
                } else {
                    page.keyringStatus = "Synced API keys to KWallet.";
                    try { if (plasmoid.self) { plasmoid.self.kwalletOpenAttempts = 0; plasmoid.self.kwalletPermanentlyFailed = false; } } catch(e) {}
                }
            } else {
                if (!op.bulk) {
                    if (stdout === "__KAI_STORE__:OPEN_FAILED") {
                        page.keyringStatus = "KWallet did not open the selected wallet.";
                        try {
                            if (plasmoid.self) {
                                plasmoid.self.kwalletOpenAttempts++;
                                if (plasmoid.self.kwalletOpenAttempts >= 3) {
                                    let reason = "KWallet sync failed (3 attempts) possibly due to wrong password. Please click 'Refresh from KWallet' to retry.";
                                    plasmoid.self.kwalletPermanentlyFailed = true;
                                    plasmoid.self.kwalletFailReason = reason;
                                }
                            }
                        } catch(e) {}
                    } else if (stdout.indexOf("__KAI_STORE__:") === 0) {
                        page.keyringStatus = "Saved key for " + (op.target || "provider") + " to KWallet.";
                        try { if (plasmoid.self) plasmoid.self.kwalletOpenAttempts = 0; } catch(e) {}
                    } else if (stderr !== "") {
                        page.keyringStatus = "KWallet error: " + stderr;
                    } else {
                        page.keyringStatus = "Saved key for " + (op.target || "provider") + " to KWallet.";
                        try { if (plasmoid.self) plasmoid.self.kwalletOpenAttempts = 0; } catch(e) {}
                    }
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
            let out = (data["stdout"] || "").trim();
            let err = (data["stderr"] || "").trim();
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
                debugLog("[KAI-DEBUG] kwallet-refresh-all stdout length:", out.length);
                debugLog("[KAI-DEBUG] kwallet-refresh-all stderr:", err);
                if (out.indexOf("__KAI_BULK__:") < 0) {
                    debugLog("[KAI-DEBUG] kwallet-refresh-all not finished yet, waiting...");
                    return ;
                }
                if (out === "__KAI_BULK__:NO_WALLET") {
                    keyringStatus = "Configured wallet not found. Pick a detected wallet and retry.";
                } else if (out === "__KAI_BULK__:OPEN_FAILED") {
                    keyringStatus = "KWallet did not open the selected wallet.";
                    try {
                        if (plasmoid.self) {
                            plasmoid.self.kwalletOpenAttempts++;
                            if (plasmoid.self.kwalletOpenAttempts >= 3) {
                                let reason = "KWallet sync failed (3 attempts) possibly due to wrong password. Please click 'Refresh from KWallet' to retry.";
                                plasmoid.self.kwalletPermanentlyFailed = true;
                                plasmoid.self.kwalletFailReason = reason;
                            }
                        }
                    } catch(e) {}
                } else if (out === "__KAI_BULK__:NOT_UNLOCKED") {
                    keyringStatus = "KWallet is locked/closed. Click 'Refresh from KWallet' to unlock.";
                } else if (out === "__KAI_BULK__:NO_FOLDER") {
                    keyringStatus = "Wallet opened, but KDE AI Chat storage is not initialized yet.";
                } else {
                    try {
                        if (plasmoid.self) {
                            plasmoid.self.kwalletOpenAttempts = 0;
                            plasmoid.self.kwalletPermanentlyFailed = false;
                            plasmoid.self.kwalletFailReason = "";
                        }
                    } catch(e) {}
                    let lines = out === "" ? [] : out.split(/\n+/);
                    let loaded = 0;
                    for (let i = 0; i < lines.length; i++) {
                        if (lines[i].indexOf("__KAI_SECRET__:") !== 0)
                            continue;

                        let rest = lines[i].slice("__KAI_SECRET__:".length);
                        let sep = rest.indexOf(":");
                        if (sep <= 0)
                            continue;

                        let targetId = rest.slice(0, sep);
                        let secretValue = rest.slice(sep + 1);
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
                    let walletList = out.slice("__KAI_STATUS__:NO_WALLET:".length).replace(/\n/g, ", ");
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
                    let keys = JSON.parse(out);
                    applyPlainConfigKeys(keys);
                    keyringStatus = "Keys successfully reloaded from the physical configuration file.";
                } catch (e) {
                    console.error("Error parsing plain config: " + e);
                    keyringStatus = "Error parsing config file: " + e;
                }
            } else if (sourceName.indexOf("plainconfig-sync") >= 0) {
                if (err !== "")
                    keyringStatus = "Error saving to config file: " + err;

            } else if (sourceName.indexOf("sched-poll-") >= 0) {
                page.schedulerDaemonRunning = (out.trim() === "SCHED_RUNNING");
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
            } else if (sourceName.indexOf("mem-usage-") >= 0) {
                page.memRefreshing = false;
                try {
                    let memData = JSON.parse(out.trim());
                    page.memPlasma = memData.plasmashell || 0;
                    page.memScheduler = memData.scheduler || 0;
                    page.memOpenCode = memData.opencode || 0;
                } catch(e) {
                    console.warn("Failed to parse memory data:", e);
                }
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
                        let parsed = JSON.parse(out);
                        let allSchedules = parsed.schedules || [];
                        let active = [];
                        let archived = [];
                        for (let i = 0; i < allSchedules.length; i++) {
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
                        let hist = parsed.history || [];
                        let limit = page.getHistoryLimitValue();
                        if (hist.length > limit) {
                            hist = hist.slice(hist.length - limit);
                        }
                        page.schedulerHistory = hist;
                    } catch (e) {
                        page.schedulerList = [];
                        page.schedulerArchivedList = [];
                        page.schedulerHistory = [];
                    }
                }
            } else if (sourceName.indexOf("sched-save") >= 0) {
                page.schedSaving = false;
                page.schedulerStatus = "Schedules saved.";
            } else if (sourceName.indexOf("#opencode-autostart") >= 0) {
                if (err !== "" && err.indexOf("Warning:") < 0 && err.indexOf("nohup:") < 0) {
                    discoveryStatus = "Auto-start failed: " + err;
                } else {
                    discoveryStatus = "OpenCode auto-start command launched. Checking server...";
                }
            } else if (sourceName.indexOf("#opencode-start") >= 0) {
                if (err !== "" && err.indexOf("Warning:") < 0 && err.indexOf("nohup:") < 0) {
                    discoveryStatus = "Start failed: " + err;
                } else {
                    discoveryStatus = "OpenCode start command launched. Checking server...";
                    openCodeAutoStartTimer.restart();
                }
            } else if (sourceName.indexOf("#opencode-stop") >= 0) {
                if (err !== "" && err.indexOf("Warning:") < 0 && err.indexOf("nohup:") < 0) {
                    discoveryStatus = "Stop failed: " + err;
                } else {
                    discoveryStatus = "OpenCode server stopped.";
                    openCodeProviderCandidates = [];
                    openCodeModelCandidates = [];
                    setOpenCodeProviderValue("");
                    setOpenCodeModelValue("");
                    updateFilteredOpenCodeModels("");
                }
            } else {
                discoveryStatus = out !== "" ? out : (err !== "" ? err : "Command finished.");
            }
            disconnectSource(sourceName);
        }
    }

    Item {
        id: zoomHost
        width: page.availableWidth
        implicitWidth: page.availableWidth

        // Sum the heights of all six sibling section FormLayouts
        implicitHeight: Math.ceil(
            (generalSection.implicitHeight +
             openCodeSection.implicitHeight +
             providersSection.implicitHeight +
             keys1.implicitHeight +
             keys2.implicitHeight +
             advancedSection.implicitHeight) * page.configZoom
        )
        clip: true

        // ── General Settings ─────────────────────────────────────────────────
        // LINKAGE: ConfigGeneralSection is the first Kirigami.FormLayout section.
        // All six sibling FormLayouts are linked via twinFormLayouts so
        // all label columns are identically wide across the whole settings page.
        ConfigGeneralSection {
            id: generalSection
            page: page
            x: 0; y: 0
            height: implicitHeight
            clip: true
            scale: page.configZoom
            transformOrigin: Item.TopLeft
            wideMode: false
            width: page.configBoundedWidth
            twinFormLayouts: [openCodeSection, providersSection, keys1, keys2, advancedSection]
        }

        // ── OpenCode Settings ─────────────────────────────────────────────────
        ConfigOpenCodeSection {
            id: openCodeSection
            page: page
            x: 0
            height: implicitHeight
            clip: true
            scale: page.configZoom
            transformOrigin: Item.TopLeft
            wideMode: false
            width: page.configBoundedWidth
            y: generalSection.implicitHeight * page.configZoom
            twinFormLayouts: [generalSection, providersSection, keys1, keys2, advancedSection]
        }

        // ── Provider Selection ─────────────────────────────────────────────────
        ConfigProvidersSection {
            id: providersSection
            page: page
            x: 0
            height: implicitHeight
            clip: true
            scale: page.configZoom
            transformOrigin: Item.TopLeft
            wideMode: false
            width: page.configBoundedWidth
            y: (generalSection.implicitHeight + openCodeSection.implicitHeight) * page.configZoom
            twinFormLayouts: [generalSection, openCodeSection, keys1, keys2, advancedSection]
        }

        // ── Provider API Keys (Group 1: OpenAI → Hugging Face) ──────────────────
        // LINKAGE: keys1 is a sibling of providersSection (NOT nested inside it).
        // It is positioned directly below providersSection in the vertical stack.
        ConfigProvidersKeys1 {
            id: keys1
            page: page
            x: 0
            height: implicitHeight
            clip: true
            scale: page.configZoom
            transformOrigin: Item.TopLeft
            wideMode: false
            width: page.configBoundedWidth
            y: (generalSection.implicitHeight + openCodeSection.implicitHeight + providersSection.implicitHeight) * page.configZoom
            twinFormLayouts: [generalSection, openCodeSection, providersSection, keys2, advancedSection]
        }

        // ── Provider API Keys (Group 2: xAI → Maritaca) ─────────────────────
        ConfigProvidersKeys2 {
            id: keys2
            page: page
            x: 0
            height: implicitHeight
            clip: true
            scale: page.configZoom
            transformOrigin: Item.TopLeft
            wideMode: false
            width: page.configBoundedWidth
            y: (generalSection.implicitHeight + openCodeSection.implicitHeight + providersSection.implicitHeight + keys1.implicitHeight) * page.configZoom
            twinFormLayouts: [generalSection, openCodeSection, providersSection, keys1, advancedSection]
        }

        // ── Advanced / Scheduler / Storage ────────────────────────────────────
        ConfigAdvancedSection {
            id: advancedSection
            page: page
            x: 0
            height: implicitHeight
            clip: true
            scale: page.configZoom
            transformOrigin: Item.TopLeft
            wideMode: false
            width: page.configBoundedWidth
            y: (generalSection.implicitHeight + openCodeSection.implicitHeight + providersSection.implicitHeight + keys1.implicitHeight + keys2.implicitHeight) * page.configZoom
            twinFormLayouts: [generalSection, openCodeSection, providersSection, keys1, keys2]
        }

    }

    FolderDialog {
        id: folderDialog

        title: "Select Chat History Directory"
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            if (path.length > 1 && path.slice(-1) === "/")
                path = path.slice(0, -1);

            advancedSection.customHistoryPathField.text = path;
        }
    }

}
