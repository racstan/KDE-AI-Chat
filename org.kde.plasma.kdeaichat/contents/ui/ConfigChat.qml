// Settings → Chat: the system prompt, how much history is sent, chat names
// and prompt templates. Each chat can add its own instructions in its chat
// settings.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property alias cfg_enableSystemPrompt: promptCheck.checked
    property alias cfg_systemPrompt: promptArea.text
    property alias cfg_contextMessageLimit: limitSpin.value
    property alias cfg_autoNameChats: autoNameCheck.checked
    property alias cfg_promptTemplates: templates.json

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: promptCheck
            Kirigami.FormData.label: i18n("System prompt:")
            text: i18n("Send these instructions before every chat")
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 20
            // FormLayout sizes its rows from implicit sizes.
            implicitHeight: Kirigami.Units.gridUnit * 8
            enabled: promptCheck.checked

            QQC2.TextArea {
                id: promptArea
                wrapMode: TextEdit.Wrap
                placeholderText: i18n("Instructions for the model…")
                Accessible.name: i18n("System prompt")
            }
        }

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
