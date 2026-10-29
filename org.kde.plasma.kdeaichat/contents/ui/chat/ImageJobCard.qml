// The progress of a picture being made: the place in AI Horde's queue and the
// wait time, or Pollinations' free-service countdown, with a Stop button.
// `job` is the reply's imageJob ({service, name, phase, queuePosition, waitTime,
// seconds, possible, ...}, see chat/ImageJobs.qml).
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Rectangle {
    id: card

    property var job: ({})
    // False for a job left over from before the widget was closed: nothing is running.
    property bool live: true

    signal stopRequested()

    function duration(seconds) {
        var s = Math.max(0, Math.round(Number(seconds) || 0));
        return s < 90 ? i18n("%1 s", s) : i18n("%1 min", Math.ceil(s / 60));
    }

    readonly property string status: {
        var name = job.name || i18n("The image service");
        if (!live)
            return i18n("This picture was not finished.");
        if (job.phase === "countdown")
            return i18n("The older free %1 service makes one picture every 45 seconds. Yours starts in %2.", name, duration(job.seconds));
        if (job.possible === false)
            return i18n("%1 has no worker for this model right now. It keeps looking for a while.", name);
        if (job.phase === "queued" && job.queuePosition > 0)
            return job.waitTime > 0 ? i18n("In %1's queue: place %2, about %3 left.", name, job.queuePosition, duration(job.waitTime))
                                    : i18n("In %1's queue: place %2.", name, job.queuePosition);
        if (job.phase === "queued")
            return job.waitTime > 0 ? i18n("Waiting for %1: about %2 left.", name, duration(job.waitTime)) : i18n("Waiting for %1…", name);
        if (job.phase === "working")
            return job.waitTime > 0 ? i18n("%1 is making your picture: about %2 left.", name, duration(job.waitTime)) : i18n("%1 is making your picture…", name);
        return i18n("Sending your prompt to %1…", name);
    }

    implicitHeight: row.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.cornerRadius
    color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
    border.width: 1
    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        PC3.BusyIndicator {
            running: card.live
            visible: card.live
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }

        PC3.Label {
            textFormat: Text.PlainText
            objectName: "jobStatus"
            Layout.fillWidth: true
            text: card.status
            wrapMode: Text.Wrap
        }

        PC3.Button {
            objectName: "jobStop"
            visible: card.live
            text: i18n("Stop")
            icon.name: "process-stop"
            onClicked: card.stopRequested()
        }
    }
}
