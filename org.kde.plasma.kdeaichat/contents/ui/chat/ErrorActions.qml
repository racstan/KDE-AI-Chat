// What the user can do about an error message: Try again, Open settings
// (when settings can fix it), Change model (when another model is the fix), Check setup (when the setup check can find the
// cause: it runs config/SetupCheck.qml here, under the error, and lists only
// the problems) and, when the original message says more than the
// plain-language text, a way to read it. `info` is ErrorText.describe().
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../config" as Config
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: actions

    property var info: ({})
    property bool showDetail: false
    // The widget root (configuration, wallet, the chat's mode) for Check setup.
    property var chat: null
    property bool showCheck: false

    signal retryRequested()
    signal settingsRequested()
    signal copyRequested()
    signal deleteRequested()

    // With per-chat model settings the quick picker (the one /model opens) changes
    // just this chat's model; otherwise the model is chosen in Settings. Plasma
    // can't open its settings on a given page; Connection is the first one.
    function changeModel() {
        if (!chat)
            return;
        if (chat.plasmoid && chat.plasmoid.configuration.perChatModelSettings === true && chat.composerRef && chat.composerRef.picker)
            chat.composerRef.picker.open();
        else
            chat.openSettings();
    }

    spacing: Kirigami.Units.smallSpacing

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PrimaryButton {
            objectName: "retryButton"
            text: i18n("Try again")
            icon.name: "view-refresh"
            onClicked: actions.retryRequested()
        }

        PC3.Button {
            objectName: "settingsButton"
            visible: actions.info.settings === true && actions.info.changeModel !== true
            text: i18n("Open settings")
            icon.name: "configure"
            onClicked: actions.settingsRequested()
        }

        PC3.Button {
            objectName: "changeModelButton"
            visible: actions.info.changeModel === true
            text: i18n("Change model")
            icon.name: "configure"
            onClicked: actions.changeModel()
        }

        PC3.Button {
            objectName: "checkSetupButton"
            visible: actions.info.checkSetup === true && !!actions.chat
            text: i18n("Check setup")
            icon.name: "system-search"
            checkable: true
            checked: actions.showCheck
            onClicked: actions.showCheck = !actions.showCheck
        }

        PC3.ToolButton {
            objectName: "detailsButton"
            visible: !!actions.info.detail
            text: actions.showDetail ? i18n("Hide details") : i18n("Show details")
            icon.name: actions.showDetail ? "arrow-up" : "arrow-down"
            onClicked: actions.showDetail = !actions.showDetail
        }

        PC3.ToolButton {
            objectName: "copyErrorButton"
            display: PC3.AbstractButton.IconOnly
            icon.name: copied.running ? "checkmark" : "edit-copy"
            text: copied.running ? i18n("Copied") : i18n("Copy error")
            Accessible.name: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: text
            onClicked: {
                actions.copyRequested();
                copied.restart();
            }
        }

        PC3.ToolButton {
            objectName: "deleteErrorButton"
            display: PC3.AbstractButton.IconOnly
            icon.name: "trash-empty"
            text: i18n("Delete")
            Accessible.name: i18n("Delete this message")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: Accessible.name
            onClicked: actions.deleteRequested()
        }
    }

    Timer {
        id: copied
        interval: 1500
    }

    Loader {
        objectName: "setupCheckLoader"
        active: actions.showCheck && !!actions.chat
        visible: active
        Layout.fillWidth: true
        sourceComponent: Config.SetupCheck {
            problemsOnly: true
            showHeading: false
            configuration: actions.chat.plasmoid ? actions.chat.plasmoid.configuration : null
            wallet: actions.chat.wallet || null
            mode: actions.chat.openCodeMode ? "opencode" : (actions.chat.piMode ? "pi" : "direct")
            Component.onCompleted: {
                // Tests give the chat a fake helper; the widget uses the real one.
                if (actions.chat.setupCheckHelper)
                    helper = actions.chat.setupCheckHelper;
                run();
            }
        }
    }

    MonoBlock {
        objectName: "errorDetail"
        visible: actions.showDetail && !!actions.info.detail
        text: actions.info.detail || ""
        maxHeight: Kirigami.Units.gridUnit * 6
    }
}
