import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: window
    width: 600
    height: 800
    visible: true

    pageStack.initialPage: Kirigami.Page {
        id: rootPage
        title: "Test Page"

        Item {
            id: mockPage
            property string dataDirPath: "/home/home/.local/share/kdeaichat"
            property string schedulesFilePath: dataDirPath + "/schedules.json"
            property var schedulerList: []
            property var schedulerArchivedList: []
            property var schedulerHistory: []
            property bool schedSaving: false

            function translate(text) {
                return text;
            }

            function schedLoadSchedules() {
                console.log("MOCK: schedLoadSchedules called");
                let file = "file://" + schedulesFilePath;
                let doc = new XMLHttpRequest();
                doc.open("GET", file);
                doc.onreadystatechange = function() {
                    if (doc.readyState === XMLHttpRequest.DONE) {
                        try {
                            let parsed = JSON.parse(doc.responseText);
                            let all = parsed.schedules || [];
                            let active = [];
                            let archived = [];
                            for (let i = 0; i < all.length; i++) {
                                if (all[i].archived)
                                    archived.push(all[i]);
                                else
                                    active.push(all[i]);
                            }
                            mockPage.schedulerList = active;
                            mockPage.schedulerArchivedList = archived;
                            mockPage.schedulerHistory = parsed.history || [];
                            console.log("MOCK: loaded", active.length, "active schedules");
                        } catch (e) {
                            console.log("MOCK ERROR parsing:", e);
                        }
                    }
                }
                doc.send();
            }

            function schedSaveAll() {
                console.log("MOCK: schedSaveAll called");
                console.log("Active count:", mockPage.schedulerList.length);
            }
        }

        QQC2.Button {
            text: "Open Dialog"
            anchors.centerIn: parent
            onClicked: dialog.open()
        }

        ScheduleDialog {
            id: dialog
            page: mockPage
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
            width: 500
            height: 700
        }
    }

    Component.onCompleted: {
        dialog.open();
    }
}
