import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: win

    required property var modelData

    readonly property int cells: 11
    readonly property int cellSize: 13
    readonly property int loupeSize: cells * cellSize
    readonly property string frame: "file://" + ColorPicker.frameDir + "/pick-" + ColorPicker.stamp + "-" + modelData.name + ".png"
    readonly property real ratioX: shot.implicitWidth > 0 && width > 0 ? shot.implicitWidth / width : 1
    readonly property real ratioY: shot.implicitHeight > 0 && height > 0 ? shot.implicitHeight / height : 1
    readonly property int px: Math.max(0, Math.min(Math.max(0, shot.implicitWidth - 1), Math.floor(mx * ratioX)))
    readonly property int py: Math.max(0, Math.min(Math.max(0, shot.implicitHeight - 1), Math.floor(my * ratioY)))
    readonly property real loupeX: Math.max(8, Math.min(width - loupe.width - 8, mx + 28 + loupe.width > width - 8 ? mx - 28 - loupe.width : mx + 28))
    readonly property real loupeY: Math.max(8, Math.min(height - loupe.height - 8, my + 28 + loupe.height > height - 8 ? my - 28 - loupe.height : my + 28))

    property real mx: width / 2
    property real my: height / 2
    property bool hot: false
    property bool ready: false
    property bool confirming: false
    property color under: "#000000"

    function confirm(): void {
        if (!ready || confirming)
            return;
        confirming = true;
        swatch.color = under;
        const picked = under;
        swatch.grabToImage(result => {
            const ok = result ? result.saveToFile(ColorPicker.swatchPath) : false;
            ColorPicker.finish(picked, ok);
        }, Qt.size(64, 64));
    }

    function nudge(dx: int, dy: int): void {
        hot = true;
        mx = Math.max(0, Math.min(width, mx + dx / ratioX));
        my = Math.max(0, Math.min(height, my + dy / ratioY));
    }

    screen: modelData
    visible: ColorPicker.picking
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "shoji-colorpick"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: ColorPicker.picking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        if (visible) {
            ready = false;
            confirming = false;
            hot = false;
        }
    }

    Connections {
        target: ColorPicker

        function onPickingChanged() {
            if (ColorPicker.picking)
                probe.loadImage(win.frame);
            else
                probe.unloadImage(win.frame);
        }
    }

    Connections {
        target: win

        function onPxChanged() {
            probe.requestPaint();
        }

        function onPyChanged() {
            probe.requestPaint();
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ColorPicker.cancel()
        Keys.onReturnPressed: win.confirm()
        Keys.onEnterPressed: win.confirm()
        Keys.onLeftPressed: event => win.nudge(event.modifiers & Qt.ShiftModifier ? -10 : -1, 0)
        Keys.onRightPressed: event => win.nudge(event.modifiers & Qt.ShiftModifier ? 10 : 1, 0)
        Keys.onUpPressed: event => win.nudge(0, event.modifiers & Qt.ShiftModifier ? -10 : -1)
        Keys.onDownPressed: event => win.nudge(0, event.modifiers & Qt.ShiftModifier ? 10 : 1)
    }

    Image {
        id: shot

        anchors.fill: parent
        source: ColorPicker.picking ? win.frame : ""
        cache: false
        asynchronous: false
        smooth: false
        fillMode: Image.Stretch
    }

    Canvas {
        id: probe

        z: -1
        width: 1
        height: 1
        renderTarget: Canvas.Image
        onImageLoaded: requestPaint()
        onPaint: {
            if (!win.visible || !isImageLoaded(win.frame))
                return;
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, 1, 1);
            ctx.drawImage(win.frame, win.px, win.py, 1, 1, 0, 0, 1, 1);
            const d = ctx.getImageData(0, 0, 1, 1).data;
            win.under = Qt.rgba(d[0] / 255, d[1] / 255, d[2] / 255, 1);
            win.ready = true;
        }
    }

    Rectangle {
        id: swatch

        x: -200
        y: -200
        width: 64
        height: 64
        color: win.under
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 16
        width: hint.implicitWidth + 28
        height: 30
        radius: 15
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant

        Text {
            id: hint

            anchors.centerIn: parent
            text: "Click or Enter to pick, arrows to nudge, Esc to cancel"
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 12
        }
    }

    Item {
        id: loupe

        x: win.loupeX
        y: win.loupeY
        width: win.loupeSize
        height: win.loupeSize + 40
        visible: win.hot && win.ready

        ShaderEffectSource {
            id: zoom

            sourceItem: shot
            sourceRect: Qt.rect((win.px - Math.floor(win.cells / 2)) / win.ratioX, (win.py - Math.floor(win.cells / 2)) / win.ratioY, win.cells / win.ratioX, win.cells / win.ratioY)
            textureSize: Qt.size(win.cells, win.cells)
            width: win.loupeSize
            height: win.loupeSize
            smooth: false
            visible: false
        }

        Item {
            id: loupeMask

            width: win.loupeSize
            height: win.loupeSize
            visible: false
            layer.enabled: true

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "black"
            }
        }

        MultiEffect {
            width: win.loupeSize
            height: win.loupeSize
            source: zoom
            maskEnabled: true
            maskSource: loupeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: 40
            radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: Theme.m3SurfaceContainer
        }

        Rectangle {
            x: Math.floor(win.cells / 2) * win.cellSize - 1
            y: Math.floor(win.cells / 2) * win.cellSize - 1
            width: win.cellSize + 2
            height: win.cellSize + 2
            color: "transparent"
            border.width: 2
            border.color: "#ffffff"

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                color: "transparent"
                border.width: 1
                border.color: "#000000"
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: label.implicitWidth + 44
            height: 32
            radius: 16
            color: Theme.m3SurfaceContainer
            border.width: 1
            border.color: Theme.m3OutlineVariant

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: win.under
                border.width: 1
                border.color: Theme.m3OutlineVariant
            }

            Text {
                id: label

                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "#" + ColorPicker.pad(Math.round(win.under.r * 255)) + ColorPicker.pad(Math.round(win.under.g * 255)) + ColorPicker.pad(Math.round(win.under.b * 255))
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor
        onEntered: win.hot = true
        onExited: win.hot = false
        onPositionChanged: mouse => {
            win.hot = true;
            win.mx = mouse.x;
            win.my = mouse.y;
        }
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton)
                ColorPicker.cancel();
            else
                win.confirm();
        }
    }
}
