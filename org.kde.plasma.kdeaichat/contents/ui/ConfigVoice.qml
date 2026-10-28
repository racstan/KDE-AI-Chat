// Settings → Voice: two switches, both off by default. "Read aloud" adds a
// read-aloud button to replies and picks the engine (voice/TtsEngines.js:
// Speech Note, the system voice, or a speech server); "Dictation" adds the
// microphone button and picks Speech Note or a speech server. Speech Note is a
// separate app: the widget installs and runs no speech models itself.
//
// The read-aloud form is built from the engine's options (config/TtsOption.qml),
// the dictation form is config/DictationSettings.qml; every option is a cfg_
// property below, saved with OK/Apply (keys go to KWallet, never here).
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
    property string cfg_voiceTtsRemoteUrl: "http://localhost:8880/v1"
    property string cfg_voiceTtsRemoteModel: "tts-1"
    property string cfg_voiceTtsRemoteVoice: "alloy"
    property real cfg_voiceTtsRemoteSpeed: 1
    property string cfg_voiceTtsSpeechNoteModel: ""

    // Dictation (speech-to-text): voice/SttConfig.js lists these keys.
    property alias cfg_sttEnabled: enabledCheck.checked
    property bool cfg_voiceAutoSend: true
    property string cfg_sttEngine: "speechnote"
    property string cfg_sttLanguage: "auto"
    property string cfg_sttRemoteUrl: ""
    property string cfg_sttRemoteModel: "whisper-1"
    property string cfg_sttSpeechNoteModel: ""
    property int cfg_speechNoteKeepReadyMinutes: 5

    // The dictation settings as they are on the page, as the helper takes them.
    readonly property var sttDraft: {
        var draft = {};
        for (var i = 0; i < SttConfig.KEYS.length; i++)
            draft[SttConfig.KEYS[i]] = page["cfg_" + SttConfig.KEYS[i]];
        return SttConfig.payload(draft);
    }

    readonly property var configuration: typeof plasmoid !== "undefined" && plasmoid ? plasmoid.configuration : null
    // Tests pass fakes for these.
    property var runHelper: defaultRunner.run
    property var pluginOverride: ({})
    property var waitHelper: null
    // Tests: stands in for the KWallet D-Bus call (store/Wallet.qml `call`).
    property var walletCall: null

    // A saved engine that no longer exists counts as Speech Note (the widget moves it at start).
    readonly property var engine: Engines.engine(Engines.migratedEngine(cfg_voiceTtsEngine))
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
        var remote = (cfg_voiceTtsEnabled && engine.id === "remote") || (cfg_sttEnabled && SttConfig.migratedEngine(cfg_sttEngine) === "remote");
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

    // Speech Note's state, shared by the read-aloud and dictation parts.
    Config.SpeechNoteStatus {
        id: speechNoteInfo
        runHelper: page.runHelper
    }

    Voice.TtsProbe {
        id: probe
        pluginOverride: page.pluginOverride
    }

    Voice.ReadAloud {
        id: tester
        runHelper: page.runHelper
        waitHelper: page.waitHelper
        pluginOverride: page.pluginOverride
        idleUnloadMs: 30000
        onError: function(message) { page.testResult = i18n("Read aloud failed: %1", message); }
        onIsPlayingChanged: if (!isPlaying && page.testResult === "") page.testResult = usedFallback
            ? (engine.id !== "speechnote" ? i18n("That was the system voice.")
               : fallbackReason === "not_configured" ? i18n("That was the system voice, because Speech Note has no voice yet: download one in Speech Note.")
               : i18n("That was the system voice, because Speech Note is not installed: see the setup steps above.")) : i18n("Finished.")
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

            Config.SettingHelp {
                text: i18n("Adds a speaker button under each reply that reads it out loud. Choose the voice below.")
            }

            QQC2.CheckBox {
                id: enabledCheck
                objectName: "dictationSwitch"
                Kirigami.FormData.label: i18n("Dictation:")
                text: i18n("Show a microphone button in the chat")
            }

            Config.SettingHelp {
                text: i18n("Speak instead of typing: press the microphone, talk, and your words are written into the message box. The speech is turned into text on this computer unless you pick a server below.")
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
                    Accessible.name: i18n("Engine")
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
                    // Looked up in the model itself: indexOfValue() can lag when the list arrives late.
                    currentIndex: {
                        var list = model || [];
                        for (var i = 0; i < list.length; i++)
                            if (list[i].value === page.engine.id)
                                return i;
                        return list.length > 0 ? 0 : -1;
                    }
                    displayText: count === 0 && probe.probing ? i18n("Looking for voices…") : currentText
                    onActivated: page.cfg_voiceTtsEngine = currentValue
                }
                QQC2.BusyIndicator {
                    visible: probe.probing
                    running: visible
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
            }

            Config.SettingHelp {
                visible: readCheck.checked
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                details: i18n("The engine is the program that makes the speech. Speech Note is a separate app with natural voices in many languages; \"System voices\" works without any setup but sounds robotic; a speech server is one you run or pay for.")
                text: i18n(page.engine.note)
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

        }

        Config.SpeechNotePanel {
            objectName: "speechNoteReadAloud"
            role: "tts"
            showKeepReady: !(cfg_sttEnabled && SttConfig.migratedEngine(cfg_sttEngine) === "speechnote")   // shown once, with dictation when that uses it
            form: page
            status: speechNoteInfo
            twin: voiceForm
            visible: readCheck.checked && page.engine.id === "speechnote"
            active: visible
        }

        Kirigami.FormLayout {
            id: voiceForm2
            twinFormLayouts: [voiceForm]
            Layout.fillWidth: true

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

            Config.SettingHelp {
                visible: readCheck.checked
                text: i18n("Plays a short greeting with the settings above, so you can hear them before saving.")
            }

            QQC2.CheckBox {
                id: ttsAutoCheck
                visible: readCheck.checked
                text: i18n("Read every reply aloud when it is finished")
            }

            Config.SettingHelp {
                visible: readCheck.checked
                text: i18n("Hands-free: each new reply is spoken without pressing the speaker button. Stop it with the stop button or Ctrl+Shift+S.")
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
            speechNote: speechNoteInfo
            twin: voiceForm
            Layout.fillWidth: true
        }
    }
}
