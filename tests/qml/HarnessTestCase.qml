// Base TestCase for widget component tests: offscreen screenshots and a fake
// plasmoid configuration.
//
// Screenshots land in build/qml-screens/<name>.png for visual review.
import QtQuick
import QtTest

TestCase {
    id: harness

    when: windowShown

    // Stand-in for `plasmoid.configuration`: tests set only the keys a
    // component reads.
    property var fakeConfiguration: ({})

    readonly property string screensDir: {
        let url = String(Qt.resolvedUrl("../../build/qml-screens/"));
        return decodeURIComponent(url.replace(/^file:\/\//, ""));
    }

    // Saves `item` as build/qml-screens/<fileName>.png and returns the path.
    function screenshot(item, fileName) {
        let path = screensDir + fileName + ".png";
        let saved = false;
        verify(item.grabToImage(function(result) {
            saved = result.saveToFile(path);
        }), "grabToImage refused to start");
        tryVerify(() => saved, 5000, "screenshot not saved: " + path);
        return path;
    }
}
