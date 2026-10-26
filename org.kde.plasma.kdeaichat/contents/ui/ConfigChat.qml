// Settings → Chat: how much history is sent, chat names, questions, the
// default workspace of new chats, per-chat model settings and prompt
// templates. The instructions sent before every chat are on the Personality
// page. Each chat can add its own instructions and workspace in its chat settings.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property alias cfg_contextMessageLimit: limitSpin.value
    property alias cfg_autoNameChats: autoNameCheck.checked
    property alias cfg_allowAskUser: askUserCheck.checked
    property alias cfg_promptTemplates: templates.json
    property alias cfg_openCodeWorkspaceCwd: workspaceField.text
    property alias cfg_perChatModelSettings: perChatSwitch.checked
    // "chat" or "main" (see chat/EffectiveConfig.js).
    property string cfg_perChatPriority: "chat"

    FolderDialog {
        id: workspaceDialog
        title: i18n("Default workspace for new chats")
        onAccepted: {
            var path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.substring(7));
            workspaceField.text = path;
        }
    }

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: limitSpin
            Kirigami.FormData.label: i18n("Earlier messages sent:")
            from: -1
            to: 99
            editable: true
            textFromValue: function(value) {
                return value < 0 ? i18n("All (up to 100)") : String(value);
            }
            valueFromText: function(text) {
                var number = parseInt(text, 10);
                return isNaN(number) ? -1 : number;
            }
            Accessible.name: i18n("Number of earlier messages sent with each request")
        }

        QQC2.CheckBox {
            id: autoNameCheck
            Kirigami.FormData.label: i18n("Chat names:")
            text: i18n("Let the model name new chats")
        }

        QQC2.CheckBox {
            id: askUserCheck
            objectName: "askUserCheck"
            Kirigami.FormData.label: i18n("Questions:")
            text: i18n("Let the AI ask me questions")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.Wrap
            color: Kirigami.Theme.disabledTextColor
            text: i18n("When it needs a choice or a missing detail, the AI can ask you in the chat and wait for your answer. Applies to chats with a provider; the agent modes ask in their own way.")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Default workspace for new chats:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: workspaceField
                objectName: "defaultWorkspaceField"
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                maximumLength: 4096
                placeholderText: i18n("No workspace")
                Accessible.name: i18n("Default workspace for new chats")
            }
            QQC2.Button {
                icon.name: "folder-open"
                onClicked: workspaceDialog.open()
                Accessible.name: i18n("Choose a folder")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a folder")
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.Wrap
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Copied into a chat when it is created. Leave empty for no workspace. Each chat can change its own in the bar above the chat.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Model settings per chat")
        }

        QQC2.Switch {
            id: perChatSwitch
            objectName: "perChatSwitch"
            Kirigami.FormData.label: i18n("Chats:")
            text: i18n("Let chats have their own model settings")
            Accessible.description: i18n("When off, every chat uses the model settings from Settings. A chat's own settings are kept but ignored.")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.Wrap
            color: Kirigami.Theme.disabledTextColor
            text: perChatSwitch.checked
                ? i18n("A chat can choose its own mode (provider, OpenCode or Pi), provider and model in its Chat info panel.")
                : i18n("Every chat uses the mode, provider and model from Settings. Any model settings a chat already has are kept, and come back if you turn this on.")
        }

        QQC2.RadioButton {
            id: chatWinsRadio
            objectName: "chatWinsRadio"
            visible: perChatSwitch.checked
            Kirigami.FormData.label: i18n("When they differ:")
            text: i18n("This chat's settings win")
            checked: page.cfg_perChatPriority !== "main"
            onClicked: page.cfg_perChatPriority = "chat"
        }

        QQC2.RadioButton {
            id: mainWinsRadio
            objectName: "mainWinsRadio"
            visible: perChatSwitch.checked
            text: i18n("Main settings win")
            checked: page.cfg_perChatPriority === "main"
            onClicked: page.cfg_perChatPriority = "main"
        }

        QQC2.Label {
            visible: perChatSwitch.checked
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.Wrap
            color: Kirigami.Theme.disabledTextColor
            text: chatWinsRadio.checked
                ? i18n("A chat that has its own settings uses them; anything it leaves empty comes from the main settings.")
                : i18n("The main settings are used. A chat's own settings only fill in what the main settings leave empty, such as a model.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Prompt templates")
        }

        Config.TemplatesEditor {
            id: templates
            Kirigami.FormData.label: i18n("Insert with /name:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Layout.fillWidth: true
        }
    }
}
