// Settings → Connection: how chats reach a model, and everything that way
// needs, on one page. The choice at the top (a provider directly, OpenCode or
// Pi) decides which section is shown below it; the other modes' settings stay
// saved. Each chat can override the model in its own chat settings.
//
//   Directly to a provider: the provider list (keys in KWallet, never in the
//     config), time limit, streaming.
//   Through OpenCode: server address and controls, provider, model and variant.
//   Through Pi: provider, model and thinking level.
// A model's variant (reasoning level) has a picker only when the model has
// variants; the direct providers' variants are chosen in the provider editor.
import QtQuick
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "store" as Store
import "config" as Config
import "config/LocalServers.js" as LocalServers

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property bool cfg_useOpenCode: false
    property bool cfg_usePi: false
    property alias cfg_openCodeUrl: openCode.url
    property alias cfg_openCodeProvider: openCode.provider
    property alias cfg_openCodeModel: openCode.model
    property alias cfg_openCodeVariant: openCode.variant
    property alias cfg_piProvider: pi.provider
    property alias cfg_piModel: pi.model
    property alias cfg_piThinking: pi.thinking
    // 0 means no time limit.
    property alias cfg_requestTimeout: requests.timeout
    property alias cfg_disableStreaming: requests.disableStreaming

    readonly property string mode: cfg_useOpenCode ? "opencode" : (cfg_usePi ? "pi" : "direct")
    readonly property var configuration: typeof plasmoid !== "undefined" && plasmoid ? plasmoid.configuration : null
    // Only the direct mode uses API keys, so the wallet is opened for it alone.
    // (A property so a test can pass a fake.)
    property Store.Wallet wallet: Store.Wallet {}
    property bool walletRequested: false
    // Runs the helper's commands (Pi's model list, the OpenCode server); a property so a test can pass a fake.
    property var helperRunner: defaultRunner

    function setMode(next) {
        cfg_useOpenCode = next === "opencode";
        cfg_usePi = next === "pi";
    }

    function loadWalletForDirectMode() {
        if (mode === "direct" && !walletRequested) {
            walletRequested = true;
            wallet.load();
        }
    }

    onModeChanged: loadWalletForDirectMode()
    Component.onCompleted: loadWalletForDirectMode()

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Config.ModeChooser {
            id: chooser
            objectName: "modeChooser"
            Layout.fillWidth: true
            mode: page.mode
            twinFormLayouts: [openCode, pi, requests]
            onChosen: function(next) { page.setMode(next); }
        }

        Config.ProvidersPanel {
            id: providersPanel
            objectName: "providersSection"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 40
            Layout.alignment: Qt.AlignHCenter
            visible: page.mode === "direct"
            configuration: page.configuration
            wallet: page.wallet
        }

        Config.SettingHelp {
            objectName: "providersHelp"
            visible: page.mode === "direct"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 40
            Layout.alignment: Qt.AlignHCenter
            text: i18n("A provider is an AI service, or an AI program on your computer. Add one with the web address and key its website gives you (a program on your own computer usually needs none). The default one answers new chats.")
            details: i18n("Picture services for /image (such as AI Horde) have their own list; they never answer chats.")
        }

        Config.LocalServers {
            objectName: "localServers"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 40
            Layout.alignment: Qt.AlignHCenter
            visible: page.mode === "direct"
            active: page.mode === "direct"
            helper: page.helperRunner
            providers: providersPanel.providers
            busy: providersPanel.editingIndex >= 0
            onUseServer: function(server) {
                var made = LocalServers.providerFor(server);
                providersPanel.skipModelFetch = made.needsKey;
                providersPanel.addFromPreset(made.presetId, made.overrides);
                if (made.needsKey)
                    providersPanel.setStatus(i18n("This server asks for a key. Enter it, then Save; the models are listed after that."), "info");
            }
        }

        Config.RequestOptions {
            id: requests
            objectName: "requestsSection"
            Layout.fillWidth: true
            visible: page.mode === "direct"
        }

        Config.OpenCodeSettings {
            id: openCode
            objectName: "openCodeSection"
            Layout.fillWidth: true
            visible: page.mode === "opencode"
            active: page.mode === "opencode"
            helper: page.helperRunner
        }

        Config.PiSettings {
            id: pi
            objectName: "piSection"
            Layout.fillWidth: true
            visible: page.mode === "pi"
            active: page.mode === "pi"
            helper: page.helperRunner
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // What this way of chatting needs on this computer, and how to fix what's missing.
        Config.SetupCheck {
            objectName: "setupCheck"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 40
            Layout.alignment: Qt.AlignHCenter
            configuration: page.configuration
            wallet: page.wallet
            mode: page.mode
            openCodeUrl: openCode.url
            helper: page.helperRunner
        }
    }
}
