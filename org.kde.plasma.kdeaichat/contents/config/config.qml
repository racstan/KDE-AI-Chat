import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("System Prompt")
        icon: "dialog-scripts"
        source: "ConfigSystemPrompt.qml"
    }
}
