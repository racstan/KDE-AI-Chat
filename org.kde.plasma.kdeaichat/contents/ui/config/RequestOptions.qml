// How requests to a provider are made in direct mode: the time limit and
// whether replies are shown while they are written. The settings page owns
// the saved values (cfg_requestTimeout, cfg_disableStreaming); this form only
// edits them.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: options

    // Seconds; 0 means no time limit.
    property int timeout: 60
    property bool disableStreaming: false

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
            checked: options.timeout > 0
            onToggled: options.timeout = checked ? Math.max(1, timeoutSpin.value) : 0
        }
        QQC2.SpinBox {
            id: timeoutSpin
            enabled: timeoutCheck.checked
            from: 1
            to: 600
            stepSize: 5
            editable: true
            value: options.timeout > 0 ? options.timeout : 60
            onValueModified: options.timeout = value
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
        checked: !options.disableStreaming
        onToggled: options.disableStreaming = !checked
    }
}
