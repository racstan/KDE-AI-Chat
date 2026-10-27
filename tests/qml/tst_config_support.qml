// Settings → About (ConfigSupport.qml): name, version, description, license,
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
        name: "ConfigSupport"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null

        function open(props) {
            var component = Qt.createComponent(uiDir + "ConfigSupport.qml");
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

        function test_no_repeat_of_plasmas_about_page() {
            open();
            ["aboutVersion", "aboutDescription", "aboutLicense", "aboutAuthor", "sourceButton"].forEach(function(name) {
                compare(findChild(page, name), null, name + " belongs to Plasma's own About page");
            });
            var credits = findChild(page, "aboutCredits").text;
            verify(credits.indexOf("Speech Note") >= 0 && credits.indexOf("Michał Kosciesza") >= 0 && credits.indexOf("MPL-2.0") >= 0, credits);
            wait(300);
            screenshot(page, "config-support");
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
