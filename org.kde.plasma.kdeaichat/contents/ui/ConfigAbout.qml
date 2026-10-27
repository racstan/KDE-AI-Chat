// Settings → About: the widget's name, version, what it is, its license,
// author, source link and credits, a link to support the developer and one to
// the terms of use. Nothing here is a setting (no cfg_ property); Plasma still
// hands every page its cfg_ values, and a page without them just ignores them
// (like Storage). The version comes from metadata.json (plasmoid.metaData).
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
    readonly property string sourceUrl: "https://github.com/racstan/KDE-AI-Chat"
    readonly property string speechNoteUrl: "https://github.com/mkiol/dsnote"
    // From metadata.json; a test or a plain QML run has no plasmoid.
    property string version: typeof plasmoid !== "undefined" && plasmoid && plasmoid.metaData ? String(plasmoid.metaData.version) : "dev"
    // Opens a link; tests replace it.
    property var openUrl: function(url) { Qt.openUrlExternally(url); }

    Kirigami.FormLayout {
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("KDE AI Chat")
        }

        QQC2.Label {
            objectName: "aboutVersion"
            Kirigami.FormData.label: i18n("Version:")
            text: page.version
        }

        QQC2.Label {
            objectName: "aboutDescription"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.Wrap
            text: i18n("A chat with AI models (online services or ones on your computer, OpenCode and Pi agents) in a Plasma widget.")
        }

        QQC2.Label {
            objectName: "aboutLicense"
            Kirigami.FormData.label: i18n("License:")
            text: i18n("GPL-3.0-or-later")
        }

        QQC2.Label {
            objectName: "aboutAuthor"
            Kirigami.FormData.label: i18n("Author:")
            text: "Rachit Asthana"
        }

        QQC2.Button {
            objectName: "sourceButton"
            Kirigami.FormData.label: i18n("Source code:")
            text: i18n("Open the project page")
            icon.name: "applications-development"
            onClicked: page.openUrl(page.sourceUrl)
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: page.sourceUrl
        }

        Config.SettingHelp {
            text: i18n("The code, the issue tracker and the releases are on GitHub; this opens the page in your web browser.")
        }

        QQC2.Label {
            objectName: "aboutCredits"
            Kirigami.FormData.label: i18n("Credits:")
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: i18n("Speech, models and GPU support by <a href=\"%1\">Speech Note</a>, © Michał Kosciesza, MPL-2.0", page.speechNoteUrl)
            onLinkActivated: function(link) { page.openUrl(link); }
        }

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
    }
}
