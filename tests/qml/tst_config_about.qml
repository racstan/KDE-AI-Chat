// Settings → About (ConfigAbout.qml): name, version, description, license,
// author, source link and credits, and the "Buy Me a Coffee" and "Read the
// terms" buttons (moved here from Appearance). Links open through the page's
// openUrl, which the test replaces: no browser is started.
import QtQuick
import QtTest

Item {
    id: root
    width: 820
    height: 760

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property var opened: []

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    HarnessTestCase {
        id: testCase
        name: "ConfigAbout"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open(props) {
            var component = Qt.createComponent(uiDir + "ConfigAbout.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({
                "width": root.width, "height": root.height,
                "openUrl": function(url) { root.opened.push(url); }
            }, props || {}));
            verify(page !== null);
            return page;
        }
        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            root.opened = [];
            wait(200);
        }

        function test_facts() {
            open({"version": "1.4.0"});
            compare(findChild(page, "aboutVersion").text, "1.4.0");
            verify(findChild(page, "aboutDescription").text.length > 20);
            compare(findChild(page, "aboutLicense").text, "GPL-3.0-or-later");
            compare(findChild(page, "aboutAuthor").text, "Rachit Asthana");
            var credits = findChild(page, "aboutCredits").text;
            verify(credits.indexOf("Speech Note") >= 0 && credits.indexOf("Michał Kosciesza") >= 0 && credits.indexOf("MPL-2.0") >= 0, credits);
            wait(300);
            screenshot(page, "config-about");
        }

        function test_version_without_plasma() {
            open();
            compare(findChild(page, "aboutVersion").text, "dev", "no plasmoid: a plain placeholder");
        }

        function test_source_link() {
            open();
            var button = findChild(page, "sourceButton");
            verify(button !== null);
            button.clicked();
            compare(root.opened.join(","), "https://github.com/racstan/KDE-AI-Chat");
        }

        function test_donate_link() {
            open();
            var button = findChild(page, "donateButton");
            verify(button !== null);
            compare(button.text, "Buy Me a Coffee");
            verify(findChild(page, "donateHelp").text.length > 20);
            button.clicked();
            compare(root.opened.join(","), "https://buymeacoffee.com/rachitasthana");
        }

        function test_terms_link() {
            open();
            var button = findChild(page, "termsButton");
            verify(button !== null);
            verify(findChild(page, "termsHelp").text.indexOf("warranty") >= 0);
            button.clicked();
            compare(root.opened[root.opened.length - 1], "https://github.com/racstan/KDE-AI-Chat/blob/master/TERMS.md");
        }

        function test_no_settings_of_its_own() {
            open();
            for (var name in page)
                verify(name.indexOf("cfg_") !== 0, name + " would be saved by the settings dialog");
        }
    }
}
