import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Behavior")
        icon: "preferences-system-behavior"
        source: "ConfigSystemPrompt.qml"
    }
    ConfigCategory {
        name: i18n("Other Settings")
        icon: "preferences-other"
        source: "ConfigOther.qml"
    }
}
