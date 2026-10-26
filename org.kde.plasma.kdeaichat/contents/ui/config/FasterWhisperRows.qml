// Settings → Voice, dictation with faster-whisper: model (sizes, the
// recommended one, models already on this computer from Speech Note, Handy
// or the HuggingFace cache, or your own folder), device, how long the model
// stays loaded, and the setup buttons. Every button that downloads or
// deletes shows the size first; Download and Remove ask before they start.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../voice/SttEngines.js" as SttEngines

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: rows

    property var form: null      // config/DictationSettings.qml
    property var setup: null     // config/SttSetup.qml
    property bool shown: true
    property alias confirmDialog: confirm

    visible: shown
    Layout.fillWidth: true

    readonly property string model: form ? String(form.optionValue("sttModel") || "small") : "small"
    readonly property bool ownFolder: SttEngines.isFolder(model)
    readonly property var catalogueRow: {
        var list = setup ? setup.catalogue : [];
        for (var i = 0; i < list.length; i++)
            if (list[i].name === model)
                return list[i];
        return null;
    }
    readonly property bool installed: !!setup && setup.fasterWhisperInstalled
    readonly property bool needsDownload: !ownFolder && !!catalogueRow && !catalogueRow.downloaded
    readonly property var dataInfo: setup ? setup.data : null
    readonly property var size: setup ? setup.size : null

    // {"kind": "download"|"remove"|"rebuild", "title", "text"} while the dialog is open.
    property var pending: null
    function ask(kind) {
        if (kind === "download")
            pending = {"kind": kind, "title": i18n("Download the speech model?"),
                       "text": i18n("“%1” is %2. It is saved in %3 and used only on this computer.", model,
                                    SttEngines.size(catalogueRow ? catalogueRow.mb : 0), size && size.items.length
                                    ? (size.items.filter(function(i) { return i.kind === "model"; })[0] || {}).to || "~/.cache/huggingface/hub"
                                    : "~/.cache/huggingface/hub")};
        else if (kind === "remove")
            pending = {"kind": kind, "title": i18n("Remove faster-whisper's data?"),
                       "text": i18n("This deletes the engine (%1) and the models downloaded here (%2), %3 in all. Models from Speech Note, Handy or other apps are not touched. Dictation with faster-whisper needs Install again afterwards.",
                                    SttEngines.size(dataInfo ? dataInfo.venv_mb : 0), SttEngines.size(dataInfo ? dataInfo.models_mb : 0),
                                    SttEngines.size(dataInfo ? dataInfo.total_mb : 0))};
        else
            pending = {"kind": kind, "title": i18n("Rebuild the engine smaller?"),
                       "text": i18n("The engine was installed by an older version with packages dictation no longer needs. Rebuilding deletes it, frees about %1 and installs it again (about %2 to download). Your models are kept.",
                                    SttEngines.size(dataInfo ? dataInfo.rebuild_frees_mb : 0), SttEngines.size(size ? size.packages_mb : 0))};
        confirm.open();
    }
    function confirmed() {
        var kind = pending ? pending.kind : "";
        pending = null;
        if (kind === "download") setup.download();
        else if (kind === "remove") setup.removeData(false);
        else if (kind === "rebuild") setup.rebuild();
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Model:")
        QQC2.ComboBox {
            id: modelCombo
            objectName: "sttModelCombo"
            textRole: "text"
            valueRole: "value"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 18
            model: {
                var out = (rows.setup ? rows.setup.catalogue : []).map(function(m) {
                    var text = m.name + " · " + SttEngines.size(m.mb);
                    if (m.downloaded) text += " · " + i18n("downloaded");
                    if (m.recommended) text += " · " + i18n("recommended");
                    return {"value": m.name, "text": text};
                });
                (rows.setup ? rows.setup.found : []).forEach(function(m) {
                    if (m.engine === "faster-whisper" && m.source !== "HuggingFace")
                        out.push({"value": m.model, "text": i18n("%1 · from %2 · on disk", m.name, m.source)});
                });
                if (out.length > 0 && !out.some(function(o) { return o.value === rows.model; }))
                    out.push({"value": rows.model, "text": rows.ownFolder ? i18n("Folder: %1", rows.model) : rows.model});
                return out;
            }
            currentIndex: model.map(function(o) { return o.value; }).indexOf(rows.model)
            onActivated: rows.form.setOption("sttModel", currentValue)
        }
        QQC2.Button {
            icon.name: "document-open-folder"
            Accessible.name: i18n("Use a model folder (CTranslate2)")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: Accessible.name
            onClicked: folderDialog.open()
        }
        FolderDialog {
            id: folderDialog
            onAccepted: rows.form.setOption("sttModel", decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, "")))
        }
    }

    SettingHelp {
        objectName: "sttModelNote"
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        details: i18n("Bigger models understand speech better, especially accents and noisy rooms, but are bigger to download and slower. \"small\" suits most people.")
        text: i18n("The speech model that turns your voice into text.") + " " + (rows.ownFolder ? i18n("A model folder on this computer: nothing to download.")
            : rows.catalogueRow ? (rows.catalogueRow.note ? i18n(rows.catalogueRow.note) + ". " : "")
                                  + (rows.catalogueRow.downloaded ? i18n("Downloaded.") : i18n("Not downloaded yet (%1).", SttEngines.size(rows.catalogueRow.mb)))
            : "")
    }

    QQC2.ComboBox {
        objectName: "sttDeviceCombo"
        Kirigami.FormData.label: i18n("Run on:")
        textRole: "text"
        valueRole: "value"
        model: SttEngines.devices.map(function(d) { return {"value": d.value, "text": i18n(d.text)}; })
        currentIndex: Math.max(0, model.map(function(o) { return o.value; }).indexOf(String(rows.form ? rows.form.optionValue("sttDevice") || "auto" : "auto")))
        onActivated: rows.form.setOption("sttDevice", currentValue)
    }
    SettingHelp {
        text: i18n("Which part of the computer does the work. \"Automatic\" is right for almost everyone; an NVIDIA graphics card is much faster than the processor.")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Keep loaded:")
        QQC2.SpinBox {
            objectName: "sttIdleSpin"
            from: 1
            to: 120
            value: Number(rows.form ? rows.form.optionValue("sttIdleMinutes") || 5 : 5)
            onValueModified: rows.form.setOption("sttIdleMinutes", value)
        }
        QQC2.Label { text: i18n("minutes after the last use") }
    }
    SettingHelp {
        text: i18n("The speech model stays in memory this long after you dictate, so the next time starts quickly. A shorter time frees memory sooner.")
    }

    // Not installed: what Install downloads, before anything happens.
    RowLayout {
        Kirigami.FormData.label: i18n("Setup:")
        visible: !rows.installed && !!rows.setup && rows.setup.enginesLoaded
        QQC2.Label {
            objectName: "sttSetupSize"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            wrapMode: Text.Wrap
            text: !rows.size ? i18n("Working out the download size…")
                : i18n("Install downloads about %1 of Python packages%2 into its own folder. The model (%3) is downloaded afterwards, when you choose.",
                       SttEngines.size(rows.size.packages_mb), rows.size.gpu ? i18n(" (with NVIDIA GPU support)") : "",
                       rows.ownFolder ? i18n("your folder") : SttEngines.size(rows.size.model_mb))
        }
        QQC2.Button {
            objectName: "sttInstallButton"
            text: i18n("Install")
            icon.name: "run-install"
            enabled: !!rows.size && !rows.setup.busy
            onClicked: rows.setup.install()
        }
    }
    SettingHelp {
        visible: !rows.installed && !!rows.setup && rows.setup.enginesLoaded
        text: i18n("A one-time setup of the speech program in its own folder. Nothing is installed until you press Install.")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Model download:")
        visible: rows.installed && rows.needsDownload
        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            wrapMode: Text.Wrap
            text: i18n("“%1” needs a download of %2.", rows.model, SttEngines.size(rows.catalogueRow ? rows.catalogueRow.mb : 0))
        }
        QQC2.Button {
            objectName: "sttDownloadButton"
            text: i18n("Download…")
            icon.name: "download"
            enabled: !rows.setup.busy
            onClicked: rows.ask("download")
        }
    }
    SettingHelp {
        visible: rows.installed && rows.needsDownload
        text: i18n("The chosen model has to be downloaded once before you can dictate. You are asked before it starts.")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Status:")
        visible: !!rows.setup && (rows.setup.status !== "" || rows.setup.busy)
        QQC2.BusyIndicator {
            visible: !!rows.setup && rows.setup.busy
            running: visible
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        }
        QQC2.Label {
            objectName: "sttStatus"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.Wrap
            text: rows.setup ? rows.setup.status : ""
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Smaller engine:")
        visible: !!rows.dataInfo && rows.dataInfo.has_torch === true
        QQC2.Label {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            wrapMode: Text.Wrap
            text: i18n("Installed by an older version with packages dictation no longer needs (about %1).",
                       SttEngines.size(rows.dataInfo ? rows.dataInfo.rebuild_frees_mb : 0))
        }
        QQC2.Button {
            objectName: "sttRebuildButton"
            text: i18n("Rebuild (smaller)…")
            icon.name: "edit-clear-all"
            enabled: !rows.setup.busy
            onClicked: rows.ask("rebuild")
        }
    }
    SettingHelp {
        visible: !!rows.dataInfo && rows.dataInfo.has_torch === true
        text: i18n("Sets the speech program up again without the parts it no longer needs, to free disk space. Dictation keeps working the same.")
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Engine data:")
        visible: !!rows.dataInfo && (rows.dataInfo.venv_exists || (rows.dataInfo.models || []).length > 0)
        QQC2.Label {
            objectName: "sttDataSize"
            text: i18n("%1 (engine %2, models downloaded here %3)", SttEngines.size(rows.dataInfo ? rows.dataInfo.total_mb : 0),
                       SttEngines.size(rows.dataInfo ? rows.dataInfo.venv_mb : 0), SttEngines.size(rows.dataInfo ? rows.dataInfo.models_mb : 0))
        }
        QQC2.Button {
            objectName: "sttRemoveButton"
            text: i18n("Remove…")
            icon.name: "edit-delete"
            enabled: !rows.setup.busy
            onClicked: rows.ask("remove")
        }
    }
    SettingHelp {
        visible: !!rows.dataInfo && (rows.dataInfo.venv_exists || (rows.dataInfo.models || []).length > 0)
        text: i18n("Disk space the speech program and its models use. Remove deletes them if you no longer dictate; you can install them again later.")
    }

    Kirigami.PromptDialog {
        id: confirm
        objectName: "sttConfirmDialog"
        title: rows.pending ? rows.pending.title : ""
        subtitle: rows.pending ? rows.pending.text : ""
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: rows.confirmed()
        onRejected: rows.pending = null
    }
}
