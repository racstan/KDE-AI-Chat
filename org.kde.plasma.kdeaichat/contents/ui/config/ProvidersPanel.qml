// Settings: the user's direct-mode providers.
//
// A list (stored as `providersJson`, see ProviderService.js) with add from a
// preset, edit, remove and "use by default". API keys are written to KWallet
// under the provider id and never to the config. Changes save immediately.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../ProviderService.js" as ProviderService
import "../components" as Components

ColumnLayout {
    id: panel
    spacing: Kirigami.Units.smallSpacing

    property var configuration: null   // plasmoid.configuration
    property var wallet: null          // store/Wallet.qml
    property var providers: []
    property string defaultProvider: configuration ? String(configuration.provider || "") : ""

    // Editor state. editingIndex is -1 when nothing is being edited.
    property int editingIndex: -1
    property bool editingNew: false
    property var draft: ({})
    property string draftKey: ""
    property var modelCandidates: []
    property bool fetching: false
    property string status: ""
    property int confirmRemoveIndex: -1

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

    function hostOf(url) {
        var m = /^[a-z]+:\/\/([^/]+)/i.exec(String(url || ""));
        return m ? m[1] : "";
    }

    function addFromPreset(presetId) {
        var preset = ProviderService.presetById(presetId) || {};
        var entry = {"id": ProviderService.newProviderId(providers, presetId), "name": preset.name || i18n("New provider"), // qmllint disable unqualified
                     "type": preset.type || "openai-compat", "baseUrl": preset.baseUrl || "", "model": preset.model || ""};
        if (preset.headers) entry.headers = preset.headers;
        providers = providers.concat([entry]);
        startEdit(providers.length - 1, true);
    }

    function startEdit(index, isNew) {
        draft = Object.assign({}, providers[index]);
        draftKey = wallet && wallet.keys ? (wallet.keys[draft.id] || "") : "";
        modelCandidates = draft.model ? [draft.model] : [];
        status = "";
        editingNew = !!isNew;
        editingIndex = index;
        confirmRemoveIndex = -1;
    }

    function cancelEdit() {
        if (editingNew)
            providers = providers.slice(0, editingIndex).concat(providers.slice(editingIndex + 1));
        editingIndex = -1;
        editingNew = false;
    }

    function saveEdit() {
        var entry = Object.assign({}, draft);
        entry.name = String(entry.name || "").trim() || entry.id;
        entry.baseUrl = String(entry.baseUrl || "").trim();
        if (!ProviderService.isHttpUrlAllowed(entry.baseUrl)) {
            status = i18n("Enter an http:// or https:// URL."); // qmllint disable unqualified
            return;
        }
        var list = providers.slice();
        list[editingIndex] = entry;
        providers = list;
        persist();
        if (wallet && (draftKey.trim() !== (wallet.keys[entry.id] || "")))
            wallet.write(entry.id, draftKey.trim(), function(ok) {
                if (ok) panel.notifyKeysChanged();
                else status = wallet.statusMessage();
            });
        if (!defaultProvider || ProviderService.getProviderConfig(defaultProvider, configuration).found === false)
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
            setDefault(providers.length > 0 ? providers[0].id : "");
        confirmRemoveIndex = -1;
    }

    function setDefault(id) {
        configuration.provider = id;
    }

    function fetchModels() {
        fetching = true;
        status = i18n("Fetching models…"); // qmllint disable unqualified
        ProviderService.fetchModels(draft, draftKey.trim(), function(ids) {
            fetching = false;
            modelCandidates = ids;
            status = ids.length > 0 ? i18n("%1 models available.", ids.length) : i18n("The provider returned no models."); // qmllint disable unqualified
        }, function(error) {
            fetching = false;
            status = error;
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
    Repeater {
        model: panel.providers
        delegate: ColumnLayout {
            id: row
            Layout.fillWidth: true
            spacing: 0
            required property var modelData
            required property int index

            RowLayout {
                Layout.fillWidth: true
                visible: panel.editingIndex !== row.index
                Kirigami.Icon {
                    source: panel.isLocal(row.modelData) ? "computer" : "network-server"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QQC2.Label {
                        text: row.modelData.name + (row.modelData.id === panel.defaultProvider ? "  · " + i18n("default") : "") // qmllint disable unqualified
                        font.bold: row.modelData.id === panel.defaultProvider
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        text: (row.modelData.model || i18n("no model set")) + " · " + panel.hostOf(row.modelData.baseUrl) // qmllint disable unqualified
                            + (!panel.isLocal(row.modelData) && panel.wallet && !panel.wallet.keys[row.modelData.id] ? " · " + i18n("no API key") : "") // qmllint disable unqualified
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                QQC2.Button {
                    visible: row.modelData.id !== panel.defaultProvider && panel.confirmRemoveIndex !== row.index
                    text: i18n("Use by default") // qmllint disable unqualified
                    onClicked: panel.setDefault(row.modelData.id)
                }
                QQC2.ToolButton {
                    visible: panel.confirmRemoveIndex !== row.index
                    icon.name: "document-edit"
                    enabled: panel.editingIndex < 0
                    onClicked: panel.startEdit(row.index, false)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Edit") // qmllint disable unqualified
                    Accessible.name: i18n("Edit %1", row.modelData.name) // qmllint disable unqualified
                }
                QQC2.ToolButton {
                    visible: panel.confirmRemoveIndex !== row.index
                    icon.name: "edit-delete"
                    enabled: panel.editingIndex < 0
                    onClicked: panel.confirmRemoveIndex = row.index
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Remove") // qmllint disable unqualified
                    Accessible.name: i18n("Remove %1", row.modelData.name) // qmllint disable unqualified
                }
                QQC2.Label {
                    visible: panel.confirmRemoveIndex === row.index
                    text: i18n("Remove this provider and its key?") // qmllint disable unqualified
                }
                QQC2.Button {
                    visible: panel.confirmRemoveIndex === row.index
                    text: i18n("Remove") // qmllint disable unqualified
                    icon.name: "edit-delete"
                    onClicked: panel.removeAt(row.index)
                }
                QQC2.Button {
                    visible: panel.confirmRemoveIndex === row.index
                    text: i18n("Cancel") // qmllint disable unqualified
                    onClicked: panel.confirmRemoveIndex = -1
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                opacity: 0.4
            }
        }
    }

    // ── Editor (one, below the list) ──────────────────────────────────
    Kirigami.FormLayout {
        Layout.fillWidth: true
        visible: panel.editingIndex >= 0

        QQC2.TextField {
            Kirigami.FormData.label: i18n("Name:") // qmllint disable unqualified
            text: panel.draft.name || ""
            onTextEdited: panel.draft.name = text
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("API type:") // qmllint disable unqualified
            model: [i18n("OpenAI-compatible"), i18n("Anthropic")] // qmllint disable unqualified
            currentIndex: panel.draft.type === "anthropic" ? 1 : 0
            onActivated: panel.draft.type = currentIndex === 1 ? "anthropic" : "openai-compat"
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Server URL:") // qmllint disable unqualified
            Layout.fillWidth: true
            text: panel.draft.baseUrl || ""
            placeholderText: "https://api.example.com/v1"
            onTextEdited: panel.draft.baseUrl = text
        }
        Kirigami.PasswordField {
            Kirigami.FormData.label: i18n("API key:") // qmllint disable unqualified
            Layout.fillWidth: true
            text: panel.draftKey
            placeholderText: panel.editingIndex >= 0 && panel.isLocal(panel.draft) ? i18n("Optional for local servers") : i18n("Stored in KWallet") // qmllint disable unqualified
            onTextEdited: panel.draftKey = text
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Model:") // qmllint disable unqualified
            Layout.fillWidth: true
            Components.ModelPicker {
                Layout.fillWidth: true
                model: panel.modelCandidates
                value: panel.draft.model || ""
                onPicked: function(id) { panel.draft = Object.assign({}, panel.draft, {"model": id}); }
            }
            QQC2.Button {
                text: i18n("Fetch models") // qmllint disable unqualified
                icon.name: "view-refresh"
                enabled: !panel.fetching
                onClicked: panel.fetchModels()
            }
        }
        QQC2.Label {
            visible: panel.status !== ""
            text: panel.status
            wrapMode: Text.Wrap
            opacity: 0.8
            Layout.fillWidth: true
        }
        RowLayout {
            QQC2.Button {
                text: i18n("Save") // qmllint disable unqualified
                icon.name: "document-save"
                onClicked: panel.saveEdit()
            }
            QQC2.Button {
                text: i18n("Cancel") // qmllint disable unqualified
                onClicked: panel.cancelEdit()
            }
        }
    }

    // Keeps rows at their natural height when the panel is given extra space.
    Item {
        Layout.fillHeight: true
    }
}
