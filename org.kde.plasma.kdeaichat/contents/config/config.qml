import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Widget Shortcuts")
        icon: "preferences-desktop-keyboard-shortcuts"
        source: "ConfigShortcuts.qml"
    }
}
