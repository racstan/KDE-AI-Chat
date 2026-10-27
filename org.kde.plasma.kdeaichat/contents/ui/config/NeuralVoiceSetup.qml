// Settings → Voice, read aloud with the natural voice (Kokoro): whether it is
// installed, what installing downloads (shown before the button is
// pressed), Install, and Remove (asks first). The helper does the work
// (kdeaichat/tts_neural.py); nothing is installed or downloaded otherwise.
//
// runHelper(command, payload, callback(stdout, exitCode, stderr)) is
// store/HelperRunner.qml's run(); tests pass a fake.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: setup

    property var runHelper: null
    // Looked up when this becomes true (the natural voice is chosen and read aloud is on).
    property bool active: false

    property var info: null          // tts_neural_status reply
    property bool busy: false
    property string message: ""
    readonly property bool installed: !!info && info.installed === true
    readonly property var size: info ? (gpuCheck.checked ? info.size_gpu : info.size) : null

    objectName: "neuralVoiceSetup"
    Kirigami.FormData.label: i18n("Natural voice:")
    Kirigami.FormData.labelAlignment: Qt.AlignTop
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    onActiveChanged: if (active && !info) refresh()
    Component.onCompleted: if (active) refresh()

    function _reply(stdout) {
        try {
            return JSON.parse(String(stdout || "").trim().split("\n").pop());
        } catch (e) {
            return null;
        }
    }

    function refresh() {
        if (!runHelper)
            return;
        runHelper("tts_neural_status", {}, function(stdout) {
            var r = setup._reply(stdout);
            if (r && r.type === "tts_neural_status")
                setup.info = r;
        });
    }

    function megabytes(mb) {
        return mb >= 1000 ? i18n("%1 GB", (mb / 1000).toFixed(1)) : i18n("%1 MB", Math.max(1, Math.round(mb)));
    }

    function install() {
        if (!runHelper || busy)
            return;
        busy = true;
        message = i18n("Installing… this can take a few minutes.");
        runHelper("tts_neural_install", {"gpu": gpuCheck.checked}, function(stdout, exitCode, stderr) {
            var r = setup._reply(stdout);
            setup.busy = false;
            setup.message = r && r.ok ? i18n("Installed. Replies are now read with the natural voice.")
                : i18n("Install failed: %1", r && r.error ? r.error : (String(stderr).trim().split("\n").pop() || i18n("no answer")));
            setup.refresh();
        });
    }

    function remove() {
        if (!runHelper || busy)
            return;
        busy = true;
        runHelper("tts_neural_remove", {}, function(stdout) {
            setup.busy = false;
            setup.message = i18n("Removed. The system voice reads until you install the natural voice again.");
            setup.refresh();
        });
    }

    QQC2.Label {
        objectName: "neuralVoiceState"
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 28
        wrapMode: Text.Wrap
        text: !setup.info ? i18n("Checking…")
            : setup.installed ? (setup.info.gpu_installed ? i18n("Installed, with graphics card support.") : i18n("Installed."))
            : i18n("Not installed yet: replies are read with the system voice until you install it.")
    }

    QQC2.Label {
        objectName: "neuralVoiceSize"
        visible: !!setup.size && setup.size.total_mb > 0
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 28
        wrapMode: Text.Wrap
        text: {
            var s = setup.size;
            if (!s)
                return "";
            var parts = [];
            if (s.program_mb) parts.push(i18n("the program %1", setup.megabytes(s.program_mb)));
            if (s.gpu_mb) parts.push(i18n("graphics card support %1", setup.megabytes(s.gpu_mb)));
            if (s.model_mb) parts.push(i18n("the voice model %1", setup.megabytes(s.model_mb)));
            return i18n("Install downloads about %1 (%2), into %3.", setup.megabytes(s.total_mb), parts.join(", "),
                        setup.info ? setup.info.venv.replace(/\/[^\/]*$/, "") : "");
        }
    }

    QQC2.CheckBox {
        id: gpuCheck
        objectName: "neuralVoiceGpu"
        visible: !!setup.info && setup.info.gpu === true && !(setup.installed && setup.info.gpu_installed)
        text: i18n("Also use the NVIDIA graphics card (much bigger download)")
    }
    SettingHelp {
        visible: gpuCheck.visible
        text: i18n("Not needed: the processor reads fast enough. The graphics card only makes the first words come a little sooner.")
    }

    RowLayout {
        QQC2.Button {
            objectName: "neuralVoiceInstall"
            visible: !!setup.info && !!setup.size && setup.size.total_mb > 0
            enabled: !setup.busy
            icon.name: "download"
            text: setup.size ? i18n("Install (%1)", setup.megabytes(setup.size.total_mb)) : i18n("Install")
            onClicked: setup.install()
        }
        QQC2.Button {
            objectName: "neuralVoiceRemove"
            visible: !!setup.info && (setup.info.packages || setup.info.model !== "")
            enabled: !setup.busy
            icon.name: "edit-delete"
            text: i18n("Remove…")
            onClicked: confirm.open()
        }
        QQC2.BusyIndicator {
            visible: setup.busy
            running: visible
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        }
    }

    QQC2.Label {
        objectName: "neuralVoiceMessage"
        visible: text !== ""
        text: setup.message
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 28
    }

    Kirigami.PromptDialog {
        id: confirm
        title: i18n("Remove the natural voice?")
        subtitle: i18n("This deletes its program and voice model from %1 and %2. The system voice reads instead until you install it again.",
                       setup.info ? setup.info.venv : "", setup.info ? setup.info.models : "")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: setup.remove()
    }
}
