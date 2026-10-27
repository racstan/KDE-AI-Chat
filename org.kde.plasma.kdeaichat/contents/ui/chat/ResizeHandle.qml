// The grip in a corner of the popup that resizes it.
//
// The mouse is measured in screen coordinates, so the handle moving with the
// popup's edge doesn't feed back into the size (problem 5). While dragging,
// the size goes to chat.livePopupWidth/Height (the popup follows it at
// once); the saved size in config is written once, on release.
//
// Place it in the corner away from the panel: growsLeft puts the grip on the
// left edge (dragging left widens), growsUp on the top edge (dragging up
// makes it taller).
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

MouseArea {
    id: handle

    // Has popupPreferredWidth/Height (the current size) and
    // livePopupWidth/Height (0 when not dragging).
    property var chat: null
    // Has customPopupWidth/Height (the saved size).
    property var config: null
    property bool growsLeft: false
    property bool growsUp: false
    property int minimumWidth: 500
    property int minimumHeight: 620
    property int maximumWidth: Screen.width > 0 ? Screen.width : 4096
    property int maximumHeight: Screen.height > 0 ? Screen.height : 4096

    // The room the grip takes in each corner of the popup (0 where it isn't):
    // whatever sits in that corner (the header's last button, the composer's
    // Send) keeps this much free, so the grip never covers a button.
    readonly property real roomTopLeft: growsUp && growsLeft ? width : 0
    readonly property real roomTopRight: growsUp && !growsLeft ? width : 0
    readonly property real roomBottomLeft: !growsUp && growsLeft ? width : 0
    readonly property real roomBottomRight: !growsUp && !growsLeft ? width : 0

    property point pressPoint: Qt.point(0, 0)
    property int startWidth: 0
    property int startHeight: 0

    // Which way a popup grows along one axis: Plasma keeps the edge nearest
    // the screen edge in place, so it grows away from it. True when the high
    // side (right, bottom) is the one nearer its screen edge, so the popup
    // grows towards the low side (left, up). The grip belongs there; on the
    // other corner, dragging does nothing as the popup cannot grow that way.
    function growsTowardsLow(low, high, screenLow, screenHigh) {
        return (screenHigh - high) < (low - screenLow);
    }

    function clamp(value, low, high) {
        return Math.round(Math.max(low, Math.min(Math.max(low, high), value)));
    }

    function commit() {
        if (!handle.chat)
            return;
        var w = handle.chat.livePopupWidth;
        var h = handle.chat.livePopupHeight;
        if (w > 0 && h > 0 && handle.config) {
            if (handle.config.customPopupWidth !== w)
                handle.config.customPopupWidth = w;
            if (handle.config.customPopupHeight !== h)
                handle.config.customPopupHeight = h;
        }
        handle.chat.livePopupWidth = 0;
        handle.chat.livePopupHeight = 0;
    }

    width: Kirigami.Units.gridUnit
    height: Kirigami.Units.gridUnit
    // In the corner of its parent away from the panel. (Not anchors: switching
    // anchors when the panel moves to another edge can leave it stretched.)
    x: growsLeft || !parent ? 0 : parent.width - width
    y: growsUp || !parent ? 0 : parent.height - height
    cursorShape: handle.growsLeft === handle.growsUp ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
    preventStealing: true

    onPressed: function(mouse) {
        if (!handle.chat)
            return;
        handle.pressPoint = handle.mapToGlobal(mouse.x, mouse.y);
        handle.startWidth = handle.chat.popupPreferredWidth;
        handle.startHeight = handle.chat.popupPreferredHeight;
    }
    onPositionChanged: function(mouse) {
        if (!handle.pressed || !handle.chat)
            return;
        var p = handle.mapToGlobal(mouse.x, mouse.y);
        var dx = (p.x - handle.pressPoint.x) * (handle.growsLeft ? -1 : 1);
        var dy = (p.y - handle.pressPoint.y) * (handle.growsUp ? -1 : 1);
        handle.chat.livePopupWidth = handle.clamp(handle.startWidth + dx, handle.minimumWidth, handle.maximumWidth);
        handle.chat.livePopupHeight = handle.clamp(handle.startHeight + dy, handle.minimumHeight, handle.maximumHeight);
    }
    onReleased: handle.commit()
    onCanceled: handle.commit()

    Canvas {
        id: grip

        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        transform: Scale {
            origin.x: grip.width / 2
            origin.y: grip.height / 2
            xScale: handle.growsLeft ? -1 : 1
            yScale: handle.growsUp ? -1 : 1
        }
        property color strokeColor: Kirigami.Theme.textColor
        onStrokeColorChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = grip.strokeColor;
            ctx.lineWidth = 1;
            ctx.globalAlpha = 0.5;
            ctx.beginPath();
            for (var d = 4; d <= 12; d += 4) {
                ctx.moveTo(width - d, height);
                ctx.lineTo(width, height - d);
            }
            ctx.stroke();
        }
    }
}
