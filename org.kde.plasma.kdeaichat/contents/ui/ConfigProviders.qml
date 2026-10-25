// Settings → Providers: the direct-mode providers and how requests to them
// are made. Providers are edited in config/ProvidersPanel.qml, which saves
// immediately (keys go to KWallet, never to a cfg_ property).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "store" as Store
import "config" as Config

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    // 0 means no time limit.
    property int cfg_requestTimeout: 60
    property bool cfg_disableStreaming: false

    readonly property var configuration: typeof plasmoid !== "undefined" && plasmoid ? plasmoid.configuration : null
    readonly property Store.Wallet wallet: Store.Wallet {}
    readonly property string harnessName: !configuration ? "" : configuration.useOpenCode ? "OpenCode"
        : configuration.usePi ? "Pi" : ""

    Component.onCompleted: wallet.load()

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.harnessName !== ""
            type: Kirigami.MessageType.Information
            text: i18n("Chats currently go through %1 (see Harness). These providers are used when it is turned off.", page.harnessName)
        }

        Config.ProvidersPanel {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 40
            Layout.alignment: Qt.AlignHCenter
            configuration: page.configuration
            wallet: page.wallet
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Requests")
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Time limit:")
                spacing: Kirigami.Units.smallSpacing

                QQC2.CheckBox {
                    id: timeoutCheck
                    text: i18n("Give up after")
                    checked: page.cfg_requestTimeout > 0
                    onToggled: page.cfg_requestTimeout = checked ? Math.max(1, timeoutSpin.value) : 0
                }
                QQC2.SpinBox {
                    id: timeoutSpin
                    enabled: timeoutCheck.checked
                    from: 1
                    to: 600
                    stepSize: 5
                    editable: true
                    value: page.cfg_requestTimeout > 0 ? page.cfg_requestTimeout : 60
                    onValueModified: page.cfg_requestTimeout = value
                    Accessible.name: i18n("Seconds before a request is given up")
                }
                QQC2.Label {
                    text: i18n("seconds")
                    enabled: timeoutCheck.checked
                }
            }

            QQC2.CheckBox {
                Kirigami.FormData.label: i18n("Replies:")
                text: i18n("Show replies while they are written")
                checked: !page.cfg_disableStreaming
                onToggled: page.cfg_disableStreaming = !checked
            }
        }
    }
}
