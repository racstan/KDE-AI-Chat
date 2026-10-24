// Settings → Behavior: the system prompt and how much history is sent.
//
// System-info injection, the user-facts memory and automatic context
// compaction were removed in 1.4.0 (see docs/plan/07-cut-list.md).
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: configPage

    property alias cfg_systemPrompt: customPromptArea.text
    property alias cfg_enableSystemPrompt: enableSystemPromptCheck.checked
    property alias cfg_contextMessageLimit: contextMessageLimitField.value

    readonly property string defaultSystemPrompt: "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts."

    function resetToDefaults() {
        enableSystemPromptCheck.checked = true;
        customPromptArea.text = defaultSystemPrompt;
        contextMessageLimitField.value = -1;
    }

    Kirigami.FormLayout {
        id: formLayout
        wideMode: false
        property int fieldMaxWidth: Kirigami.Units.gridUnit * 35

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("System Prompt")
        }

        QQC2.CheckBox {
            id: enableSystemPromptCheck
            Kirigami.FormData.label: i18n("Enable system prompt:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            text: checked ? i18n("Enabled — instructions sent before every chat") : i18n("Disabled")
        }

        QQC2.ScrollView {
            id: customPromptScroll
            visible: enableSystemPromptCheck.checked
            Kirigami.FormData.label: i18n("Instructions:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: Kirigami.Units.gridUnit * 8
            Layout.preferredHeight: Kirigami.Units.gridUnit * 8
            clip: true

            QQC2.TextArea {
                id: customPromptArea
                placeholderText: i18n("Instructions sent to the model before every chat…")
                wrapMode: Text.Wrap
                width: customPromptScroll.width
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            opacity: 0.72
            font: Kirigami.Theme.smallFont
            text: i18n("Each chat can add its own instructions in the chat settings panel.")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Context")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Messages sent:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            QQC2.SpinBox {
                id: contextMessageLimitField
                from: -1
                to: 9999
            }
            QQC2.Label {
                text: i18n("most recent messages (-1 = up to 100)")
                opacity: 0.72
                font: Kirigami.Theme.smallFont
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Advanced")
        }

        QQC2.Button {
            Kirigami.FormData.label: i18n("Reset settings:")
            text: i18n("Reset to defaults")
            onClicked: configPage.resetToDefaults()
        }
    }
}
