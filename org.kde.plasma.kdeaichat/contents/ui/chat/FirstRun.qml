// First-run setup: while no provider can be chatted with yet, the empty chat
// shows a short card instead of the normal empty state: choose where the AI
// runs (a local server found on this computer, or an online service), give the
// key, pick a model, optionally send a test message.
//
// It is derived, not stored: the card is wanted while no direct-mode provider
// has a model and (unless it is local) a key in KWallet (FirstRun.js). Skip
// sets `firstRunDismissed`. Keys go to KWallet only (store/Wallet.qml), never
// to the config; the provider list (no key) goes to `providersJson`. It never
// touches a chat's mode: in OpenCode or Pi mode it does not appear.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../ProviderService.js" as ProviderService
import "../config" as Config
import "../config/LocalServers.js" as LocalServers
import "FirstRun.js" as Logic

// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Item {
    id: setup

    property var chat: null
    // For tests: replaces XMLHttpRequest.
    property alias xhrFactory: checker.xhrFactory

    readonly property var configuration: chat && chat.plasmoid ? chat.plasmoid.configuration : null
    readonly property var wallet: chat && chat.wallet ? chat.wallet : null
    // Runs helper commands: tests give the chat a fake, the widget has its storage's runner.
    readonly property var helper: !chat ? null : chat.setupCheckHelper ? chat.setupCheckHelper
        : chat.store && chat.store.runHelper ? {"run": chat.store.runHelper} : null
    // Bumped after this card writes the configuration (a plain object does not notify).
    property int revision: 0

    readonly property bool wanted: {
        if (!configuration)
            return false;
        var rev = revision;
        return Logic.wanted({
            "providers": ProviderService.parseProviders(configuration),
            "keys": wallet ? wallet.keys : {},
            "isLocal": setup.isLocal,
            "dismissed": configuration.firstRunDismissed === true,
            "agentMode": configuration.useOpenCode === true || configuration.usePi === true || !!chat.openCodeMode || !!chat.piMode,
            "walletStatus": wallet ? wallet.status : "ready"
        });
    }
    // Stays up through the steps even after the provider works; ends with the test or "Start chatting".
    property bool engaged: false
    property bool done: false
    readonly property bool shown: engaged && !done && !!chat && (chat.messages || []).length === 0

    property string step: "choose"   // choose | key | test
    property var choice: null        // {id, name, keyUrl, preset, server?}
    property var servers: []
    property bool scanning: false
    property bool busy: false
    property string keyText: ""
    property bool modelsReady: false
    property var models: []
    property string model: ""
    property string status: ""
    property string statusKind: "info"
    // What was saved, for the last screen.
    property string savedName: ""
    property string savedModel: ""
    property bool savedLocal: false

    readonly property var cloud: Logic.cloudChoices(ProviderService.presetById)
    readonly property string termsUrl: Logic.TERMS_URL

    function isLocal(entry) {
        return ProviderService.getProviderConfig(entry.id, {"providersJson": JSON.stringify([entry])}).allowEmptyKey;
    }

    onWantedChanged: {
        if (wanted && !done)
            engaged = true;
        else if (!wanted && step === "choose")
            engaged = false;
    }
    onEngagedChanged: if (engaged && !scanning && servers.length === 0) scan()
    Component.onCompleted: if (wanted) engaged = true

    function scan() {
        if (!helper)
            return;
        scanning = true;
        helper.run("local_servers_scan", {}, function(stdout, exitCode) {
            setup.servers = LocalServers.parse(stdout, exitCode) || [];
            setup.scanning = false;
        });
    }

    function setStatus(text, kind) {
        status = text;
        statusKind = kind || "info";
    }

    function resetKeyStep() {
        keyText = "";
        modelsReady = false;
        models = [];
        model = "";
        setStatus("");
    }

    // The provider entry for the current choice with `model`.
    function entryFor(model) {
        var overrides = choice.server ? LocalServers.providerFor(choice.server).overrides : {};
        var id = choice.server && choice.preset.id === "custom"
            ? ProviderService.newProviderId(ProviderService.parseProviders(configuration), "custom") : choice.preset.id;
        return Logic.makeEntry(choice.preset, id, model, overrides);
    }

    function chooseCloud(item) {
        resetKeyStep();
        choice = item;
        step = "key";
    }

    // A found server: no key means one click saves it; one that asks for a key goes to the key step.
    function chooseServer(server) {
        var made = LocalServers.providerFor(server);
        var preset = ProviderService.presetById(made.presetId) || ProviderService.presetById("custom");
        resetKeyStep();
        choice = {"id": preset.id, "name": server.kind === "openai" ? i18n("OpenAI-compatible server") : server.name, "keyUrl": "", "preset": preset, "server": server};
        if (made.needsKey) {
            step = "key";
            return;
        }
        commit(entryFor(made.overrides.model), "");
    }

    function back() {
        resetKeyStep();
        step = "choose";
    }

    // Lists the provider's models with the key (a wrong key is told apart here).
    function checkKey() {
        var key = keyText.trim();
        var entry = entryFor("");
        busy = true;
        setStatus("");
        checker.loadModels(entry, key, true, function(result) {
            setup.busy = false;
            if (!result.ok) {
                setup.setStatus(result.error === "rejected" ? i18n("%1 did not accept this key. Check you copied the whole key.", entry.name)
                    : result.error === "http" ? i18n("%1 answered with an error (HTTP %2). Try again in a moment.", entry.name, result.status)
                    : i18n("Could not reach %1. Check your connection.", checker.hostOf(entry.baseUrl)), "error");
                return;
            }
            var list = result.chat.length > 0 ? result.chat : result.all;
            if (list.length === 0) {
                setup.setStatus(i18n("The key works, but %1 listed no models.", entry.name), "error");
                return;
            }
            setup.models = list;
            setup.model = Logic.pickModel(list, entry.model);
            setup.modelsReady = true;
        });
    }

    // Checks the key with the chosen model, then saves.
    function saveModel() {
        var key = keyText.trim();
        var entry = entryFor(model);
        busy = true;
        setStatus("");
        checker.verify(entry, key, false, function(result) {
            if (result.state === "key_rejected" || result.state === "model_unavailable") {
                setup.busy = false;
                setup.setStatus(checker.describe(entry, result).text, "error");
                return;
            }
            setup.commit(entry, key);
        });
    }

    // The key goes to KWallet first; only when that worked is the provider (no key) saved and made the default.
    function commit(entry, key) {
        busy = true;
        function finish() {
            setup.savedName = entry.name;
            setup.savedModel = entry.model;
            setup.savedLocal = setup.isLocal(entry);
            setup.step = "test";
            setup.configuration.providersJson = ProviderService.serializeProviders(Logic.upsert(ProviderService.parseProviders(setup.configuration), entry));
            setup.configuration.provider = entry.id;
            setup.revision += 1;
            setup.busy = false;
        }
        if (key === "") {
            finish();
            return;
        }
        if (!wallet) {
            busy = false;
            setStatus(i18n("KWallet is not available, so the key cannot be saved."), "error");
            return;
        }
        wallet.write(entry.id, key, function(ok) {
            if (!ok) {
                setup.busy = false;
                setup.setStatus(setup.wallet.statusMessage(), "error");
                return;
            }
            if (setup.configuration.walletKeysRevision !== undefined)
                setup.configuration.walletKeysRevision = (Number(setup.configuration.walletKeysRevision) || 0) + 1;
            finish();
        });
    }

    function sendTest() {
        done = true;
        chat.chatInputText = i18n("Hello! Please reply with one short sentence so I know this works.");
        chat.sendMessage();
    }

    function finish() {
        done = true;
        if (chat && chat.focusInput)
            chat.focusInput();
    }

    // Leaves the setup for Settings → Connection; it stays away until a provider works.
    function skip() {
        configuration.firstRunDismissed = true;
        revision += 1;
        done = true;
        chat.openSettings();
    }

    Config.ProviderChecker {
        id: checker
    }

    visible: shown

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, card.implicitHeight + Kirigami.Units.largeSpacing * 2)
        boundsBehavior: Flickable.StopAtBounds
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        ColumnLayout {
            id: card
            objectName: "firstRunCard"
            width: Math.min(flick.width - Kirigami.Units.largeSpacing * 2, Kirigami.Units.gridUnit * 28)
            x: (flick.width - width) / 2
            y: Math.max(Kirigami.Units.largeSpacing, (flick.height - implicitHeight) / 2)
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                objectName: "firstRunTitle"
                level: 2
                text: i18n("Let's get you chatting")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            FirstRunChoose {
                visible: setup.step === "choose"
                ctl: setup
                Layout.fillWidth: true
            }

            Loader {
                active: setup.step === "key"
                visible: active
                Layout.fillWidth: true
                sourceComponent: FirstRunKey {
                    ctl: setup
                }
            }

            FirstRunTest {
                visible: setup.step === "test"
                ctl: setup
                Layout.fillWidth: true
            }
        }
    }
}
