// An area whose items use a custom accent colour (Settings → Appearance)
// for the chat's own highlights: selected text, the picked message, your
// bubbles, the accent buttons of cards. With no accent (the default) the
// Plasma theme is left alone and everything inside inherits it as before.
// FullRepresentationContent.qml is one; tests use it on their own.
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: area

    // "#rrggbb", or "" for the Plasma accent.
    property string accent: ""

    // Only with an accent does the area get colours of its own, from the
    // same colour set its parent uses, with the accent as highlight.
    Kirigami.Theme.inherit: accent === ""
    Kirigami.Theme.colorSet: area.parent ? area.parent.Kirigami.Theme.colorSet : Kirigami.Theme.Window

    Binding {
        target: area.Kirigami.Theme
        property: "highlightColor"
        value: area.accent
        when: area.accent !== ""
    }
}
