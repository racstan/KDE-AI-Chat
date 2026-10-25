// Settings → Harness: whether chats go directly to a provider or through a
// coding agent (OpenCode or Pi), and that agent's defaults. Each chat can
// override them in its own chat settings.
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

    property bool cfg_useOpenCode: false
    property bool cfg_usePi: false
    property alias cfg_openCodeUrl: openCode.url
    property alias cfg_openCodeProvider: openCode.provider
    property alias cfg_openCodeModel: openCode.model
    property alias cfg_piProvider: pi.provider
    property alias cfg_piModel: pi.model

    readonly property string mode: cfg_useOpenCode ? "opencode" : (cfg_usePi ? "pi" : "direct")

    function setMode(next) {
        cfg_useOpenCode = next === "opencode";
        cfg_usePi = next === "pi";
    }

    Store.HelperRunner {
        id: helperRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.FormLayout {
            id: modeForm
            Layout.fillWidth: true
            twinFormLayouts: [openCode, pi]

            QQC2.RadioButton {
                Kirigami.FormData.label: i18n("Send messages:")
                text: i18n("Directly to a provider")
                checked: page.mode === "direct"
                onToggled: if (checked) page.setMode("direct")
            }
            QQC2.RadioButton {
                text: i18n("Through OpenCode")
                checked: page.mode === "opencode"
                onToggled: if (checked) page.setMode("opencode")
            }
            QQC2.RadioButton {
                text: i18n("Through Pi")
                checked: page.mode === "pi"
                onToggled: if (checked) page.setMode("pi")
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: page.mode === "opencode" ? "OpenCode" : "Pi"
                visible: page.mode !== "direct"
            }
        }

        Config.OpenCodeSettings {
            id: openCode
            Layout.fillWidth: true
            visible: page.mode === "opencode"
            active: page.mode === "opencode"
            helper: helperRunner
        }

        Config.PiSettings {
            id: pi
            Layout.fillWidth: true
            visible: page.mode === "pi"
            active: page.mode === "pi"
            helper: helperRunner
        }
    }
}
