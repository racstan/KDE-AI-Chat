// Settings → Support: a link to support the developer, the terms of use and
// the credits. The name, version, author, license, website and bug link are on
// the About page Plasma adds to every widget's settings (from metadata.json),
// so they are not repeated here. Nothing here is a setting (no cfg_ property);
// Plasma still hands every page its cfg_ values, and a page without them just
// ignores them (like Storage).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    readonly property string donateUrl: "https://buymeacoffee.com/rachitasthana"
    readonly property string termsUrl: "https://github.com/racstan/KDE-AI-Chat/blob/master/TERMS.md"
    readonly property string speechNoteUrl: "https://github.com/mkiol/dsnote"
    // Opens a link; tests replace it.
    property var openUrl: function(url) { Qt.openUrlExternally(url); }

    Kirigami.FormLayout {
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Support the developer")
        }

        QQC2.Button {
            objectName: "donateButton"
            Kirigami.FormData.label: i18n("Like it?")
            text: i18n("Buy Me a Coffee")
            icon.name: "emblem-favorite"
            onClicked: page.openUrl(page.donateUrl)
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: page.donateUrl
        }

        Config.SettingHelp {
            objectName: "donateHelp"
            text: i18n("KDE AI Chat is free. If it helps you, you can thank the developer with a small gift; this opens buymeacoffee.com in your web browser.")
        }

        QQC2.Button {
            objectName: "termsButton"
            Kirigami.FormData.label: i18n("Terms of use:")
            text: i18n("Read the terms")
            icon.name: "documentinfo"
            onClicked: page.openUrl(page.termsUrl)
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: page.termsUrl
        }

        Config.SettingHelp {
            objectName: "termsHelp"
            text: i18n("In short: the widget comes without warranty and collects nothing itself. Your messages go only to the services you choose, under their terms; you are responsible for your keys, for the costs on your accounts (scheduled prompts run by themselves) and for how you use the answers. Opens the full terms in your web browser.")
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Credits")
        }

        QQC2.Label {
            objectName: "aboutCredits"
            Kirigami.FormData.label: i18n("Voice:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: i18n("Speech, models and GPU support by <a href=\"%1\">Speech Note</a>, © Michał Kosciesza, MPL-2.0", page.speechNoteUrl)
            onLinkActivated: function(link) { page.openUrl(link); }
        }

        Config.SettingHelp {
            text: i18n("The name, version, author, license and website are on the About page of these settings.")
        }
    }
}
