// Keeps Speech Note ready, so pressing the microphone or the speaker does not
// wait for a cold start (its service exits after about a minute idle, and a
// start takes several seconds).
//
// - When the popup opens and Speech Note is the engine of a feature that is
//   on, its service is started once in the background (an error is not shown:
//   the press itself explains it later).
// - While the popup is open, and for `speechNoteKeepReadyMinutes` after it
//   closes (0 = only when used), a timer asks the service to stay (helper
//   speechnote_keepalive_service: it never starts the service, only keeps a
//   running one). The speech model stays in memory for that time.
//
// `runHelper(command, payload, callback)` is store/HelperRunner.qml's run().
import QtQuick

Item {
    id: warm

    property var configuration: null
    property var runHelper: null
    property bool popupOpen: false
    // Tests: shorter times.
    property int tickMs: 45000
    property int minuteMs: 60000

    readonly property bool wanted: !!configuration
        && ((configuration.sttEnabled === true && String(configuration.sttEngine || "speechnote") === "speechnote")
            || (configuration.voiceTtsEnabled === true && String(configuration.voiceTtsEngine || "speechnote") === "speechnote"))
    readonly property int keepMinutes: configuration && configuration.speechNoteKeepReadyMinutes !== undefined
        ? Number(configuration.speechNoteKeepReadyMinutes) : 5
    // The keep-alive timer is running.
    readonly property bool keeping: keepTimer.running

    property double _until: 0

    function _call(command) {
        if (runHelper)
            runHelper(command, {}, null);
    }

    function _update() {
        if (popupOpen && wanted) {
            _until = 0;
            if (!_started) {
                _started = true;
                _call("speechnote_start");
            }
            if (keepMinutes > 0)
                keepTimer.start();
        } else if (!popupOpen) {
            _started = false;
            if (keepTimer.running && keepMinutes > 0 && wanted)
                _until = Date.now() + keepMinutes * minuteMs;
            else
                keepTimer.stop();
        }
    }
    property bool _started: false

    onPopupOpenChanged: _update()
    onWantedChanged: _update()
    Component.onCompleted: _update()

    Timer {
        id: keepTimer
        interval: warm.tickMs
        repeat: true
        onTriggered: {
            if (!warm.popupOpen && Date.now() >= warm._until) {
                stop();
                return;
            }
            warm._call("speechnote_keepalive_service");
        }
    }
}
