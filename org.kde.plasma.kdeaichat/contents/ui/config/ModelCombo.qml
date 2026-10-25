// An editable model picker: lists the known model ids and accepts any other
// id typed in. It shows `value` and reports changes through picked(), so the
// owner's binding to `value` stays intact.
import QtQuick
import QtQuick.Controls as QQC2

QQC2.ComboBox {
    id: combo

    property string value: ""
    signal picked(string value)

    editable: true

    function sync() {
        var index = find(value);
        if (index >= 0) {
            currentIndex = index;
        } else {
            currentIndex = -1;
            editText = value;
        }
    }

    Component.onCompleted: sync()
    onModelChanged: sync()
    onValueChanged: if (!activeFocus) sync()
    onActivated: picked(currentText)
    onAccepted: picked(editText)
    onEditTextChanged: if (activeFocus && editText !== value) picked(editText)
}
