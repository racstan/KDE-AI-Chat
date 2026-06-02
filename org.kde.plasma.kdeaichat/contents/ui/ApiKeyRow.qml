import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ProviderData.js" as ProviderData

RowLayout {
    id: root

    property string providerId: ""
    visible: (typeof page !== "undefined" && typeof page.providerEnabled === "function") ? page.providerEnabled(providerId) : true
    property alias text: field.text
    property alias field: field
    property bool autoSave: true
    property string hideText: qsTr("Hide")
    property string showText: qsTr("Show")

    Kirigami.FormData.label: {
        var p = ProviderData.getProvider(root.providerId);
        return (p ? p.name : root.providerId) + " " + qsTr("key:");
    }
    Layout.fillWidth: true
    Layout.maximumWidth: Math.min(parent ? parent.width : 400, 480)

    QQC2.TextField {
        id: field

        Layout.fillWidth: true
        Layout.maximumWidth: parent.width - showHideBtn.implicitWidth - parent.spacing
        echoMode: showHideBtn.checked ? TextInput.Normal : TextInput.Password
        onEditingFinished: {
            if (root.autoSave && root.providerId) {
                page.saveKey(root.providerId, field.text);
                page.refreshIfActiveProvider(root.providerId);
            }
            root.editingFinished();
        }
    }

    QQC2.Button {
        id: showHideBtn

        checkable: true
        text: checked ? root.hideText : root.showText
    }
}
