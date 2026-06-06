import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_keyToggleSearch: keyToggleSearchField.text
    property alias cfg_keyNewChat: keyNewChatField.text
    property alias cfg_keyToggleHistory: keyToggleHistoryField.text
    property alias cfg_keySettings: keySettingsField.text
    property alias cfg_keyFocusInput: keyFocusInputField.text
    property alias cfg_keyClearInput: keyClearInputField.text
    property alias cfg_keyToggleSearchSidebar: keyToggleSearchSidebarField.text
    property alias cfg_keyNextSession: keyNextSessionField.text
    property alias cfg_keyPrevSession: keyPrevSessionField.text
    property alias cfg_keyRefresh: keyRefreshField.text
    property alias cfg_keyCopyLastReply: keyCopyLastReplyField.text

    function translate(text) {
        if (typeof plasmoid !== "undefined" && plasmoid.api !== undefined) {
            return plasmoid.api.translate(text);
        }
        return text;
    }

    Kirigami.FormLayout {
        id: formLayout

        readonly property int fieldMaxWidth: Kirigami.Units.gridUnit * 18

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            opacity: 0.7
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
            text: page.translate("These are keyboard shortcuts which will work when the widget is active/being used (has focus). Enter standard Qt key sequences (e.g. <code>Ctrl+F</code>, <code>Ctrl+Shift+N</code>, or <code>F1</code>). Leave blank to disable a shortcut.")
            textFormat: Text.RichText
        }

        QQC2.TextField {
            id: keyToggleSearchField
            Kirigami.FormData.label: page.translate("Toggle search:")
            placeholderText: "Ctrl+F"
        }

        QQC2.TextField {
            id: keyNewChatField
            Kirigami.FormData.label: page.translate("New chat:")
            placeholderText: "Ctrl+N"
        }

        QQC2.TextField {
            id: keyToggleHistoryField
            Kirigami.FormData.label: page.translate("Toggle history sidebar:")
            placeholderText: "Ctrl+H"
        }

        QQC2.TextField {
            id: keySettingsField
            Kirigami.FormData.label: page.translate("Open settings:")
            placeholderText: "Ctrl+,"
        }

        QQC2.TextField {
            id: keyFocusInputField
            Kirigami.FormData.label: page.translate("Focus text input:")
            placeholderText: "Ctrl+I"
        }

        QQC2.TextField {
            id: keyClearInputField
            Kirigami.FormData.label: page.translate("Clear text input:")
            placeholderText: "Ctrl+L"
        }

        QQC2.TextField {
            id: keyToggleSearchSidebarField
            Kirigami.FormData.label: page.translate("Focus chat history search:")
            placeholderText: "Ctrl+Shift+K"
        }

        QQC2.TextField {
            id: keyNextSessionField
            Kirigami.FormData.label: page.translate("Next chat session:")
            placeholderText: "Ctrl+Shift+."
        }

        QQC2.TextField {
            id: keyPrevSessionField
            Kirigami.FormData.label: page.translate("Previous chat session:")
            placeholderText: "Ctrl+Shift+,"
        }

        QQC2.TextField {
            id: keyRefreshField
            Kirigami.FormData.label: page.translate("Refresh/reload sessions:")
            placeholderText: "Ctrl+R"
        }

        QQC2.TextField {
            id: keyCopyLastReplyField
            Kirigami.FormData.label: page.translate("Copy last reply:")
            placeholderText: "Ctrl+Shift+C"
        }

        QQC2.Button {
            Kirigami.FormData.label: page.translate("Reset shortcuts:")
            text: page.translate("Reset to defaults")
            onClicked: {
                keyToggleSearchField.text = "Ctrl+F";
                keyNewChatField.text = "Ctrl+N";
                keyToggleHistoryField.text = "Ctrl+H";
                keySettingsField.text = "Ctrl+,";
                keyFocusInputField.text = "Ctrl+I";
                keyClearInputField.text = "Ctrl+L";
                keyToggleSearchSidebarField.text = "Ctrl+Shift+K";
                keyNextSessionField.text = "Ctrl+Shift+.";
                keyPrevSessionField.text = "Ctrl+Shift+,";
                keyRefreshField.text = "Ctrl+R";
                keyCopyLastReplyField.text = "Ctrl+Shift+C";
            }
        }
    }
}
