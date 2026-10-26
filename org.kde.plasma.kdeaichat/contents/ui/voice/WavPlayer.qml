// Plays one sound file for voice/FileSpeech.qml (Qt Multimedia), with
// pause and stop. `ended` fires once when the file has played to its end.
import QtQuick
import QtMultimedia

Item {
    id: player

    signal ended()
    signal failed(string message)

    function play(path) {
        media.source = "file://" + encodeURI(path);
        media.play();
    }
    function pause() { media.pause(); }
    function resume() { media.play(); }
    function stop() {
        media.stop();
        media.source = "";
    }

    MediaPlayer {
        id: media
        audioOutput: AudioOutput {}
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia)
                player.ended();
        }
        onErrorOccurred: function(error, errorString) {
            player.failed(errorString || "The sound could not be played.");
        }
    }
}
