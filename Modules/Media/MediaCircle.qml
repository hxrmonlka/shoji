import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

Item {
    id: root

    required property real progress
    required property real restX
    required property real openX
    required property real size
    required property real panelWidth
    required property real panelHeight
    property real hiddenBy: 0

    readonly property real radiusNow: Motion.lerp(size / 2, 32, progress)

    signal clicked

    x: Motion.lerp(restX, openX, progress)
    width: Motion.lerp(size, panelWidth, progress)
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

        MediaPanel {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: root.panelWidth
            height: root.panelHeight
            opacity: Motion.clamp01((root.progress - 0.4) / 0.4)
            visible: opacity > 0
        }
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

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Theme.m3OutlineVariant
                strokeWidth: 3
                fillColor: "transparent"

                PathAngleArc {
                    centerX: face.width / 2
                    centerY: face.height / 2
                    radiusX: face.width / 2 - 3
                    radiusY: face.height / 2 - 3
                    startAngle: -90
                    sweepAngle: 359.9
                }
            }

            ShapePath {
                strokeColor: Theme.m3Primary
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"

                PathAngleArc {
                    centerX: face.width / 2
                    centerY: face.height / 2
                    radiusX: face.width / 2 - 3
                    radiusY: face.height / 2 - 3
                    startAngle: -90
                    sweepAngle: 359.9 * ring.value
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: "\uf001"
            color: Media.playing ? Theme.m3Primary : Theme.m3OnSurfaceVariant
            font.family: Theme.fontIcon
            font.pixelSize: 16
        }

        Spring {
            id: ring

            target: Media.progress
            token: Motion.effectsSlow
            epsilon: 0.0005
        }
    }

    MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        width: root.size
        height: root.size
        enabled: root.progress < 0.05
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
