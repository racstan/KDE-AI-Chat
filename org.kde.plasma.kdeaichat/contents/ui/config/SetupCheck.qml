// "Check setup": lists what the current settings need and whether this
// computer has it, each with a ✓/⚠/✗ and a one-line fix (SetupChecks.js has
// the checks' words; the helper's setup_check does the computer side). It
// only looks: nothing is installed or started. The one fix it can run is
// the existing schedules_sync ("Recreate timers").
//
// Used in Settings → Connection and, with `problemsOnly`, under an error in
// the chat (chat/ErrorActions.qml).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../ProviderService.js" as ProviderService
import "../store" as Store
import "SetupChecks.js" as SetupChecks

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: check

    property var configuration: null
    // store/Wallet.qml (status and keys); loaded first if it hasn't been yet.
    property var wallet: null
    // direct | opencode | pi; the settings page passes its unsaved choice.
    property string mode: configuration ? (configuration.useOpenCode ? "opencode" : (configuration.usePi ? "pi" : "direct")) : "direct"
    property string openCodeUrl: configuration ? String(configuration.openCodeUrl || "") : ""
    // Anything with run(command, payload, onDone); tests pass a fake.
    property var helper: defaultRunner
    // Only warnings and errors (with a line saying when there are none).
    property bool problemsOnly: false
    property bool showHeading: true

    property bool running: false
    property bool checked: false
    property var rows: []
    // What passed is hidden unless asked for: only what needs doing is shown.
    property bool showPassed: false
    readonly property var problemRows: rows.filter(function(r) { return r.status !== "ok"; })
    readonly property var shownRows: showPassed && !problemsOnly ? rows : problemRows
    readonly property var summary: SetupChecks.counts(rows)

    signal finished()

    spacing: Kirigami.Units.smallSpacing

    function tr(template, args) {
        var a = args || [];
        switch (a.length) {
        case 0: return i18n(template);
        case 1: return i18n(template, a[0]);
        case 2: return i18n(template, a[0], a[1]);
        default: return i18n(template, a[0], a[1], a[2]);
        }
    }

    function entries() {
        return ProviderService.parseProviders(configuration).filter(function(e) { return e.type !== "image"; })
            .map(function(e) {
                return {"id": e.id, "name": e.name, "baseUrl": e.baseUrl, "model": e.model,
                        "local": ProviderService.getProviderConfig(e.id, configuration).allowEmptyKey === true};
            });
    }

    function run() {
        if (running)
            return;
        running = true;
        var list = mode === "direct" ? entries() : [];
        var needsWallet = list.some(function(e) { return !e.local; });
        if (needsWallet && wallet && wallet.status === "unknown" && typeof wallet.load === "function")
            wallet.load(function() { check._runHelper(list); });
        else
            _runHelper(list);
    }

    function _runHelper(list) {
        var own = mode === "direct" ? SetupChecks.directChecks(list, wallet ? wallet.status : "unknown", wallet ? wallet.keys : {},
                                                                           configuration ? String(configuration.provider || "") : "") : [];
        if (!helper) {
            _done(own.concat(SetupChecks.parseHelper("", 1)));
            return;
        }
        helper.run("setup_check", SetupChecks.helperPayload(mode, configuration, list, openCodeUrl), function(stdout, exitCode) {
            check._done(own.concat(SetupChecks.parseHelper(stdout, exitCode)));
        });
    }

    function _done(result) {
        rows = result;
        running = false;
        checked = true;
        finished();
    }

    function runAction(action) {
        if (action === "sync-schedules" && helper) {
            running = true;
            helper.run("schedules_sync", {}, function() {
                check.running = false;
                check.run();
            });
        }
    }

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("../kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            visible: check.showHeading
            level: 4
            text: i18n("Check setup")
        }


        QQC2.Button {
            objectName: "setupCheckButton"
            text: check.checked ? i18n("Check again") : i18n("Check setup")
            icon.name: "system-search"
            enabled: !check.running
            onClicked: check.run()
        }

        QQC2.BusyIndicator {
            visible: check.running
            running: visible
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        }

        QQC2.Label {
            objectName: "setupCheckSummary"
            visible: check.checked && !check.running
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
            opacity: 0.8
            text: check.summary.error + check.summary.warn === 0 ? i18n("Everything is ready.")
                : check.summary.error > 0 && check.summary.warn > 0
                    ? i18nc("%1 is a number of problems, %2 a number of warnings", "%1, %2", i18np("%1 problem", "%1 problems", check.summary.error), i18np("%1 warning", "%1 warnings", check.summary.warn))
                : check.summary.error > 0 ? i18np("%1 problem", "%1 problems", check.summary.error)
                : i18np("%1 warning", "%1 warnings", check.summary.warn)
        }
    }

    QQC2.Label {
        visible: !check.checked && !check.running && check.showHeading
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.7
        text: i18n("Looks at what your settings need on this computer (programs, servers, keys, timers) and says how to fix what's missing. It changes nothing.")
    }

    Repeater {
        model: check.running ? [] : check.shownRows

        delegate: RowLayout {
            id: line
            required property var modelData
            readonly property var words: SetupChecks.message(modelData)
            readonly property string action: SetupChecks.ACTIONS[modelData.code] || ""

            objectName: "setupCheckRow"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: line.modelData.status === "ok" ? "emblem-ok-symbolic"
                    : line.modelData.status === "warn" ? "emblem-warning" : "emblem-error"
                Accessible.name: line.modelData.status === "ok" ? i18n("OK")
                    : line.modelData.status === "warn" ? i18n("Warning") : i18n("Problem")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                QQC2.Label {
                    objectName: "setupCheckText"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: check.tr(line.words[0], line.modelData.args)
                }

                QQC2.Label {
                    objectName: "setupCheckFix"
                    visible: text !== "" && line.modelData.status !== "ok"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.75
                    text: line.words[1] ? check.tr(line.words[1], line.modelData.args) : ""
                }
            }

            QQC2.Button {
                objectName: "setupCheckAction"
                visible: line.action !== ""
                text: i18n("Recreate timers")
                icon.name: "view-refresh"
                onClicked: check.runAction(line.action)
            }
        }
    }

    // The checks that passed, on request (Settings only).
    QQC2.Button {
        objectName: "setupCheckShowPassed"
        visible: !check.problemsOnly && check.checked && !check.running && check.rows.length > check.problemRows.length
        flat: true
        icon.name: check.showPassed ? "go-up" : "go-down"
        text: check.showPassed ? i18n("Hide what passed")
            : i18np("Show what passed (1 check)", "Show what passed (%1 checks)", check.rows.length - check.problemRows.length)
        onClicked: check.showPassed = !check.showPassed
    }

    QQC2.Label {
        objectName: "setupCheckAllGood"
        visible: check.problemsOnly && check.checked && !check.running && check.shownRows.length === 0
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.8
        text: i18n("The setup check found nothing wrong on this computer. The provider may be having trouble; try again in a moment.")
    }
}
