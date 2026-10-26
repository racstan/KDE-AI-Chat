pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "ProviderService.js" as ProviderService
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid
import QtCore
import "Security.js" as Sec
import "store" as Store
import "chat/PromptTemplates.js" as PromptTemplates
import "chat/MessageContent.js" as MessageContent
import "chat/TimeFormat.js" as TimeFormat
import "chat" as Chat

PlasmoidItem {
    id: root

    // The icon value may be a KDE icon name or an image file path chosen in
    // Settings → Other (see customIconIsImage below).
    Plasmoid.icon: (plasmoid && plasmoid.configuration && plasmoid.configuration.customIcon) ? plasmoid.configuration.customIcon : "dialog-messages"

    property var sessions: []
    property string currentSessionId: ""
    property string currentSessionTitle: ""
    property var messages: []
    property string currentStreamKey: ""
    // The view's row-by-row copy of `messages` (see chat/MessageModel.qml).
    property Chat.MessageModel messageModel: Chat.MessageModel {}
    // Stream deltas wait here and reach currentStreamText/Reasoning at most every 33 ms.
    property Chat.StreamBuffer streamBuffer: Chat.StreamBuffer { target: root; maxChars: root.maxMessageChars }
    // Projects and the history's view (chat/Projects.qml); the UI calls chat.projects.<name>.
    readonly property Chat.Projects projects: Chat.Projects { chat: root }
    property var attachedFiles: []
    property bool historyOnlyMode: false
    property bool historySidePanel: false // set by chat/ChatBody.qml: history beside the chat stays open on New chat
    property bool loading: false
    property var activeXhr: null
    property int requestGeneration: 0
    property string activeRequestSessionId: ""
    property bool streamingResponse: false
    property string currentStreamText: ""
    property string currentStreamReasoning: ""
    property string currentStreamExtractedReasoning: ""
    readonly property int maxMessageChars: 2000000
    property int currentStreamIndex: -1
    property int playingMessageIndex: -1
    property int editingMessageIndex: -1
    property string editingDraft: ""
    property string editingSessionId: ""
    property string editingSessionDraft: ""
    property bool renamingCurrentChat: false
    property string currentChatRenameDraft: ""
    // The open chat's mode (set by modeSync; a chat keeps the mode it was started in).
    property bool openCodeMode: false
    property bool piMode: false
    // Shown above the chat when its mode can't be used; the chat stays in that mode.
    property string modeNotice: ""
    property string openCodeAgent: plasmoid.configuration.openCodeAgent || ""
    property string openCodeWorkspaceCwd: ""  // the open chat's workspace ("" = none), set by modeSync
    property bool openCodeUseAgentModel: plasmoid.configuration.openCodeUseAgentModel !== false
    property var openCodeAgentsList: []
    // The workspace folder openCodeAgentsList was loaded for (null: not loaded yet).
    property var openCodeAgentsDirectory: null
    property var openCodeProvidersList: []
    property var openCodeModelsList: []
    property var openCodeVariants: ({})   // "provider/model" -> variant names (OpenCodeMode.fetchCatalog)
    property var piProviderCandidates: []
    property var piProviderModelMap: ({})
    property var piThinkingModels: ({})   // "provider/model" -> true for models Pi marks as thinking
    property bool piModelsFetching: false
    property var piModelFetchWaiters: []
    property bool voiceEnabled: plasmoid.configuration.voiceEnabled === true
    property bool voiceTtsEnabled: plasmoid.configuration.voiceTtsEnabled === true
    property string compiledSystemPrompt: ""
    // Root-level proxies so root-scope functions can reach UI elements in fullRepresentation
    property string chatInputText: ""
    property var msgListViewRef: null
    property var composerRef: null
    property bool userScrolledUp: false
    // Token counts reported for the reply being streamed.
    property var currentStreamUsage: ({})
    property int queueCounter: 0
    // Popup size: the live size while chat/ResizeHandle.qml drags (0 otherwise), else the saved one.
    property int livePopupWidth: 0
    property int livePopupHeight: 0
    readonly property int popupPreferredWidth: livePopupWidth > 0 ? livePopupWidth : (plasmoid.configuration.customPopupWidth > 0 ? plasmoid.configuration.customPopupWidth : 760)
    readonly property int popupPreferredHeight: livePopupHeight > 0 ? livePopupHeight : (plasmoid.configuration.customPopupHeight > 0 ? plasmoid.configuration.customPopupHeight : 760)
    property bool keysLoaded: false
    // providerId -> API key, read from KWallet (the only place keys are kept).
    readonly property var walletApiKeys: wallet.keys
    property bool _initialLoadDone: false
    property string sessionHistoryLoadError: ""
    // One-line notice about the 1.4.0 move of keys and chats.
    property string privacyNotice: storage.notice
    readonly property var wallet: storage.wallet
    readonly property var chatStore: storage.chatStore
    readonly property var memoryStore: storage.memoryStore  // memories; chat.memory picks those sent (chat/Memory.qml)
    readonly property Chat.Memory memory: Chat.Memory { chat: root }
    readonly property var store: storage
    property bool sessionHistoryLoadBlocked: false
    // A loaded chat had no mode and was given one (stored by loadSessions).
    property bool sessionSourceInferred: false

    signal clearChatInput()
    // A chat was deleted (chat/UndoNotice.qml offers to bring it back).
    signal sessionDeleted(var session, int index)
    signal messagesDropped(string sessionId, var messages)
    readonly property var promptTemplates: PromptTemplates.parse(plasmoid.configuration.promptTemplates)

    function openSettings() {
        Plasmoid.internalAction("configure").trigger();
    }

    Store.Storage {
        id: storage
        configuration: plasmoid.configuration
        helperPath: root.getHelperPath()
        // Chats are stored per widget instance, as they were in the config.
        chatDirectory: decodeURIComponent(String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)).replace(/^file:\/\//, ""))
            + "/kdeaichat/chats/applet-" + plasmoid.id
        currentSessions: function() { return root.sessionHistoryLoadBlocked ? null : root.sessions; }
        onSavesReleased: root.persistSessions()
    }

    Chat.OpenCodeMode { id: openCode; chat: root }

    Chat.PiMode { id: piAgent; chat: root }

    Chat.DirectVariant { id: directVariant; chat: root }

    Chat.Notifier {
        id: notifier
        chat: root
        popupOpen: root.expanded
        replyEnabled: plasmoid.configuration.notifyOnReply
        errorEnabled: plasmoid.configuration.notifyOnError
        scheduledEnabled: plasmoid.configuration.notifyOnScheduled
        soundEnabled: plasmoid.configuration.playNotificationSound
        onOpenChat: function(chatId) { root.switchSession(chatId); root.expanded = true; }
    }

    VoiceManager {
        id: voiceManager

        onTextRecognized: function(text) {
            if (voiceManager.autoSend) {
                root.chatInputText = text;
                root.sendMessage();
            } else {
                root.chatInputText += (root.chatInputText ? " " : "") + text;
            }
        }

        onErrorOccurred: function(errorText) {
            console.error("Voice Error: " + errorText);
            let message = Sec.sanitizeForShell(errorText || "Unknown voice error");
            root.fileReaderDs.connectSource("notify-send -i dialog-error " + Sec.quoteForShell("Voice Error") + " " + Sec.quoteForShell(message) + " #voice-error");
        }
    }

    // Expose voiceManager as a root property so dynamically loaded children
    // (e.g. FullRepresentationContent via Loader) can access it via root.voiceManager
    property var voiceManagerRef: voiceManager

    function ensureWalletLoaded() {
        if (!keysLoaded) {
            keysLoaded = true;
            wallet.load();
        }
    }

    function scheduleWalletReload() {
        walletReloadTimer.restart();
    }

    // chat/Composer.qml registers itself here while the popup content exists.
    function focusInput() {
        Qt.callLater(function() {
            if (root.composerRef)
                root.composerRef.focusInput();
        });
    }

    function fetchPiModels(callback) {
        if (callback)
            root.piModelFetchWaiters = (root.piModelFetchWaiters || []).concat([callback]);
        if (root.piModelsFetching)
            return;
        root.piModelsFetching = true;
        piDiscoveryDs.connectSource("python3 " + Sec.quoteForShell(root.getHelperPath()) + " get_pi_models #pi-models-" + Date.now());
    }

    function triggerInitialLoad() {
        if (_initialLoadDone)
            return ;

        _initialLoadDone = true;
        startupTimer.stop(); // Stop background timer if we triggered early
        // Load sessions immediately so UI has chat list / current chat ready
        root.projects.load();
        sessionManager.loadSessions();
        storage.chatsLoaded();
        // Defer wallet and sys info slightly so initial layout/rendering is unblocked
        lazyWalletTimer.start();
    }

    // The chat list and its persistence (chat/Sessions.qml), chat names
    // (chat/SessionTitles.qml), sending and the queue (chat/SendController.qml),
    // direct-mode requests (chat/DirectRequest.qml), backend events
    // (chat/ReplyEvents.qml), message edits and agent cards (chat/MessageEdits.qml),
    // view scrolling and labels (chat/ChatNavigation.qml), attachments
    // (chat/Attachments.qml), one-off helper commands (chat/HelperCommands.qml)
    // and scheduled runs arriving from the chat folder (chat/ScheduleInbox.qml). The functions below
    // are the root's API for the chat UI (tests/qml/FakeChat.qml mirrors it).
    Chat.Sessions {
        id: sessionManager
        chat: root
        modeSyncRef: modeSync
        helperCommandsRef: helperCommands
    }

    Chat.SessionTitles { id: sessionTitles; chat: root }

    Chat.SendController {
        id: sender
        chat: root
        notifierRef: notifier
        openCodeRef: openCode
        piAgentRef: piAgent
        directToolsRef: directRequest.toolRounds
    }

    Chat.DirectRequest {
        id: directRequest
        chat: root
        directVariantRef: directVariant
    }

    Chat.ReplyEvents {
        id: replyEvents
        chat: root
        notifierRef: notifier
    }

    Chat.MessageEdits {
        id: messageEdits
        chat: root
        openCodeRef: openCode
        piAgentRef: piAgent
        directToolsRef: directRequest.toolRounds
    }

    Chat.ChatNavigation { id: chatNav; chat: root }

    Chat.Attachments { id: attachmentList; chat: root }

    Chat.HelperCommands { id: helperCommands; chat: root }

    Chat.ScheduleInbox { chat: root; notifierRef: notifier; directory: storage.chatDirectory; ready: storage.chatStore.ready; runHelper: storage.runHelper; chatStore: storage.chatStore }

    Chat.ImageStore { id: images; chat: root }   // images of replies, kept as files in the chat's folder
    readonly property var imageStore: images

    function nowTime(ts) { return TimeFormat.nowTime(ts); }

    // Chats (chat/Sessions.qml).
    function persistSessions() { sessionManager.persistSessions(); }
    function sortSessionsByUpdated() { sessionManager.sortSessionsByUpdated(); }
    function sessionSubtitle(sessionData) { return sessionManager.sessionSubtitle(sessionData); }
    function sessionIndexById(sessionId) { return sessionManager.sessionIndexById(sessionId); }
    function getSessionProperty(sessionId, key, defaultValue) { return sessionManager.getSessionProperty(sessionId, key, defaultValue); }
    function setSessionProperty(sessionId, key, value) { sessionManager.setSessionProperty(sessionId, key, value); }
    function setSessionOverrides(sessionId, overrides) { return sessionManager.setSessionOverrides(sessionId, overrides); }
    function createSession(switchToNew, projectId) { sessionManager.createSession(switchToNew, projectId); }
    function resetUnreadableSessionHistory() { sessionManager.resetUnreadableSessionHistory(); }
    function saveCurrentSessionState(touchUpdatedAt) { sessionManager.saveCurrentSessionState(touchUpdatedAt); }
    function setCurrentSessionSource() { sessionManager.setCurrentSessionSource(); }
    function setSessionArchived(sessionId, archived) { sessionManager.setSessionArchived(sessionId, archived); }
    function switchSession(sessionId) { sessionManager.switchSession(sessionId); }
    function deleteSession(sessionId) { sessionManager.deleteSession(sessionId); }
    function currentOpenCodeSessionId(sessionId) { return sessionManager.currentOpenCodeSessionId(sessionId); }
    function setCurrentOpenCodeSessionId(remoteSessionId, sessionId) { sessionManager.setCurrentOpenCodeSessionId(remoteSessionId, sessionId); }
    function clearCurrentOpenCodeSessionIfNeeded() { sessionManager.clearCurrentOpenCodeSessionIfNeeded(); }

    // Chat names (chat/SessionTitles.qml).
    function renameCurrentSession(newTitle) { sessionTitles.renameCurrentSession(newTitle); }
    function startSessionRename(sessionId) { sessionTitles.startSessionRename(sessionId); }
    function cancelSessionRename() { sessionTitles.cancelSessionRename(); }
    function saveSessionRename(sessionId) { sessionTitles.saveSessionRename(sessionId); }
    function nameChatFromFirstMessage(text) { sessionTitles.nameChatFromFirstMessage(text); }
    function maybeGenerateChatTitle() { sessionTitles.maybeGenerateChatTitle(); }

    // Sending and the queue (chat/SendController.qml).
    function requestIsCurrent(sessionId, generation) { return sender.requestIsCurrent(sessionId, generation); }
    function invalidateActiveRequest(processQueue) { sender.invalidateActiveRequest(processQueue); }
    function beginRequest(sessionId) { return sender.beginRequest(sessionId); }
    function pushErrorMessage(text) { sender.pushErrorMessage(text); }
    function sendMessage() { sender.sendMessage(); }
    function sendImageCommand(prompt) { return sender.sendImageCommand(prompt); }
    function sendMessageByIndex(index) { sender.sendMessageByIndex(index); }
    function processNextQueuedMessage() { sender.processNextQueuedMessage(); }
    function stopStreaming() { sender.stopStreaming(); }

    // Direct requests (chat/DirectRequest.qml) and backend events (chat/ReplyEvents.qml).
    function getProviderConfig(provider, sessionId) { return directRequest.getProviderConfig(provider, sessionId); }
    function buildEffectiveSystemPrompt(sessionId) { return directRequest.buildEffectiveSystemPrompt(sessionId); }
    function sessionMessages(sessionId) { return directRequest.sessionMessages(sessionId); }
    function doDirectRequest(cfg, sessionId, generation) { directRequest.doDirectRequest(cfg, sessionId, generation); }
    function resetProviderStreamingState() { replyEvents.resetProviderStreamingState(); }
    function updateMessageAt(index, update) { replyEvents.updateMessageAt(index, update); }
    function findRequestMessage(role, idField, id) { return replyEvents.findRequestMessage(role, idField, id); }
    function applyBackendEvent(event, model, extra) { replyEvents.applyBackendEvent(event, model, extra); }

    // Message edits and agent cards (chat/MessageEdits.qml).
    function deleteMessage(index) { messageEdits.deleteMessage(index); }
    function saveEditedMessage() { messageEdits.saveEditedMessage(); }
    function retryFailedMessage(index) { messageEdits.retryFailedMessage(index); }
    function regenerateResponse(index, promptModifier) { messageEdits.regenerateResponse(index, promptModifier); }
    function respondToPermission(permissionId, approved, always) { messageEdits.respondToPermission(permissionId, approved, always); }
    function respondToQuestion(questionId, answerValue, isReject) { messageEdits.respondToQuestion(questionId, answerValue, isReject); }
    function questionOptionSelected(questionId, questionIndex, label) { return messageEdits.questionOptionSelected(questionId, questionIndex, label); }
    function toggleQuestionOption(questionId, questionIndex, label, multiple) { messageEdits.toggleQuestionOption(questionId, questionIndex, label, multiple); }
    function submitQuestionAnswer(questionId, questions, customField) { messageEdits.submitQuestionAnswer(questionId, questions, customField); }

    // The chat view (chat/ChatNavigation.qml).
    function scrollToBottom(force) { chatNav.scrollToBottom(force); }
    function messageDayKeyAt(index) { return chatNav.messageDayKeyAt(index); }
    function dayDividerLabelForIndex(index) { return chatNav.dayDividerLabelForIndex(index); }
    function formatMessageTime(message, index) { return chatNav.formatMessageTime(message, index); }
    function jumpOneMessageAbove() { chatNav.jumpOneMessageAbove(); }
    function jumpOneMessageBelow() { chatNav.jumpOneMessageBelow(); }
    function formatTokensUsage(tokens, cost) { return chatNav.formatTokensUsage(tokens, cost); }

    // Attachments (chat/Attachments.qml, chat/MessageContent.js) and exports (chat/HelperCommands.qml).
    function fileIconName(filename) { return attachmentList.fileIconName(filename); }
    function attachmentsReadyToSend() { return attachmentList.attachmentsReadyToSend(); }
    function cleanupTemporaryAttachment(path) { attachmentList.cleanupTemporaryAttachment(path); }
    function removeAttachedFile(index) { attachmentList.removeAttachedFile(index); }
    function attachFile(fileUrl) { attachmentList.attachFile(fileUrl); }
    function checkClipboardForAttachments() { attachmentList.checkClipboardForAttachments(); }
    function buildMessageContent(text, attachments, apiType, quotes) { return MessageContent.build(text, attachments, apiType, quotes); }
    function writeExportFile(filePath, content) { helperCommands.writeExportFile(filePath, content); }

    // The mode, provider and model a chat really uses (chat/ModeSync.qml, rules in
    // chat/EffectiveConfig.js). Everything that sends, validates or shows them goes through this.
    function effectiveConfig(sessionId) { return modeSync.effectiveConfig(sessionId); }

    // The provider for requests that always go to a provider (direct chats, naming a chat).
    function getEffectiveProvider(sessionId) {
        return effectiveConfig(sessionId).direct.provider || ProviderService.getSupportedProviders(plasmoid.configuration)[0] || "openai";
    }

    // Puts the widget in the chat's own mode, and re-reads its provider/model
    // when the settings change. A chat never changes mode (chat/ModeSync.qml).
    Chat.ModeSync { id: modeSync; chat: root }

    function applySessionSource(session) { return modeSync.apply(session); }

    function openCodeBaseUrl() {
        var raw = String(plasmoid.configuration.openCodeUrl || "http://127.0.0.1:4096/v1").trim();
        var valid = Sec.validateHttpUrl(raw);
        if (!valid) return "";
        return valid.replace(/\/v1\/?$/, "").replace(/\/$/, "");
    }

    // OpenCode work lives in chat/OpenCodeMode.qml.
    function syncOpenCodeSessionHistory() { openCode.syncHistory(); }
    function fetchOpenCodeAgents(callback) { openCode.fetchAgents(callback); }
    function chooseOpenCodeAgent(value) { openCode.chooseAgent(value); }
    function chooseWorkspace(path) { modeSync.chooseWorkspace(path); }

    function fetchOpenCodeProvidersAndModels(callback) { openCode.fetchCatalog(callback); }

    function providerDisplayName(providerId) {
        return ProviderService.getProviderDisplayName(providerId, plasmoid.configuration);
    }

    function triggerNotificationSound() {
        notifier.playSound();

        if (voiceManager && voiceManager.enabled && (voiceManager.ttsAuto || voiceManager.callModeActive)) {
            // Find the last assistant message
            for (var i = root.messages.length - 1; i >= 0; i--) {
                if (root.messages[i].role === "assistant") {
                    var text = (root.messages[i].content || "").trim();
                    if (text) {
                        root.playingMessageIndex = i;
                        voiceManager.playTTS(text);
                    }
                    break;
                }
            }
        }
    }

    function readClipboardText() {
        clipboardHelper.text = "";
        clipboardHelper.paste();
        return clipboardHelper.text;
    }

    function copyTextToClipboard(textToCopy) {
        clipboardHelper.text = textToCopy || "";
        clipboardHelper.selectAll();
        clipboardHelper.copy();
    }

    function initSystemPrompt() {
        compiledSystemPrompt = String(plasmoid.configuration.systemPrompt || "").trim().substring(0, 100000);
    }

    Plasmoid.title: plasmoid.configuration.appDisplayName || "KDE AI Chat"
    // Panels and the desktop show the compact icon; standalone hosts such as
    // plasmawindowed (used by scripts/dev-run.sh) open the chat directly.
    preferredRepresentation: Qt.application.name === "plasmawindowed" ? fullRepresentation : compactRepresentation
    onHistoryOnlyModeChanged: {
        if (!historyOnlyMode) {
            root.focusInput();
            Qt.callLater(function() { root.scrollToBottom(true); });
        }
    }
    onExpandedChanged: {
        if (expanded) {
            root.triggerInitialLoad();
            root.focusInput();
            Qt.callLater(root.scrollToBottom);
        }
    }
    Component.onCompleted: {
        // Build a usable prompt immediately; the deferred system-information
        // probe will refresh it once its results arrive.
        root.initSystemPrompt();
        helperCommands.stopLegacyWatchdog();
    }
    onMessagesChanged: {
        messageModel.sync(root.messages);
        // The streamed reply keeps its row even if messages before it are removed or added.
        if (root.currentStreamIndex >= 0)
            root.currentStreamIndex = messageModel.indexOfKey(root.currentStreamKey);
    }

    Timer {
        id: startupTimer

        interval: 1000
        running: true
        repeat: false
        onTriggered: {
            root.triggerInitialLoad();
        }
    }

    Timer {
        id: lazyWalletTimer

        interval: 150
        repeat: false
        onTriggered: {
            root.ensureWalletLoaded();
        }
    }

    Timer {
        id: walletReloadTimer
        interval: 250
        repeat: false
        onTriggered: {
            root.keysLoaded = false;
            root.ensureWalletLoaded();
        }
    }

    Connections {
        function onSystemPromptChanged() {
            root.initSystemPrompt();
        }

        function onCustomProvidersJsonChanged() { root.scheduleWalletReload(); }
        function onWalletKeysRevisionChanged() { root.scheduleWalletReload(); }

        target: plasmoid.configuration
    }

    P5Support.DataSource {
        id: piDiscoveryDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            piAgent.applyDiscovery(data["stdout"] || "");
            disconnectSource(sourceName);
        }
    }

    // Starts in the chat's workspace folder (chat/AttachDialog.qml).
    Chat.AttachDialog {
        id: fileDialog
        chat: root
    }

    // Text editor acting as helper to interact with OS text clipboard (copy / paste)
    // Placed offscreen so selection/clipboard actions function correctly in all Qt versions
    TextEdit {
        id: clipboardHelper

        x: -9999
        y: -9999
        width: 1
        height: 1
        visible: true
    }

    function getHelperPath() {
        let urlStr = String(Qt.resolvedUrl("kde_ai_helper.py"));
        if (urlStr.indexOf("file://") === 0)
            urlStr = urlStr.substring(7);
        let path = decodeURIComponent(urlStr);
        return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
    }

    // True when the custom widget icon is an image file (not a KDE icon name).
    function customIconIsImage() {
        var v = (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.customIcon || "") : "";
        if (v === "")
            return false;
        var s = v.trim().toLowerCase();
        if (s.indexOf("file://") === 0 || s.charAt(0) === "/")
            return true;
        return s.endsWith(".png") || s.endsWith(".jpg") || s.endsWith(".jpeg")
            || s.endsWith(".gif") || s.endsWith(".webp") || s.endsWith(".svg")
            || s.endsWith(".svgz") || s.endsWith(".bmp");
    }

    // Turns the stored icon value (a file path) into a QML-usable source URL.
    function customIconImageSource() {
        var v = (plasmoid && plasmoid.configuration) ? (plasmoid.configuration.customIcon || "") : "";
        if (v === "")
            return "";
        if (v.indexOf("file://") === 0)
            return v;
        return "file://" + v;
    }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        // Custom image icons (including animated GIFs) are rendered with an
        // Image element; KDE icon names fall back to Kirigami.Icon.
        Image {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            visible: root.customIconIsImage()
            source: root.customIconIsImage() ? root.customIconImageSource() : ""
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            visible: !root.customIconIsImage()
            source: (plasmoid && plasmoid.configuration && plasmoid.configuration.customIcon)
                ? plasmoid.configuration.customIcon : "dialog-messages"
        }
    }

    fullRepresentation: Item {
        implicitWidth: root.popupPreferredWidth
        implicitHeight: root.popupPreferredHeight
        Layout.minimumWidth: 500
        Layout.minimumHeight: 620
        Layout.preferredWidth: root.popupPreferredWidth
        Layout.preferredHeight: root.popupPreferredHeight
        Component.onCompleted: {
            root.focusInput();
        }
        onVisibleChanged: {
            if (visible) {
                root.focusInput();
                Qt.callLater(root.scrollToBottom);
            }
        }
        // No background or colours of its own: the Plasma popup draws the
        // background and the content follows the Plasma colour scheme.
        Loader {
            id: mainContentLoader

            anchors.fill: parent
            active: root.expanded || root._initialLoadDone
            source: "FullRepresentationContent.qml"

            onStatusChanged: {
                console.log("Loader status changed:", status, (status === Loader.Error ? "ERROR!" : ""));
                if (status === Loader.Error) {
                    console.log("Error string:", sourceComponent ? sourceComponent.errorString() : "No sourceComponent");
                }
            }
        }

    }

}
