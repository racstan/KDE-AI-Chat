// The image-service part of ProvidersPanel.qml: editing an AI Horde or Pollinations entry
// of the provider list. The panel keeps the list, the draft and the key (KWallet); this
// part shows ImageProviderEditor.qml for an image entry, lists the service's models
// (ImageModels.qml) and saves through the panel. An image service is never checked
// with a test request: it stays off until the user switches it on.
import QtQuick
import QtQuick.Layouts

// plasmoid is provided by Plasma at runtime (in the settings dialog too).
// qmllint disable unqualified

ColumnLayout {
    id: part

    property var panel: null   // ProvidersPanel.qml
    // For AI Horde's Client-Agent: the widget's version and website (metadata.json).
    property string version: typeof plasmoid !== "undefined" && plasmoid && plasmoid.metaData ? String(plasmoid.metaData.version) : "dev"
    property string website: typeof plasmoid !== "undefined" && plasmoid && plasmoid.metaData ? String(plasmoid.metaData.website || "") : ""
    readonly property bool active: !!panel && panel.editingIndex >= 0 && panel.draft.type === "image"
    readonly property alias models: imageModels
    readonly property alias editor: form

    visible: active
    onActiveChanged: {
        if (active)
            imageModels.load(panel.draft.service, false);
        else
            imageModels.cancel();
    }

    // An edit of the form: the key, a field of the entry, or "option.<name>" (null removes it).
    function edit(field, value) {
        panel.overrideKind = "";
        if (field === "key") {
            panel.draftKey = value;
            return;
        }
        var change = {};
        if (field.indexOf("option.") === 0) {
            let options = Object.assign({}, panel.draft.options || {});
            if (value === null || value === undefined)
                delete options[field.substring(7)];
            else
                options[field.substring(7)] = value;
            change.options = options;
        } else {
            change[field] = value;
        }
        panel.draft = Object.assign({}, panel.draft, change);
    }

    function save() {
        var entry = panel.draftEntry();
        // No model chosen: the one that suits the service best right now.
        if (entry.model === "")
            entry.model = imageModels.defaultModel(entry.service);
        panel.commit(entry, entry.service === "pollinations-legacy" ? "" : panel.draftKey.trim());
    }

    ImageModels {
        id: imageModels
        version: part.version
        website: part.website
        xhrFactory: part.panel ? part.panel.xhrFactory : null
    }

    ImageProviderEditor {
        id: form
        objectName: "imageProviderEditor"
        Layout.fillWidth: true
        draft: part.panel ? part.panel.draft : ({})
        draftKey: part.panel ? part.panel.draftKey : ""
        models: imageModels.list
        listing: imageModels.listing
        listError: imageModels.error
        message: part.panel ? part.panel.status : ""
        messageKind: part.panel ? part.panel.statusKind : "info"
        onFieldEdited: function(field, value) { part.edit(field, value); }
        onRefreshClicked: imageModels.load(part.panel.draft.service, true)
        onSaveClicked: part.save()
        onCancelClicked: part.panel.cancelEdit()
    }
}
