// Harness settings for Pi: the default provider and model, read from
// `pi --list-models` through the helper.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components" as Components

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: pi

    property string provider: ""
    property string model: ""
    property var helper: null        // store/HelperRunner.qml
    property bool active: false      // loads Pi's models when true

    property var providers: []
    property var modelsByProvider: ({})
    property string status: ""
    property bool busy: false

    onActiveChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()

    function choose(providerId, preferredModel) {
        var models = modelsByProvider[providerId] || [];
        var next = preferredModel || model;
        if (models.length > 0 && models.indexOf(next) < 0)
            next = models[0];
        provider = providerId;
        model = next || "";
    }

    function applyModels(reply) {
        var list = (reply && reply.providers) || [];
        var ids = [];
        var map = {};
        for (var i = 0; i < list.length; i++) {
            var id = list[i] && list[i].id;
            if (!id || ids.indexOf(id) >= 0)
                continue;
            ids.push(id);
            map[id] = Array.isArray(list[i].models) ? list[i].models : [];
        }
        modelsByProvider = map;
        providers = ids;
        if (ids.length === 0) {
            status = reply && (reply.message || reply.error) ? String(reply.message || reply.error)
                                                            : i18n("Pi listed no models.");
            return;
        }
        choose(ids.indexOf(provider) >= 0 ? provider : ids[0], model);
        status = i18n("%1 providers available.", ids.length);
    }

    function refresh() {
        if (!helper)
            return;
        busy = true;
        status = i18n("Asking Pi for its models…");
        helper.run("get_pi_models", {}, function(stdout, exitCode, stderr) {
            pi.busy = false;
            try {
                pi.applyModels(JSON.parse(stdout));
            } catch (e) {
                pi.status = stderr || i18n("Pi could not be run.");
            }
        });
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Provider:")
        Layout.fillWidth: true

        QQC2.ComboBox {
            Layout.fillWidth: true
            enabled: pi.providers.length > 0
            model: pi.providers.length > 0 ? pi.providers : (pi.provider ? [pi.provider] : [])
            currentIndex: Math.max(0, model.indexOf(pi.provider))
            onActivated: pi.choose(currentText, "")
        }
        QQC2.Button {
            icon.name: "view-refresh"
            text: i18n("Refresh")
            enabled: !pi.busy
            onClicked: pi.refresh()
        }
    }

    Components.ModelPicker {
        Kirigami.FormData.label: i18n("Model:")
        Layout.fillWidth: true
        model: pi.modelsByProvider[pi.provider] || []
        value: pi.model
        onPicked: function(id) { pi.model = id; }
    }

    QQC2.Label {
        Kirigami.FormData.label: i18n("Status:")
        Layout.fillWidth: true
        visible: pi.status !== ""
        text: pi.status
        wrapMode: Text.Wrap
        opacity: 0.8
    }
}
