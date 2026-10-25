import QtQuick
import org.kde.plasma.configuration

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ConfigModel {
    ConfigCategory {
        name: i18n("Providers")
        icon: "network-server"
        source: "ConfigProviders.qml"
    }
    ConfigCategory {
        name: i18n("Harness")
        icon: "utilities-terminal"
        source: "ConfigHarness.qml"
    }
    ConfigCategory {
        name: i18n("Chat")
        icon: "dialog-messages"
        source: "ConfigChat.qml"
    }
    ConfigCategory {
        name: i18n("Schedules")
        icon: "view-calendar"
        source: "ConfigSchedules.qml"
    }
    ConfigCategory {
        name: i18n("Voice")
        icon: "audio-input-microphone"
        source: "ConfigVoice.qml"
    }
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-icons"
        source: "ConfigAppearance.qml"
    }
}
