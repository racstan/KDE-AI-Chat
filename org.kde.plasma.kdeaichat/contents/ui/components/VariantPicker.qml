// A drop-down for a model's variant (reasoning / thinking level, see
// Variants.js). It is only visible when the model has variants: a source that
// reports none gets no picker. The first entry ("Default") means no variant:
// nothing is sent for it.
//
// API:
//   variants   [{id, label}] the model's variants (empty: the picker is hidden)
//   value      the stored variant id (bind it; the picker never writes it)
//   picked(id) emitted when the user chooses ("" for Default)
import QtQuick
import QtQuick.Controls as QQC2

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QQC2.ComboBox {
    id: picker

    property var variants: []
    property string value: ""

    signal picked(string id)

    readonly property var entries: [{"id": "", "label": i18n("Default")}].concat(variants || [])

    visible: (variants || []).length > 0
    model: entries
    textRole: "label"
    valueRole: "id"
    Accessible.name: i18n("Variant")
    onActivated: picked(String(currentValue || ""))

    // Shows the stored id's entry; a stored id the model does not offer shows as
    // Default: nothing is sent for it. Done by hand (not a binding): the combo
    // box resets its index whenever its model changes.
    function sync() {
        var at = 0;
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].id === value)
                at = i;
        }
        currentIndex = at;
    }
    onValueChanged: sync()
    onCountChanged: sync()
    onEntriesChanged: Qt.callLater(sync)
    onModelChanged: Qt.callLater(sync)
    Component.onCompleted: sync()
}
