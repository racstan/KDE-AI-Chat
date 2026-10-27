// Settings → Desktop integration: ask the widget from KRunner and from Dolphin.
//
// Both need small files outside the widget (a KRunner plugin and a Dolphin menu entry), so they are opt-in:
// both switches are off by default. On OK/Apply, saveConfig() asks the helper (desktop_sync) to install the
// files of the switches that are on and to remove those of the switches that are off. Nothing here holds a
// secret; the helper only ever touches its own files (see kdeaichat/desktop_integration.py).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "store" as Store
import "config" as Config

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property alias cfg_krunnerEnabled: krunnerSwitch.checked
    property alias cfg_krunnerPrefix: prefixField.text
    property alias cfg_dolphinMenuEnabled: dolphinSwitch.checked

    // Runs the helper's commands; tests pass a fake with run(command, payload, onDone).
    property var helperRunner: defaultRunner
    // What the last desktop_sync/desktop_status said (null until it arrives).
    property var status: null
    property string errorText: ""
    // The prefix as the runner will use it: one word, no spaces.
    readonly property string cleanPrefix: {
        var word = String(prefixField.text).trim();
        return word.length > 0 && word.length <= 24 && !/\s/.test(word) ? word : "ai";
    }
    readonly property bool prefixValid: String(prefixField.text).trim() === "" || String(prefixField.text).trim() === cleanPrefix

    // Called by Plasma on OK/Apply, before it saves the cfg_ values.
    function saveConfig() {
        helperRunner.run("desktop_sync", {
            "krunner": krunnerSwitch.checked, "dolphin": dolphinSwitch.checked, "prefix": cleanPrefix,
            "restart_krunner": status === null || status.krunner !== krunnerSwitch.checked
        }, function(stdout, exitCode, stderr) { page.takeStatus(stdout); });
    }

    function takeStatus(stdout) {
        try {
            const data = JSON.parse(String(stdout).trim().split("\n").pop());
            page.status = data;
            page.errorText = data.errors && data.errors.length > 0 ? data.errors.join(" ") : "";
        } catch (e) {
            page.errorText = i18n("Could not set this up. Try again.");
        }
    }

    Component.onCompleted: helperRunner.run("desktop_status", {}, function(stdout) { page.takeStatus(stdout); })

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            text: i18n("Ask KDE AI Chat from other places on your desktop. These add small files outside the widget, so both are off until you turn them on, and the files are removed again when you turn them off. The widget has to be on your panel or desktop to receive the question.")
        }

        Kirigami.InlineMessage {
            objectName: "desktopError"
            Layout.fillWidth: true
            visible: page.errorText !== ""
            type: Kirigami.MessageType.Error
            text: page.errorText
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Switch {
                id: krunnerSwitch
                objectName: "krunnerSwitch"
                Kirigami.FormData.label: i18n("KRunner:")
                text: i18n("Ask from KRunner")
            }

            Config.SettingHelp {
                text: i18n("Adds KDE AI Chat to KRunner (Alt+Space). Type the word below and a question, for example “ai why is the sky blue”, and press Enter: the widget opens and sends it. Choose “Ask in a new chat” to start a fresh chat instead. KRunner may need a moment, or a restart of KRunner, to notice the change.")
            }

            QQC2.TextField {
                id: prefixField
                objectName: "krunnerPrefix"
                Kirigami.FormData.label: i18n("Word to type first:")
                enabled: krunnerSwitch.checked
                maximumLength: 24
                placeholderText: "ai"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            }

            Config.SettingHelp {
                text: page.prefixValid ? i18n("KRunner only offers to ask KDE AI Chat when what you type starts with this word and a space. Use one short word with no spaces.")
                                       : i18n("Use one word without spaces. “%1” will be used instead.", page.cleanPrefix)
            }

            QQC2.Switch {
                id: dolphinSwitch
                objectName: "dolphinSwitch"
                Kirigami.FormData.label: i18n("Dolphin:")
                text: i18n("“Ask KDE AI Chat about this file” in Dolphin")
            }

            Config.SettingHelp {
                text: i18n("Adds an entry to Dolphin’s right-click menu for text files, PDFs, Word documents and pictures. It attaches the file to your message in the widget and opens it, ready for your question. Its contents are sent to the AI only when you send the message.")
            }
        }

        QQC2.Label {
            objectName: "desktopStatus"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.75
            visible: page.status !== null
            text: page.status === null ? "" : i18n("Installed now: KRunner %1, Dolphin %2.",
                  page.status.krunner ? i18n("yes") : i18n("no"), page.status.dolphin ? i18n("yes") : i18n("no"))
        }
    }
}
