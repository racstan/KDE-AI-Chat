// Compiles every QML file shipped in the widget, offscreen.
//
// A compile error (unknown property, missing type, bad import) makes Plasma
// drop the whole component at runtime, e.g. the chat popup failing to open.
// Those errors surface here as Component.Error without needing Plasma.
import QtQuick
import QtTest

TestCase {
    name: "ComponentsLoad"

    readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
    readonly property url configDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/config/")

    function test_compiles_data() {
        return [
            { tag: "main", url: uiDir + "main.qml" },
            { tag: "FullRepresentationContent", url: uiDir + "FullRepresentationContent.qml" },
            { tag: "ChatSettingsDialog", url: uiDir + "ChatSettingsDialog.qml" },
            { tag: "ScheduleDialog", url: uiDir + "ScheduleDialog.qml" },
            { tag: "VoiceManager", url: uiDir + "VoiceManager.qml" },
            { tag: "store/Wallet", url: uiDir + "store/Wallet.qml" },
            { tag: "store/ChatStore", url: uiDir + "store/ChatStore.qml" },
            { tag: "store/HelperRunner", url: uiDir + "store/HelperRunner.qml" },
            { tag: "store/Migration", url: uiDir + "store/Migration.qml" },
            { tag: "store/Storage", url: uiDir + "store/Storage.qml" },
            { tag: "chat/NoticeBanner", url: uiDir + "chat/NoticeBanner.qml" },
            { tag: "config/ProvidersPanel", url: uiDir + "config/ProvidersPanel.qml" },
            { tag: "config/ProviderEditor", url: uiDir + "config/ProviderEditor.qml" },
            { tag: "config/ProviderRow", url: uiDir + "config/ProviderRow.qml" },
            { tag: "config/ProviderChecker", url: uiDir + "config/ProviderChecker.qml" },
            { tag: "chat/OpenCodeMode", url: uiDir + "chat/OpenCodeMode.qml" },
            { tag: "chat/ModeSync", url: uiDir + "chat/ModeSync.qml" },
            { tag: "chat/AttachDialog", url: uiDir + "chat/AttachDialog.qml" },
            { tag: "chat/PiMode", url: uiDir + "chat/PiMode.qml" },
            { tag: "chat/PermissionButtons", url: uiDir + "chat/PermissionButtons.qml" },
            { tag: "chat/PiChatSettings", url: uiDir + "chat/PiChatSettings.qml" },
            { tag: "chat/MessageModel", url: uiDir + "chat/MessageModel.qml" },
            { tag: "chat/ChatView", url: uiDir + "chat/ChatView.qml" },
            { tag: "chat/MessageDelegate", url: uiDir + "chat/MessageDelegate.qml" },
            { tag: "chat/MessageBody", url: uiDir + "chat/MessageBody.qml" },
            { tag: "chat/MessageText", url: uiDir + "chat/MessageText.qml" },
            { tag: "chat/CodeBlock", url: uiDir + "chat/CodeBlock.qml" },
            { tag: "chat/ReasoningBlock", url: uiDir + "chat/ReasoningBlock.qml" },
            { tag: "chat/AttachmentChips", url: uiDir + "chat/AttachmentChips.qml" },
            { tag: "chat/MessageImages", url: uiDir + "chat/MessageImages.qml" },
            { tag: "chat/ImageViewer", url: uiDir + "chat/ImageViewer.qml" },
            { tag: "chat/ImageStore", url: uiDir + "chat/ImageStore.qml" },
            { tag: "chat/ImageJobs", url: uiDir + "chat/ImageJobs.qml" },
            { tag: "chat/ImageJobCard", url: uiDir + "chat/ImageJobCard.qml" },
            { tag: "config/ImageProvidersPanel", url: uiDir + "config/ImageProvidersPanel.qml" },
            { tag: "config/ImageProviderEditor", url: uiDir + "config/ImageProviderEditor.qml" },
            { tag: "config/ImageModels", url: uiDir + "config/ImageModels.qml" },
            { tag: "chat/QuestionCard", url: uiDir + "chat/QuestionCard.qml" },
            { tag: "chat/ContextList", url: uiDir + "chat/ContextList.qml" },
            { tag: "chat/MessageActions", url: uiDir + "chat/MessageActions.qml" },
            { tag: "chat/StreamBuffer", url: uiDir + "chat/StreamBuffer.qml" },
            { tag: "chat/StreamingText", url: uiDir + "chat/StreamingText.qml" },
            { tag: "chat/DeferredBuilder", url: uiDir + "chat/DeferredBuilder.qml" },
            { tag: "chat/ChatHeader", url: uiDir + "chat/ChatHeader.qml" },
            { tag: "chat/WorkspaceBar", url: uiDir + "chat/WorkspaceBar.qml" },
            { tag: "chat/RenameRow", url: uiDir + "chat/RenameRow.qml" },
            { tag: "chat/Composer", url: uiDir + "chat/Composer.qml" },
            { tag: "chat/SessionList", url: uiDir + "chat/SessionList.qml" },
            { tag: "chat/ChatBody", url: uiDir + "chat/ChatBody.qml" },
            { tag: "chat/ChatInfoSummary", url: uiDir + "chat/ChatInfoSummary.qml" },
            { tag: "chat/ChatOverridesForm", url: uiDir + "chat/ChatOverridesForm.qml" },
            { tag: "chat/ChatSettingsDraft", url: uiDir + "chat/ChatSettingsDraft.qml" },
            { tag: "chat/ResizeHandle", url: uiDir + "chat/ResizeHandle.qml" },
            { tag: "chat/ChatShortcuts", url: uiDir + "chat/ChatShortcuts.qml" },
            { tag: "chat/ComposerStatus", url: uiDir + "chat/ComposerStatus.qml" },
            { tag: "chat/EmptyState", url: uiDir + "chat/EmptyState.qml" },
            { tag: "chat/ErrorActions", url: uiDir + "chat/ErrorActions.qml" },
            { tag: "chat/MonoBlock", url: uiDir + "chat/MonoBlock.qml" },
            { tag: "chat/PermissionDetail", url: uiDir + "chat/PermissionDetail.qml" },
            { tag: "chat/TemplateSuggestions", url: uiDir + "chat/TemplateSuggestions.qml" },
            { tag: "chat/PrimaryButton", url: uiDir + "chat/PrimaryButton.qml" },
            { tag: "chat/ToolCard", url: uiDir + "chat/ToolCard.qml" },
            { tag: "chat/UndoNotice", url: uiDir + "chat/UndoNotice.qml" },
            { tag: "ConfigConnection", url: uiDir + "ConfigConnection.qml" },
            { tag: "ConfigChat", url: uiDir + "ConfigChat.qml" },
            { tag: "ConfigSchedules", url: uiDir + "ConfigSchedules.qml" },
            { tag: "ConfigVoice", url: uiDir + "ConfigVoice.qml" },
            { tag: "ConfigAppearance", url: uiDir + "ConfigAppearance.qml" },
            { tag: "config/ModeChooser", url: uiDir + "config/ModeChooser.qml" },
            { tag: "config/RequestOptions", url: uiDir + "config/RequestOptions.qml" },
            { tag: "components/ModelPicker", url: uiDir + "components/ModelPicker.qml" },
            { tag: "components/VariantPicker", url: uiDir + "components/VariantPicker.qml" },
            { tag: "chat/DirectVariant", url: uiDir + "chat/DirectVariant.qml" },
            { tag: "config/OpenCodeSettings", url: uiDir + "config/OpenCodeSettings.qml" },
            { tag: "config/PiSettings", url: uiDir + "config/PiSettings.qml" },
            { tag: "config/TemplatesEditor", url: uiDir + "config/TemplatesEditor.qml" },
            { tag: "config/SchedulerService", url: uiDir + "config/SchedulerService.qml" },
            { tag: "config/VoiceEngine", url: uiDir + "config/VoiceEngine.qml" },
            { tag: "config/VoiceStatusGrid", url: uiDir + "config/VoiceStatusGrid.qml" },
            { tag: "config", url: configDir + "config.qml" }
        ];
    }

    function test_compiles(data) {
        const component = Qt.createComponent(data.url, Component.PreferSynchronous);
        tryVerify(() => component.status !== Component.Loading, 10000);
        verify(component.status === Component.Ready, component.errorString());
    }
}
