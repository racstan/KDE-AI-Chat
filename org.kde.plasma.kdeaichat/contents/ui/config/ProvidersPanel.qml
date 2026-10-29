// Settings: the user's direct-mode providers.
//
// A list (stored as `providersJson`, see ProviderService.js) with add from a
// preset, edit, remove and "use by default". API keys are written to KWallet
// under the provider id and never to the config. Changes save immediately.
//
// Saving a provider with a new or changed key first checks it with the
// provider (ProviderChecker.qml): a rejected key is not saved; a model that
// answers "gone" or a provider that cannot be reached asks for a confirmation.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../ProviderService.js" as ProviderService

ColumnLayout {
    id: panel
    spacing: Kirigami.Units.smallSpacing

    property var configuration: null   // plasmoid.configuration
    property var wallet: null          // store/Wallet.qml
    property var providers: []
    property string defaultProvider: configuration ? String(configuration.provider || "") : ""
    // The image service /image uses (image entries are edited by ImageProvidersPanel.qml).
    readonly property string defaultImage: configuration && providers ? ProviderService.defaultImageProvider(configuration) : ""

    // Editor state. editingIndex is -1 when nothing is being edited.
    property int editingIndex: -1
    property bool editingNew: false
    property var draft: ({})
    property string draftKey: ""
    // Set before adding a found server that asks for a key: no model list until the key is saved.
    property bool skipModelFetch: false
    // The models offered in the editor, and what the provider listed.
    property var listChat: []
    property var listAll: []
    property bool showAll: false
    readonly property var modelCandidates: candidates(listChat, listAll, showAll, draft.model, checker.deadRevision)
    // The draft model's variants, when the provider reports any (Variants.js).
    property var draftVariants: []
    property int _variantGeneration: 0
    property string status: ""
    property string statusKind: "info"
    // "" | "model" | "unverified": which "go on anyway" button is offered.
    property string overrideKind: ""
    property int confirmRemoveIndex: -1

    // For tests: replaces XMLHttpRequest.
    property alias xhrFactory: checker.xhrFactory

    ProviderChecker {
        id: checker
    }
    readonly property var providerChecker: checker

    function setStatus(text, kind) {
        status = text;
        statusKind = kind || "info";
    }

    // [{id, name}] for the model picker: the list (chat models, or all), the
    // current model first if it is not in it, dead models marked.
    function candidates(chat, all, showEverything, current, revision) {
        var ids = (showEverything ? all : chat).slice();
        if (current && ids.indexOf(current) < 0)
            ids.unshift(current);
        return ids.map(function(id) {
            return {"id": id, "name": checker.deadReason(draft.id, id) !== "" ? i18n("(unavailable)") : ""}; // qmllint disable unqualified
        });
    }

    function load() {
        var list = ProviderService.parseProviders(configuration);
        // Before the 1.4.0 migration has run, show what it will create.
        if (list.length === 0)
            list = ProviderService.legacyProviders(configuration || {}, wallet ? wallet.keys : {});
        providers = list;
    }

    function persist() {
        configuration.providersJson = ProviderService.serializeProviders(providers);
    }

    // Tells the running widget to read the keys again (main.qml reloads the
    // wallet when walletKeysRevision changes); otherwise it keeps the old key.
    function notifyKeysChanged() {
        if (configuration && configuration.walletKeysRevision !== undefined)
            configuration.walletKeysRevision = (Number(configuration.walletKeysRevision) || 0) + 1;
    }

    function isLocal(entry) {
        return ProviderService.getProviderConfig(entry.id, {"providersJson": JSON.stringify([entry])}).allowEmptyKey;
    }

    function addFromPreset(presetId, overrides) {
        var preset = ProviderService.presetById(presetId) || {};
        var entry = {"id": ProviderService.newProviderId(providers, presetId), "name": preset.name || i18n("New provider"), // qmllint disable unqualified
                     "type": preset.type || "openai-compat", "baseUrl": preset.baseUrl || "", "model": preset.model || ""};
        if (preset.headers) entry.headers = preset.headers;
        Object.assign(entry, overrides || {});   // e.g. a found local server's address and model
        if (preset.service) Object.assign(entry, {"service": preset.service, "accepted": false, "options": {}});   // an image service, off at first
        providers = providers.concat([entry]);
        startEdit(providers.length - 1, true);
    }

    function startEdit(index, isNew) {
        checker.cancel();
        draft = Object.assign({}, providers[index]);
        draftKey = wallet && wallet.keys ? (wallet.keys[draft.id] || "") : "";
        listChat = [];
        listAll = [];
        draftVariants = [];
        showAll = false;
        overrideKind = "";
        setStatus("");
        editingNew = !!isNew;
        editingIndex = index;
        confirmRemoveIndex = -1;
        // Show the provider's current models without being asked.
        var skip = skipModelFetch; skipModelFetch = false;
        if (draft.type !== "image" && !skip && (isLocal(draft) || draftKey.trim() !== ""))
            refreshModels(false);
    }

    function cancelEdit() {
        checker.cancel();
        if (editingNew)
            providers = providers.slice(0, editingIndex).concat(providers.slice(editingIndex + 1));
        editingIndex = -1;
        editingNew = false;
    }

    // The draft with its text fields cleaned up, as it would be saved.
    function draftEntry() {
        var entry = Object.assign({}, draft);
        entry.name = String(entry.name || "").trim() || entry.id;
        entry.baseUrl = String(entry.baseUrl || "").trim();
        entry.model = String(entry.model || "").trim();
        return entry;
    }

    function onFieldEdited(field, value) {
        overrideKind = "";
        if (field === "key") {
            draftKey = value;
            return;
        }
        var change = {};
        change[field] = value;
        // A variant belongs to its model: another model starts without one.
        if (field === "model")
            change.variant = "";
        draft = Object.assign({}, draft, change);
        if (field === "baseUrl") {
            listChat = [];
            listAll = [];
            draftVariants = [];
        }
        if (field === "model" || field === "baseUrl")
            loadVariants();
    }

    // Looks up the draft model's variants: from the list already fetched, so
    // normally without a request.
    function loadVariants() {
        var entry = draftEntry();
        var generation = ++_variantGeneration;
        draftVariants = [];
        if (entry.model === "" || !ProviderService.isHttpUrlAllowed(entry.baseUrl) || (draftKey.trim() === "" && !isLocal(entry)))
            return;
        checker.variantsFor(entry, draftKey.trim(), entry.model, function(variants) {
            if (generation === _variantGeneration && editingIndex >= 0 && draft.id === entry.id)
                draftVariants = variants;
        });
    }

    // Saves the draft. Unless `skipCheck`, a cloud provider whose key, URL or
    // model changed is checked with the provider first.
    function saveEdit(skipCheck) {
        var entry = draftEntry();
        var key = draftKey.trim();
        if (!ProviderService.isHttpUrlAllowed(entry.baseUrl)) {
            setStatus(i18n("Enter an http:// or https:// URL."), "error"); // qmllint disable unqualified
            return;
        }
        var before = providers[editingIndex] || {};
        var changed = editingNew || (wallet && key !== (wallet.keys[entry.id] || ""))
            || before.model !== entry.model || before.baseUrl !== entry.baseUrl;
        if (skipCheck === true || !changed || key === "" || isLocal(entry)) {
            commit(entry, key);
            return;
        }
        overrideKind = "";
        setStatus("");
        checker.verify(entry, key, false, function(result) {
            if (result.state === "ok" || result.state === "skipped") {
                commit(entry, key);
                return;
            }
            var shown = checker.describe(entry, result);
            setStatus(shown.text, shown.kind);
            overrideKind = result.state === "model_unavailable" ? "model" : result.state === "unverified" ? "unverified" : "";
        });
    }

    function commit(entry, key) {
        checker.cancel();
        var list = providers.slice();
        list[editingIndex] = entry;
        providers = list;
        persist();
        if (wallet && (key !== (wallet.keys[entry.id] || "")))
            wallet.write(entry.id, key, function(ok) {
                if (ok) panel.notifyKeysChanged();
                else setStatus(wallet.statusMessage(), "error");
            });
        // An image service never becomes the default for chats by itself.
        if (entry.type !== "image" && (!defaultProvider || ProviderService.getProviderConfig(defaultProvider, configuration).found === false))
            setDefault(entry.id);
        editingIndex = -1;
        editingNew = false;
    }

    function removeAt(index) {
        var id = providers[index].id;
        providers = providers.slice(0, index).concat(providers.slice(index + 1));
        persist();
        if (wallet) wallet.remove(id, function(ok) { if (ok) panel.notifyKeysChanged(); });
        if (defaultProvider === id)
            setDefault((providers.filter(function(p) { return p.type !== "image"; })[0] || {"id": ""}).id);
        confirmRemoveIndex = -1;
    }

    // The default for chats, or for an image service the one /image uses.
    function setDefault(id) {
        if (providers.some(function(p) { return p.id === id && p.type === "image"; })) configuration.imageProvider = id;
        else configuration.provider = id;
    }

    // Fetches the draft provider's models; `force` skips the session cache and
    // tries the saved model again.
    function refreshModels(force) {
        var entry = draftEntry();
        var key = draftKey.trim();
        if (!ProviderService.isHttpUrlAllowed(entry.baseUrl)) {
            setStatus(i18n("Enter an http:// or https:// URL."), "error"); // qmllint disable unqualified
            return;
        }
        var id = entry.id;
        checker.loadModels(entry, key, force, function(result) {
            if (editingIndex < 0 || draft.id !== id)
                return;
            if (!result.ok) {
                setStatus(result.error === "rejected" ? i18n("The provider rejected the API key (HTTP %1).", result.status) // qmllint disable unqualified
                          : result.error === "http" ? i18n("The provider answered HTTP %1 for its model list.", result.status) // qmllint disable unqualified
                          : i18n("Could not fetch models from %1.", checker.hostOf(entry.baseUrl)), "error"); // qmllint disable unqualified
                return;
            }
            listChat = result.chat;
            listAll = result.all;
            loadVariants();
            setStatus(result.all.length > 0 ? i18np("%1 model available.", "%1 models available.", result.chat.length) : i18n("The provider returned no models."), "info"); // qmllint disable unqualified
            checkSavedModel(entry, key, force, result);
        });
    }

    // Finds out (once per session, or when refreshed) whether the chosen model
    // still answers; a dead one is flagged here and next to the provider row.
    function checkSavedModel(entry, key, force, list) {
        if (entry.model === "")
            return;
        if (isLocal(entry)) {
            checker.markMissing(entry, list.all);
            return;
        }
        if (key === "" || (!force && checker.probed[entry.id + "|" + entry.model]))
            return;
        checker.verify(entry, key, false, function(result) {
            if (editingIndex >= 0 && draft.id === entry.id && (result.state === "key_rejected" || result.state === "model_unavailable")) {
                let shown = checker.describe(entry, result);
                setStatus(shown.text, shown.kind);
            }
        });
    }

    Component.onCompleted: load()

    Connections {
        target: panel.wallet
        function onLoaded() { if (panel.editingIndex < 0) panel.load(); }
    }

    // ── Header ────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Kirigami.Heading {
            level: 4
            text: i18n("Providers") // qmllint disable unqualified
            Layout.fillWidth: true
        }
        QQC2.Button {
            text: i18n("Add provider") // qmllint disable unqualified
            icon.name: "list-add"
            enabled: panel.editingIndex < 0
            onClicked: presetMenu.popup()
            QQC2.Menu {
                id: presetMenu
                Repeater {
                    model: ProviderService.PRESETS
                    QQC2.MenuItem {
                        required property var modelData
                        text: modelData.name
                        onTriggered: panel.addFromPreset(modelData.id)
                    }
                }
            }
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: panel.wallet !== null && panel.wallet.status !== "ready" && panel.wallet.status !== "unknown"
        type: Kirigami.MessageType.Warning
        text: panel.wallet ? panel.wallet.statusMessage() : ""
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: panel.providers.length === 0
        wrapMode: Text.Wrap
        opacity: 0.75
        text: i18n("No providers yet. Add one to chat with a model directly, using your own API key or a local server.") // qmllint disable unqualified
    }

    // ── List ──────────────────────────────────────────────────────────────
    // Shown with the default first; `index` is the position in `providers`.
    Repeater {
        id: providerList
        objectName: "providerList"
        model: ProviderService.defaultFirstOrder(panel.providers, panel.defaultProvider)
        delegate: ProviderRow {
            id: providerRow
            required property int modelData
            readonly property int index: modelData
            readonly property var item: panel.providers[modelData] || ({"id": "", "name": ""})  // briefly stale while rows are rebuilt
            entry: providerRow.item
            isDefault: providerRow.item.id === (providerRow.item.type === "image" ? panel.defaultImage : panel.defaultProvider)
            local: panel.isLocal(providerRow.item)
            missingKey: !local && panel.wallet !== null && !panel.wallet.keys[providerRow.item.id]
            host: checker.hostOf(providerRow.item.baseUrl)
            unavailable: checker.deadReason(providerRow.item.id, providerRow.item.model)
            busy: panel.editingIndex >= 0
            editing: panel.editingIndex === index
            confirmingRemove: panel.confirmRemoveIndex === index
            onUseByDefault: panel.setDefault(providerRow.item.id)
            onEdit: panel.startEdit(index, false)
            onAskRemove: panel.confirmRemoveIndex = index
            onConfirmRemove: panel.removeAt(index)
            onCancelRemove: panel.confirmRemoveIndex = -1
        }
    }

    // ── Editor (one, below the list) ──────────────────────────────────
    ImageProvidersPanel {
        objectName: "imageProvidersPanel"
        Layout.fillWidth: true
        panel: panel
    }
    ProviderEditor {
        Layout.fillWidth: true
        visible: panel.editingIndex >= 0 && panel.draft.type !== "image"
        draft: panel.draft
        draftKey: panel.draftKey
        local: panel.editingIndex >= 0 && panel.isLocal(panel.draft)
        models: panel.modelCandidates
        variants: panel.draftVariants
        hiddenCount: panel.listAll.length - panel.listChat.length
        showAll: panel.showAll
        listing: checker.listing
        checking: checker.checking
        message: panel.status
        messageKind: panel.statusKind
        overrideText: panel.overrideKind === "model" ? i18n("Use this model anyway") : panel.overrideKind === "unverified" ? i18n("Save anyway") : "" // qmllint disable unqualified
        modelWarning: checker.deadReason(panel.draft.id, panel.draft.model || "") !== ""
            ? i18n("Unavailable: %1", checker.deadReason(panel.draft.id, panel.draft.model)) : "" // qmllint disable unqualified
        onFieldEdited: function(field, value) { panel.onFieldEdited(field, value); }
        onRefreshClicked: panel.refreshModels(true)
        onShowAllToggled: function(on) { panel.showAll = on; }
        onSaveClicked: panel.saveEdit(false)
        onOverrideClicked: panel.saveEdit(true)
        onCancelClicked: panel.cancelEdit()
    }

    // Keeps rows at their natural height when the panel is given extra space.
    Item {
        Layout.fillHeight: true
    }
}
