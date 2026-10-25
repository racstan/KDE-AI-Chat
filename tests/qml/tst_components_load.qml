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
            { tag: "chat/OpenCodeMode", url: uiDir + "chat/OpenCodeMode.qml" },
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
            { tag: "chat/QuestionCard", url: uiDir + "chat/QuestionCard.qml" },
            { tag: "chat/ContextList", url: uiDir + "chat/ContextList.qml" },
            { tag: "chat/MessageActions", url: uiDir + "chat/MessageActions.qml" },
            { tag: "chat/ChatHeader", url: uiDir + "chat/ChatHeader.qml" },
            { tag: "chat/OpenCodeBar", url: uiDir + "chat/OpenCodeBar.qml" },
            { tag: "chat/RenameRow", url: uiDir + "chat/RenameRow.qml" },
            { tag: "chat/Composer", url: uiDir + "chat/Composer.qml" },
            { tag: "chat/SessionList", url: uiDir + "chat/SessionList.qml" },
            { tag: "ConfigGeneral", url: uiDir + "ConfigGeneral.qml" },
            { tag: "ConfigSystemPrompt", url: uiDir + "ConfigSystemPrompt.qml" },
            { tag: "ConfigVoice", url: uiDir + "ConfigVoice.qml" },
            { tag: "ConfigOther", url: uiDir + "ConfigOther.qml" },
            { tag: "config", url: configDir + "config.qml" }
        ];
    }

    function test_compiles(data) {
        const component = Qt.createComponent(data.url, Component.PreferSynchronous);
        tryVerify(() => component.status !== Component.Loading, 10000);
        verify(component.status === Component.Ready, component.errorString());
    }
}
