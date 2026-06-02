import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

RowLayout {
    id: root

    property string providerId: ""
    property alias text: field.text
    property alias field: field
    property string hideText: qsTr("Hide")
    property string showText: qsTr("Show")

    signal editingFinished()

    Layout.fillWidth: true
    Layout.maximumWidth: Math.min(parent ? parent.width : 400, 480)

    QQC2.TextField {
        id: field

        Layout.fillWidth: true
        Layout.maximumWidth: parent.width - showHideBtn.implicitWidth - parent.spacing
        echoMode: showHideBtn.checked ? TextInput.Normal : TextInput.Password
        onEditingFinished: root.editingFinished()
    }

    QQC2.Button {
        id: showHideBtn

        checkable: true
        text: checked ? root.hideText : root.showText
    }
}
