// First screen of the first-run setup: where the AI runs. Local servers found
// on this computer first (nothing to enter), then the common online services.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() and i18np() come from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: choose

    // The FirstRun.qml that owns the state.
    property var ctl: null

    spacing: Kirigami.Units.smallSpacing

    Kirigami.Heading {
        level: 4
        text: i18n("Choose where your AI runs")
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    // ── On this computer ──────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        visible: choose.ctl.servers.length > 0 || choose.ctl.scanning
        Kirigami.Heading {
            level: 5
            text: i18n("On this computer")
            opacity: 0.8
            Layout.fillWidth: true
        }
        QQC2.BusyIndicator {
            visible: choose.ctl.scanning
            running: choose.ctl.scanning
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
        }
    }

    Repeater {
        model: choose.ctl.servers
        delegate: FirstRunRow {
            id: serverRow
            required property var modelData
            objectName: "firstRunServer"
            iconName: "computer"
            title: serverRow.modelData.kind === "openai" ? i18n("OpenAI-compatible server") : serverRow.modelData.name
            detail: serverRow.modelData.needsKey ? i18n("Found here · asks for a key")
                : i18np("Found here · %1 model · stays on this computer", "Found here · %1 models · stays on this computer", serverRow.modelData.count)
            enabled: !choose.ctl.busy
            onClicked: choose.ctl.chooseServer(serverRow.modelData)
        }
    }

    // ── Online services ───────────────────────────────────────────────
    Kirigami.Heading {
        level: 5
        text: i18n("Online services")
        opacity: 0.8
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
    }

    Repeater {
        model: choose.ctl.cloud
        delegate: FirstRunRow {
            id: cloudRow
            required property var modelData
            objectName: "firstRunCloud"
            iconName: "internet-services"
            title: cloudRow.modelData.name
            detail: i18n("Needs your own key")
            onClicked: choose.ctl.chooseCloud(cloudRow.modelData)
        }
    }

    // ── Privacy and the way out ───────────────────────────────────────
    QQC2.Label {
        objectName: "firstRunPrivacy"
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        wrapMode: Text.Wrap
        opacity: 0.8
        font: Kirigami.Theme.smallFont
        linkColor: Kirigami.Theme.linkColor
        textFormat: Text.StyledText
        text: i18n("Online services see the messages you send them; a program on this computer keeps them here. <a href=\"%1\">Read the terms</a>.", choose.ctl.termsUrl)
        onLinkActivated: link => Qt.openUrlExternally(link)
    }

    QQC2.Label {
        objectName: "firstRunSkip"
        Layout.fillWidth: true
        linkColor: Kirigami.Theme.linkColor
        textFormat: Text.StyledText
        text: "<a href=\"skip\">" + i18n("Skip — I'll set it up in Settings") + "</a>"
        onLinkActivated: choose.ctl.skip()
        Accessible.role: Accessible.Link
        Accessible.name: i18n("Skip — I'll set it up in Settings")
    }
}
