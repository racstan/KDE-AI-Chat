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
    SettingHelp {
        text: i18n("The usual choice: the widget talks to an AI service (such as OpenAI, Anthropic or OpenRouter) or to a model running on your own computer (such as Ollama).")
    }
    QQC2.RadioButton {
        text: i18n("Through OpenCode")
        checked: chooser.mode === "opencode"
        onToggled: if (checked) chooser.chosen("opencode")
    }
    SettingHelp {
        text: i18n("For coding help: OpenCode, a separate program, does the work and can read and change files in the chat's folder. It has to be installed.")
    }
    QQC2.RadioButton {
        text: i18n("Through Pi")
        checked: chooser.mode === "pi"
        onToggled: if (checked) chooser.chosen("pi")
    }
    SettingHelp {
        text: i18n("Like OpenCode, but with the Pi coding agent, which also has to be installed. A chat keeps the way it was started; this choice is for new chats.")
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: chooser.mode === "opencode" ? "OpenCode" : "Pi"
        visible: chooser.mode !== "direct"
    }
}
