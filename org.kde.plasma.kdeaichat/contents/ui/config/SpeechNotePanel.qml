// Settings → Voice, Speech Note part (dictation: role "stt", read aloud: "tts"):
// whether Speech Note is installed (with links to get it and a one-line setup),
// the model picker filled from Speech Note itself, and the credit line.
// The model is the page's cfg_ property (sttSpeechNoteModel /
// voiceTtsSpeechNoteModel; empty = Speech Note's own default), saved with
// OK/Apply. `status` is a config/SpeechNoteStatus.qml shared by both parts.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../voice/SpeechNote.js" as SpeechNote

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: panel

    property string role: "stt"          // "stt" | "tts"
    property var form: null              // the settings page (optionValue / setOption)
    property var status: null            // SpeechNoteStatus.qml
    property var twin: null
    // The part is on screen: the model lists are fetched once.
    property bool active: false
    // The "keep ready" row (one setting, shown in one of the two parts).
    property bool showKeepReady: true

    readonly property bool isStt: role === "stt"
    readonly property string key: isStt ? "sttSpeechNoteModel" : "voiceTtsSpeechNoteModel"
    readonly property var models: status ? (isStt ? status.sttModels : status.ttsModels) : []
    readonly property bool ready: !!status && status.loaded && status.installed && status.errorCode === ""

    function check() {
        if (active && status && !status.loaded && !status.loading)
            status.refresh();
    }
    onActiveChanged: check()
    Component.onCompleted: check()

    Layout.fillWidth: true

    Kirigami.FormLayout {
        twinFormLayouts: panel.twin ? [panel.twin] : []
        Layout.fillWidth: true

        QQC2.Label {
            objectName: "speechNoteStatus"
            Kirigami.FormData.label: i18n("Speech Note:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.Wrap
            text: {
                var s = panel.status;
                if (!s || !s.loaded)
                    return i18n("Looking for Speech Note…");
                if (!s.installed)
                    return i18n("Not installed.");
                var where = s.kind === "flatpak" ? i18n("Installed (Flatpak).") : i18n("Installed.");
                if (s.errorCode !== "")
                    return i18n("%1 %2", where, i18n(SpeechNote.errorText(s.errorCode)) + ".");
                return where;
            }
        }

        // Not a setting: no label, so the page's explanation check leaves it alone.
        RowLayout {
            QQC2.Button {
                objectName: "speechNoteRecheck"
                text: i18n("Check again")
                icon.name: "view-refresh"
                enabled: !!panel.status && !panel.status.loading
                onClicked: { panel.status.loaded = false; panel.status.refresh(); }
            }
            QQC2.BusyIndicator {
                visible: !!panel.status && panel.status.loading
                running: visible
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
        }

        // The install steps, only while Speech Note is missing. Once it is installed,
        // the line about the missing models (below) says what is still needed.
        QQC2.Label {
            objectName: "speechNoteSetup"
            visible: !!panel.status && panel.status.loaded && !panel.status.installed
            Kirigami.FormData.label: i18n("Set up:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: panel.isStt
                ? i18n("Install Speech Note, then download a speech-to-text model in your language inside Speech Note.")
                : i18n("Install Speech Note, then download a voice in your language inside Speech Note. Until then the system voice reads.")
        }

        QQC2.Label {
            objectName: "speechNoteLinks"
            visible: !!panel.status && panel.status.loaded && !panel.status.installed
            Kirigami.FormData.label: i18n("Get it:")
            textFormat: Text.StyledText
            text: "<a href=\"" + SpeechNote.FLATHUB_URL + "\">Flathub</a> · <a href=\"" + SpeechNote.GITHUB_URL + "\">GitHub</a>"
            onLinkActivated: function(link) { Qt.openUrlExternally(link); }
        }

        QQC2.ComboBox {
            Accessible.name: Kirigami.FormData.label
            id: modelCombo
            objectName: panel.isStt ? "speechNoteSttModel" : "speechNoteTtsModel"
            visible: panel.ready
            Kirigami.FormData.label: panel.isStt ? i18n("Speech model:") : i18n("Voice:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            textRole: "text"
            valueRole: "value"
            model: SpeechNote.withSaved(SpeechNote.modelChoices(panel.models, i18n("Speech Note's default")),
                                        panel.form ? panel.form.optionValue(panel.key) : "")
            currentIndex: {
                var saved = String(panel.form ? panel.form.optionValue(panel.key) || "" : "");
                for (var i = 0; i < model.length; i++)
                    if (model[i].value === saved)
                        return i;
                return 0;
            }
            onActivated: if (panel.form) panel.form.setOption(panel.key, currentValue)
        }

        QQC2.Label {
            objectName: "speechNoteNoModels"
            visible: modelCombo.visible && panel.models.length === 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: panel.isStt ? i18n("Speech Note has no speech-to-text model yet: download one in your language inside Speech Note.")
                              : i18n("Speech Note has no voice yet: download one in your language inside Speech Note. Until then the system voice reads.")
        }

        SettingHelp {
            visible: modelCombo.visible
            text: panel.isStt
                ? i18n("Which of the speech models you downloaded in Speech Note understands you. \"Speech Note's default\" uses the one chosen in Speech Note; each model's name shows its language.")
                : i18n("Which of the voices you downloaded in Speech Note reads to you. \"Speech Note's default\" uses the one chosen in Speech Note; each voice's name shows its language.")
        }

        QQC2.SpinBox {
            Accessible.name: Kirigami.FormData.label
            id: keepReady
            objectName: "speechNoteKeepReady"
            visible: panel.showKeepReady
            Kirigami.FormData.label: i18n("Keep ready:")
            from: 0
            to: 120
            editable: true
            value: panel.form ? Number(panel.form.optionValue("speechNoteKeepReadyMinutes")) : 5
            textFromValue: function(v) { return v === 0 ? i18n("Only when used") : i18n("%1 min", v); }
            valueFromText: function(text) { return parseInt(text) || 0; }
            onValueModified: if (panel.form) panel.form.setOption("speechNoteKeepReadyMinutes", value)
        }

        SettingHelp {
            visible: keepReady.visible
            text: i18n("How long Speech Note stays ready after you close the chat, so the next press starts at once. While it is ready its speech model stays in memory (and in the graphics card's memory); \"Only when used\" frees it after about a minute.")
        }

        QQC2.Label {
            objectName: "speechNoteCredit"
            Kirigami.FormData.label: i18n("Credit:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            textFormat: Text.StyledText
            text: i18n("Speech, models and GPU support by <a href=\"%1\">Speech Note</a>, © Michał Kosciesza, MPL-2.0", SpeechNote.GITHUB_URL)
            onLinkActivated: function(link) { Qt.openUrlExternally(link); }
        }
    }
}
