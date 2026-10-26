// A short video as the panel icon (chat/PanelIcon.qml loads it only in the
// video mode): muted (no audio output at all), looping, scaled to fit, and
// paused while `playing` is false. failed() when it can't be played, so the
// normal icon is shown instead.
import QtQuick
import QtMultimedia

Item {
    id: panelVideo

    property url source
    property bool playing: false
    signal failed()

    // Paused (not stopped), so the current frame stays on the panel.
    function sync() {
        if (player.mediaStatus === MediaPlayer.InvalidMedia || String(source) === "")
            return;
        if (playing)
            player.play();
        else
            player.pause();
    }

    onPlayingChanged: sync()
    onSourceChanged: sync()

    MediaPlayer {
        id: player
        source: panelVideo.source
        loops: MediaPlayer.Infinite
        videoOutput: output
        // No audioOutput: the video is always silent.
        onErrorOccurred: panelVideo.failed()
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.InvalidMedia)
                panelVideo.failed();
            else if (mediaStatus === MediaPlayer.LoadedMedia)
                panelVideo.sync();
        }
    }

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }
}
