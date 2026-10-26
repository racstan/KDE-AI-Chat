// Checks, repairs and tests the local dictation (speech-to-text) engine for
// Settings → Voice. Read aloud doesn't use it any more (voice/ReadAloud.qml).
//
// Runs voice/voice_helper.py (in the engine's venv) for checks and tests,
// voice/venv_setup.sh to repair the engine, and the helper's
// setup_venv_services to install or update the systemd user unit.
import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "../Security.js" as Sec

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Item {
    id: engine

    // Current (possibly unsaved) values from the page.
    property string venvPath: "~/.local/share/kdeaichat/venv"
    property string espeakPath: ""
    property string sttPath: ""
    property string language: "auto"
    property bool gpu: false
    property bool voiceEnabled: false

    property var env: null            // last check_env reply
    property bool checking: false
    property bool repairing: false
    property int progress: 0
    property string status: ""
    property bool sttTesting: false
    property string sttResult: ""

    property string _checkSource: ""
    property string _sttSource: ""

    readonly property bool sttReady: !!(env && env.stt_ready)
    readonly property bool ready: sttReady
    readonly property bool repairNeeded: !!env && (!env.venv_ready || !env.faster_whisper_ok || !env.sounddevice_ok
        || (gpu && !env.torch_cuda_version))

    function filePath(relative) {
        var path = decodeURIComponent(String(Qt.resolvedUrl(relative)).replace(/^file:\/\//, ""));
        return path.indexOf("/contents/ui/") >= 0 ? path : "";
    }

    function venvPython() {
        var py = (venvPath || "~/.local/share/kdeaichat/venv") + "/bin/python3";
        return py.indexOf("~/") === 0 ? '"$HOME"' + Sec.quoteForShell(py.substring(1)) : Sec.quoteForShell(py);
    }

    function servicePayload() {
        return Sec.base64Encode(JSON.stringify({"venvPy": (venvPath || "~/.local/share/kdeaichat/venv") + "/bin/python3",
            "espeakPath": espeakPath, "voiceEnabled": voiceEnabled}));
    }

    function shell(script, tag, seconds) {
        var source = (seconds ? "timeout " + seconds + "s " : "") + "sh -c " + Sec.rawShellSnippetQuote(script)
            + " #voice-" + tag + "-" + Date.now();
        ds.connectSource(source);
        return source;
    }

    function helperCommand(payload, tag, seconds) {
        var helper = Sec.quoteForShell(filePath("../voice/voice_helper.py"));
        var arg = Sec.rawShellSnippetQuote(Sec.base64Encode(JSON.stringify(payload)));
        var py = venvPython();
        return shell("if [ -f " + py + " ]; then " + py + " " + helper + " --command-b64 " + arg
                     + "; else python3 " + helper + " --command-b64 " + arg + "; fi", tag, seconds);
    }

    function installServices() {
        var helper = filePath("../kde_ai_helper.py");
        if (helper)
            shell("if [ -f " + venvPython() + " ]; then python3 " + Sec.quoteForShell(helper) + " setup_venv_services "
                  + Sec.rawShellSnippetQuote(servicePayload()) + "; fi", "services", 30);
    }

    // Stops and disables the dictation service.
    function disableServices() {
        shell("systemctl --user disable --now kde-ai-stt.service 2>/dev/null; pkill -f 'voice_helper.py --stt-server' 2>/dev/null; true", "stop");
    }

    function check() {
        checking = true;
        status = i18n("Checking folders, microphone and engine packages…");
        _checkSource = helperCommand({"cmd": "check_env", "stt_model_path": sttPath, "tts_model_path": "",
                                      "venv_path": venvPath, "espeak_path": espeakPath, "gpu_requested": gpu}, "check", 25);
        checkTimer.restart();
    }

    function repair() {
        var setup = filePath("../voice/venv_setup.sh");
        var helper = filePath("../kde_ai_helper.py");
        if (!setup || !helper) {
            status = i18n("The voice setup files are missing.");
            return;
        }
        repairing = true;
        progress = 0;
        status = i18n("Installing the voice engine. Models are not downloaded yet.");
        shell("NON_INTERACTIVE=1 bash " + Sec.quoteForShell(setup) + " " + Sec.quoteForShell(venvPath) + " "
              + Sec.quoteForShell(gpu ? "gpu" : "cpu") + " && python3 " + Sec.quoteForShell(helper)
              + " setup_venv_services " + Sec.rawShellSnippetQuote(servicePayload()), "setup");
    }

    // Transcribes the bundled sample with faster-whisper (helper stt_test; no microphone).
    function testStt() {
        var helper = filePath("../kde_ai_helper.py");
        sttTesting = true;
        sttResult = i18n("Loading the speech model…");
        var payload = {"sttEngine": "faster-whisper", "sttModel": sttPath || "small", "sttLanguage": language || "auto",
                       "sttDevice": gpu ? "cuda" : "auto", "venv": venvPath};
        _sttSource = shell("python3 " + Sec.quoteForShell(helper) + " stt_test "
                           + Sec.rawShellSnippetQuote(Sec.base64Encode(JSON.stringify(payload))), "stt", 75);
        sttTimer.restart();
    }

    // The stop marker also stops a test running in a separate helper process.
    function cancelStt() {
        if (_sttSource) ds.disconnectSource(_sttSource);
        _sttSource = "";
        sttTesting = false;
        sttResult = i18n("Recording stopped.");
    }

    function explain(r) {
        if (!r.stt_model_path_ok) return i18n("The speech-to-text folder has no model files.");
        if (!r.venv_exists) return i18n("The voice engine is not installed. Press Repair.");
        if (!r.sounddevice_ok || !r.numpy_ok || !r.faster_whisper_ok) return i18n("Engine packages are missing or broken. Press Repair.");
        if (!r.mic_available) return i18n("No microphone was found.");
        return i18n("Not ready.");
    }

    function devTag(r) {
        return r.device ? " [" + String(r.device).toUpperCase() + "]" : "";
    }

    function handle(r) {
        var steps = {"creating_venv": i18n("Creating the voice engine…"), "upgrading_pip": i18n("Preparing Python packages…"),
                     "installing_pytorch": i18n("Installing the speech runtime…"), "installing_spacy": i18n("Installing language packages…"),
                     "installing_dependencies": i18n("Installing speech packages…"), "installing_kokoro": i18n("Installing text-to-speech support…")};
        switch (r.type) {
        case "env_check":
            env = r; checking = false; repairing = false; checkTimer.stop();
            status = ready ? i18n("Ready.") : explain(r);
            break;
        case "setup_status":
            if (r.percent !== undefined) progress = r.percent;
            if (r.status === "done") { status = i18n("Engine installed. Checking again…"); check(); }
            else if (steps[r.status]) status = steps[r.status];
            break;
        case "setup_error": case "error":
            repairing = false; checking = false; sttTesting = false;
            status = r.error || i18n("Setting up the voice engine failed.");
            break;
        case "stt_status":
            sttResult = (r.status === "recording" ? i18n("Recording. Speak now…") : r.status === "transcribing"
                         ? i18n("Transcribing…") : i18n("Loading the speech model…")) + devTag(r);
            break;
        case "stt_result":
            sttTesting = false; sttTimer.stop();
            sttResult = (r.text ? r.text : i18n("No speech heard.")) + devTag(r);
            break;
        case "stt_error":
            sttTesting = false; sttTimer.stop();
            sttResult = i18n("Speech-to-text failed: %1", r.error || i18n("unknown error"));
            break;
        }
    }

    // Called when a command ends without a usable reply.
    function noReply(sourceName, stderr) {
        if (!sourceName)
            return;
        ds.disconnectSource(sourceName);
        if (sourceName === _checkSource) { checking = false; repairing = false; status = stderr || i18n("The check got no reply. Repair the engine, then check again."); }
        else if (sourceName === _sttSource) { sttTesting = false; sttResult = stderr || i18n("Speech-to-text got no reply. Check the folder and the engine."); }
        else if (stderr) { repairing = false; status = stderr; }
    }

    P5Support.DataSource {
        id: ds
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName);
            var handled = false;
            var lines = String(data["stdout"] || "").split("\n");
            for (var i = 0; i < lines.length; i++) {
                try {
                    var reply = JSON.parse(lines[i]);
                    if (reply && reply.type) { engine.handle(reply); handled = true; }
                } catch (e) {}
            }
            if (!handled)
                engine.noReply(sourceName, String(data["stderr"] || "").trim().split("\n").slice(-3).join("\n"));
        }
    }

    Timer {
        id: checkTimer
        interval: 30000
        onTriggered: engine.noReply(engine._checkSource, i18n("The check timed out after 30 seconds."))
    }
    Timer {
        id: sttTimer
        interval: 80000
        onTriggered: engine.noReply(engine._sttSource, i18n("The speech-to-text test timed out."))
    }
}
