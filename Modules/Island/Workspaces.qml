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
            width: modelData.active ? 22 : 8
            height: 8
            radius: 4
            color: modelData.active ? Theme.primary : modelData.urgent ? Theme.onPrimaryContainer : Theme.surfaceContainerHighest

            Behavior on width {
                NumberAnimation {
                    duration: Motion.medium2
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.emphasized
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Motion.short4
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.standard
                }
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
