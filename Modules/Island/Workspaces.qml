import QtQuick
import Quickshell
import Quickshell.WindowManager
import qs.Commons

Row {
    id: root

    required property var screen

    spacing: 6

    Repeater {
        model: WindowManager.screenProjection(root.screen).windowsets

        Rectangle {
            id: dot

            required property var modelData

            visible: modelData.shouldDisplay
            width: grow.value
            height: 8
            radius: 4
            color: tint.color

            Spring {
                id: grow

                target: dot.modelData.active ? 22 : 8
                token: Motion.spatialFast
                epsilon: 0.02
            }

            ColorSpring {
                id: tint

                target: dot.modelData.active ? Theme.m3Primary : dot.modelData.urgent ? Theme.m3OnPrimaryContainer : Theme.m3SurfaceContainerHighest
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: dot.modelData.activate()
            }
        }
    }
}
