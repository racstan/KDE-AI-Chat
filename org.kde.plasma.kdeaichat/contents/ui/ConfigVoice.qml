// Settings → Voice: two switches, both off by default. "Read aloud" adds a
// read-aloud button to replies and picks the engine (voice/TtsEngines.js:
// System voices need no setup); "Dictation" adds the microphone button and
// runs a local speech-to-text engine.
//
// The read-aloud form is built from the engine's options (config/TtsOption.qml),
// the dictation form is config/DictationSettings.qml; every option is a cfg_
// property below, saved with OK/Apply (keys go to KWallet, never here).
// Nothing is installed or downloaded until a button that shows the size is
// pressed; on save, stt_sync_units adds or removes the dictation service.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config
import "store" as Store
import "voice" as Voice
import "voice/TtsEngines.js" as Engines
import "voice/SttConfig.js" as SttConfig

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    // Read aloud
    property alias cfg_voiceTtsEnabled: readCheck.checked
    property alias cfg_voiceTtsAuto: ttsAutoCheck.checked
    property string cfg_voiceTtsEngine: Engines.defaultEngine
    property string cfg_voiceTtsSystemLanguage: ""
    property string cfg_voiceTtsSystemVoice: ""
    property real cfg_voiceTtsSystemRate: 0
    property real cfg_voiceTtsSystemPitch: 0
    property string cfg_voiceTtsKokoroLanguage: ""
    property string cfg_voiceTtsKokoroVoice: ""
    property real cfg_voiceTtsKokoroRate: 0
    property string cfg_voiceTtsFliteVoice: ""
    property real cfg_voiceTtsFliteRate: 0
    property real cfg_voiceTtsFlitePitch: 0
    property string cfg_voiceTtsPiperModel: ""
    property int cfg_voiceTtsPiperSpeaker: 0
    property real cfg_voiceTtsPiperSpeed: 1
    property string cfg_voiceTtsRemoteUrl: "http://localhost:8880/v1"
    property string cfg_voiceTtsRemoteModel: "tts-1"
    property string cfg_voiceTtsRemoteVoice: "alloy"
    property real cfg_voiceTtsRemoteSpeed: 1
    property string cfg_voiceTtsCommand: ""

    // Dictation (speech-to-text): voice/SttConfig.js lists these keys.
    property alias cfg_sttEnabled: enabledCheck.checked
    property bool cfg_voiceAutoSend: true
    property string cfg_sttEngine: "faster-whisper"
    property string cfg_sttModel: "small"
    property string cfg_sttDevice: "auto"
    property string cfg_sttLanguage: "auto"
    property int cfg_sttIdleMinutes: 5
    property string cfg_sttWhisperCppBinary: ""
    property string cfg_sttWhisperCppModel: ""
    property string cfg_sttWhisperCppServer: ""
    property string cfg_sttRemoteUrl: ""
    property string cfg_sttRemoteModel: "whisper-1"
    property string cfg_sttCommand: ""

    // The dictation settings as they are on the page, as the helper takes them.
    readonly property var sttDraft: {
        var draft = {};
        for (var i = 0; i < SttConfig.KEYS.length; i++)
            draft[SttConfig.KEYS[i]] = page["cfg_" + SttConfig.KEYS[i]];
        return SttConfig.payload(draft);
    }

    // Called by Plasma on OK/Apply, before it saves the cfg_ values: the
    // dictation service appears or disappears without restarting anything.
    function saveConfig() {
        if (runHelper)
            runHelper("stt_sync_units", sttDraft, null);
    }

    readonly property var configuration: typeof plasmoid !== "undefined" && plasmoid ? plasmoid.configuration : null
    // Tests pass fakes for these.
    property var runHelper: defaultRunner.run
    property var pluginOverride: ({})
    // Tests: stands in for the KWallet D-Bus call (store/Wallet.qml `call`).
    property var walletCall: null

    readonly property var engine: Engines.engine(cfg_voiceTtsEngine) || Engines.engine(Engines.defaultEngine)
    readonly property bool engineAvailable: probe.available.indexOf(engine.id) >= 0

    readonly property var allOptions: {
        var out = [];
        Engines.engines.forEach(function(e) {
            e.options.forEach(function(o) { out.push(Object.assign({"engine": e.id}, o)); });
        });
        return out;
    }

    function optionValue(key) { return page["cfg_" + key]; }
    function setOption(key, value) { page["cfg_" + key] = value; }

    // The read-aloud settings as they are on the page (for the test button).
    function draftConfiguration() {
        var draft = {"voiceTtsEngine": engine.id};
        var keys = Engines.optionKeys();
        for (var key in keys)
            draft[key] = optionValue(key);
        return draft;
    }

    function testSpeech() {
        if (tester.isPlaying) {
            tester.stop();
            return;
        }
        testResult = "";
        tester.configuration = draftConfiguration();
        tester.speak(i18n("Hello! This is how replies will sound."));
    }
    property string testResult: ""

    // Engines are looked for once read aloud is on (and the page is complete).
    property bool _complete: false
    function probeIfNeeded() {
        if (_complete && cfg_voiceTtsEnabled && probe.available.length === 0 && !probe.probing)
            probe.refresh();
        var remote = (cfg_voiceTtsEnabled && engine.id === "remote") || (cfg_sttEnabled && cfg_sttEngine === "remote");
        if (_complete && remote && wallet.status === "unknown") {
            if (walletCall)
                wallet.call = walletCall;
            wallet.load();
        }
    }
    onCfg_voiceTtsEnabledChanged: probeIfNeeded()
    onCfg_sttEngineChanged: probeIfNeeded()
    onCfg_sttEnabledChanged: probeIfNeeded()
    onEngineChanged: probeIfNeeded()
    Component.onCompleted: { _complete = true; probeIfNeeded(); }

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    Store.Wallet { id: wallet }

    Voice.TtsProbe {
        id: probe
        runHelper: page.runHelper
        pluginOverride: page.pluginOverride
    }

    Voice.ReadAloud {
        id: tester
        runHelper: page.runHelper
        pluginOverride: page.pluginOverride
        idleUnloadMs: 30000
        onError: function(message) { page.testResult = i18n("Read aloud failed: %1", message); }
        onIsPlayingChanged: if (!isPlaying && page.testResult === "") page.testResult = i18n("Finished.")
    }

    ColumnLayout {
        Kirigami.FormLayout {
            id: voiceForm
            Layout.fillWidth: true
            QQC2.CheckBox {
                id: readCheck
                objectName: "readAloudSwitch"
                Kirigami.FormData.label: i18n("Read aloud:")
                text: i18n("Offer to read replies aloud")
            }

            QQC2.CheckBox {
                id: enabledCheck
                objectName: "dictationSwitch"
                Kirigami.FormData.label: i18n("Dictation:")
                text: i18n("Show a microphone button in the chat")
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Read aloud")
                visible: readCheck.checked
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Engine:")
                visible: readCheck.checked
                QQC2.ComboBox {
                    id: engineCombo
                    objectName: "ttsEngineCombo"
                    textRole: "text"
                    valueRole: "value"
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                    model: {
                        var list = probe.available.map(function(id) { return {"value": id, "text": i18n(Engines.engine(id).label)}; });
                        // A saved engine that isn't available now stays visible, marked.
                        if (!page.engineAvailable && !probe.probing)
                            list.push({"value": page.engine.id, "text": i18n("%1 (not available)", i18n(page.engine.label))});
                        return list;
                    }
                    currentIndex: count > 0 ? Math.max(0, indexOfValue(page.engine.id)) : -1
                    onActivated: page.cfg_voiceTtsEngine = currentValue
                }
                QQC2.BusyIndicator {
                    visible: probe.probing
                    running: visible
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
            }

            QQC2.Label {
                visible: readCheck.checked
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.75
                text: i18n(page.engine.note) + (probe.available.indexOf("piper") < 0 && !probe.probing
                      ? "\n" + i18n("Piper is offered once its piper program is installed.") : "")
            }

            // Every engine's options, made once; only the chosen engine's show
            // (FormLayout copes badly with rows being destroyed).
            Repeater {
                model: page.allOptions
                delegate: Config.TtsOption {
                    form: page
                    voiceProbe: probe
                    keyStore: wallet
                    engineId: modelData.engine
                    visible: readCheck.checked && engineId === page.engine.id
                    language: {
                        var spec = Engines.engine(engineId).options.filter(function(o) { return o.type === "language"; })[0];
                        return spec ? String(page.optionValue(spec.key) || "") : "";
                    }
                }
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Try it:")
                visible: readCheck.checked
                QQC2.Button {
                    objectName: "ttsTestButton"
                    text: tester.isPlaying ? i18n("Stop") : i18n("Say Hello")
                    icon.name: tester.isPlaying ? "media-playback-stop" : "audio-speakers"
                    enabled: tester.isPlaying || page.engineAvailable
                    onClicked: page.testSpeech()
                }
                QQC2.Label {
                    objectName: "ttsTestResult"
                    text: tester.isPlaying ? (tester.phase === "synthesizing" ? i18n("Making speech…") : i18n("Speaking…")) : page.testResult
                    wrapMode: Text.Wrap
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 18
                }
            }

            QQC2.CheckBox {
                id: ttsAutoCheck
                visible: readCheck.checked
                text: i18n("Read every reply aloud when it is finished")
            }

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Dictation")
                visible: enabledCheck.checked
            }
        }

        Config.DictationSettings {
            id: dictation
            visible: enabledCheck.checked
            active: enabledCheck.checked
            form: page
            keyStore: wallet
            runHelper: page.runHelper
            payload: page.sttDraft
            twin: voiceForm
            Layout.fillWidth: true
        }
    }
}
