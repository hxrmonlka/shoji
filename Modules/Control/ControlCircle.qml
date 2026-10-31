import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
    id: root

    required property real progress
    required property real restX
    required property real openX
    required property real size
    required property real panelWidth
    property real detailWidth: 0
    required property real panelHeight
    required property real panelRadius
    property real hiddenBy: 0

    readonly property real extraWidth: Math.max(0, detailSpring.value)
    readonly property real fullWidth: panelWidth + extraWidth
    readonly property real radiusNow: Motion.lerp(size / 2, panelRadius, progress)
    readonly property var icons: ["\uf1eb", "\uf028", "\uf06e", "\uf293", "\uf023", "\uf186", "\uf185", "\uf0f3"]
    readonly property int count: icons.length
    property int index: 0

    signal clicked

    x: Motion.lerp(restX, openX - extraWidth / 2, progress)
    width: Motion.lerp(size, fullWidth, progress)
    height: Motion.lerp(size, panelHeight, progress)
    opacity: 1 - Motion.clamp01(hiddenBy)
    visible: opacity > 0

    Rectangle {
        anchors.fill: parent
        radius: root.radiusNow
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant
    }

    Item {
        id: clipped

        anchors.fill: parent
        layer.enabled: root.progress > 0.01
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskItem
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        ControlPanel {
            id: panel

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: root.fullWidth
            height: root.panelHeight
            opacity: Motion.clamp01((root.progress - 0.4) / 0.4)
            visible: opacity > 0
        }
    }

    Spring {
        id: detailSpring

        target: panel.detail !== "" ? root.detailWidth : 0
        token: Motion.spatialDefault
        epsilon: 0.05
    }

    Item {
        id: maskItem

        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.radiusNow
            color: "black"
        }
    }

    Item {
        id: face

        anchors.left: parent.left
        anchors.top: parent.top
        width: root.size
        height: root.size
        opacity: 1 - Motion.clamp01(root.progress / 0.25)
        visible: opacity > 0
        clip: true

        Column {
            y: -scroll.value * face.height

            Repeater {
                model: root.count + 1

                Item {
                    required property int index

                    width: face.width
                    height: face.height

                    Text {
                        anchors.centerIn: parent
                        text: root.icons[parent.index % root.count]
                        color: Theme.m3Primary
                        font.family: Theme.fontIcon
                        font.pixelSize: Math.round(root.size * 0.36)
                    }
                }
            }
        }

        Spring {
            id: scroll

            token: Motion.spatialDefault
            epsilon: 0.0005
            onRunningChanged: {
                if (!running && root.index === root.count) {
                    root.index = 0;
                    value = 0;
                    target = 0;
                }
            }
        }

        Timer {
            interval: 2200
            repeat: true
            running: face.visible && root.progress < 0.01
            onTriggered: {
                root.index = Math.min(root.index + 1, root.count);
                scroll.target = root.index;
            }
        }
    }

    Ripple {
        id: circleRipple

        anchors.left: parent.left
        anchors.top: parent.top
        width: root.size
        height: root.size
        radius: root.size / 2
        visible: root.progress < 0.05 && Settings.ripple
    }

    MouseArea {
        id: circleArea

        anchors.left: parent.left
        anchors.top: parent.top
        width: root.size
        height: root.size
        enabled: root.progress < 0.05
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => circleRipple.press(circleArea, mouse)
        onClicked: root.clicked()
    }
}
