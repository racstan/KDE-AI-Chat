// Base TestCase for widget component tests: offscreen screenshots and a fake
// plasmoid configuration.
//
// Screenshots land in build/qml-screens/<name>.png for visual review.
import QtQuick
import QtTest

TestCase {
    id: harness

    when: windowShown

    // Takes the focus while settleComposerFocus waits for the composer's focus timer.
    Item {
        id: focusSink
        width: 1
        height: 1
    }

    // Stand-in for `plasmoid.configuration`: tests set only the keys a
    // component reads.
    property var fakeConfiguration: ({})

    readonly property string screensDir: {
        let url = String(Qt.resolvedUrl("../../build/qml-screens/"));
        return decodeURIComponent(url.replace(/^file:\/\//, ""));
    }

    // The first item under `item` (itself included) with this objectName, or null.
    // Looks through visual children, so Loaders' items and ListView delegates are found.
    function findChild(item, objectName) {
        if (!item)
            return null;
        if (item.objectName === objectName)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findChild(kids[i], objectName);
            if (found)
                return found;
        }
        return null;
    }

    // Every item under `item` with this objectName.
    function findChildren(item, objectName, into) {
        into = into || [];
        if (!item)
            return into;
        if (item.objectName === objectName)
            into.push(item);
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++)
            findChildren(kids[i], objectName, into);
        return into;
    }

    // composer.focusInput() gives the input the focus and starts the composer's 120 ms focus timer,
    // which gives the input the focus again when it fires (Composer.qml). A test that moves the focus
    // while that timer is pending (a picked message, an edit in place) has it taken back in the middle
    // of the test, so this moves the focus away while the timer is pending and returns once the timer
    // has brought it back. wait(0) first runs the chat.focusInput() calls still queued from before.
    function settleComposerFocus(composer) {
        wait(0);
        composer.focusInput();
        focusSink.forceActiveFocus();
        tryVerify(() => composer.input.activeFocus, 1000, "the composer's focus timer gives the input its focus back");
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
