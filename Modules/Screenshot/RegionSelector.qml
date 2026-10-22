import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: win

    required property var modelData

    property bool dragging: false
    property real startX: 0
    property real startY: 0
    property real curX: 0
    property real curY: 0

    readonly property real selX: Math.min(startX, curX)
    readonly property real selY: Math.min(startY, curY)
    readonly property real selW: Math.abs(curX - startX)
    readonly property real selH: Math.abs(curY - startY)
    readonly property color dim: Qt.rgba(0, 0, 0, 0.45)

    screen: modelData
    visible: Screenshot.selecting
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "shoji-screenshot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Screenshot.selecting ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        if (!visible)
            dragging = false;
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Screenshot.cancel()
    }

    Rectangle {
        anchors.fill: parent
        color: win.dim
        visible: !win.dragging
    }

    Item {
        anchors.fill: parent
        visible: win.dragging

        Rectangle {
            x: 0
            y: 0
            width: parent.width
            height: win.selY
            color: win.dim
        }

        Rectangle {
            x: 0
            y: win.selY + win.selH
            width: parent.width
            height: parent.height - (win.selY + win.selH)
            color: win.dim
        }

        Rectangle {
            x: 0
            y: win.selY
            width: win.selX
            height: win.selH
            color: win.dim
        }

        Rectangle {
            x: win.selX + win.selW
            y: win.selY
            width: parent.width - (win.selX + win.selW)
            height: win.selH
            color: win.dim
        }

        Rectangle {
            x: win.selX
            y: win.selY
            width: win.selW
            height: win.selH
            color: "transparent"
            border.width: 2
            border.color: Theme.m3Primary
        }

        Rectangle {
            x: Math.min(win.selX, win.width - width - 8)
            y: win.selY + win.selH + 8 + height > win.height ? Math.max(8, win.selY - height - 8) : win.selY + win.selH + 8
            width: sizeText.implicitWidth + 20
            height: 28
            radius: 14
            color: Theme.m3SurfaceContainer
            border.width: 1
            border.color: Theme.m3OutlineVariant

            Text {
                id: sizeText

                anchors.centerIn: parent
                text: Math.round(win.selW) + " x " + Math.round(win.selH)
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                Screenshot.cancel();
                return;
            }
            win.startX = mouse.x;
            win.startY = mouse.y;
            win.curX = mouse.x;
            win.curY = mouse.y;
            win.dragging = true;
        }
        onPositionChanged: mouse => {
            if (!win.dragging)
                return;
            win.curX = Math.max(0, Math.min(width, mouse.x));
            win.curY = Math.max(0, Math.min(height, mouse.y));
        }
        onReleased: mouse => {
            if (!win.dragging)
                return;
            win.dragging = false;
            if (win.selW < 4 || win.selH < 4) {
                Screenshot.cancel();
                return;
            }
            Screenshot.finishRegion(Math.round(win.screen.x + win.selX), Math.round(win.screen.y + win.selY), Math.round(win.selW), Math.round(win.selH));
        }
    }
}
