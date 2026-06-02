import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.TextField {
    required property string providerLabel
    required property string providerId
    required property var page
    property bool fieldVisible: false
    property string fieldPlaceholder: ""

    Kirigami.FormData.label: providerLabel
    visible: page ? page.providerEnabled(providerId) && fieldVisible : fieldVisible
    Layout.fillWidth: true
    placeholderText: fieldPlaceholder
}
