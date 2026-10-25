// The first choice on the Connection page: where messages go. `mode` is
// "direct", "opencode" or "pi"; chosen(mode) is emitted when the user picks
// another one, and the page decides what that changes.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: chooser

    property string mode: "direct"
    signal chosen(string mode)

    QQC2.RadioButton {
        Kirigami.FormData.label: i18n("Send messages:")
        text: i18n("Directly to a provider")
        checked: chooser.mode === "direct"
        onToggled: if (checked) chooser.chosen("direct")
    }
    QQC2.RadioButton {
        text: i18n("Through OpenCode")
        checked: chooser.mode === "opencode"
        onToggled: if (checked) chooser.chosen("opencode")
    }
    QQC2.RadioButton {
        text: i18n("Through Pi")
        checked: chooser.mode === "pi"
        onToggled: if (checked) chooser.chosen("pi")
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: chooser.mode === "opencode" ? "OpenCode" : "Pi"
        visible: chooser.mode !== "direct"
    }
}
