// The result of the last dictation engine check, one row per requirement.
// (Read aloud has no engine to check: Settings → Voice tests it directly.)
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

GridLayout {
    id: grid

    property var env: ({})
    property bool gpu: false

    columns: 2
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: 0

    readonly property var checks: [
        {"label": i18n("Speech-to-text folder"), "ok": !!env.stt_model_path_ok, "bad": i18n("no model files")},
        {"label": i18n("Speech-to-text engine"), "ok": !!(env.faster_whisper_ok && env.sounddevice_ok), "bad": i18n("needs repair")},
        {"label": i18n("Engine environment"), "ok": !!env.venv_ready, "bad": env.venv_exists ? i18n("broken") : i18n("not installed")},
        {"label": i18n("GPU libraries"), "ok": !!env.torch_cuda_version, "off": !gpu, "bad": i18n("missing"),
         "good": env.torch_cuda_version ? i18n("CUDA %1", env.torch_cuda_version) : ""},
        {"label": i18n("Microphone"), "ok": !!env.mic_available, "bad": i18n("not found")}
    ]

    Repeater {
        model: grid.checks.length * 2
        delegate: RowLayout {
            id: cell
            required property int index
            readonly property var row: grid.checks[Math.floor(index / 2)]
            readonly property bool isLabel: index % 2 === 0
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                visible: !cell.isLabel
                source: cell.row.off ? "dialog-information" : (cell.row.ok ? "dialog-ok-apply" : "dialog-error")
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            QQC2.Label {
                text: cell.isLabel ? cell.row.label
                    : cell.row.off ? i18n("not used") : (cell.row.ok ? (cell.row.good || i18n("OK")) : cell.row.bad)
                color: cell.isLabel || cell.row.off ? Kirigami.Theme.textColor
                    : (cell.row.ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor)
                opacity: cell.isLabel ? 0.8 : 1
            }
        }
    }
}
