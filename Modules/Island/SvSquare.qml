import QtQuick
import qs.Commons

Item {
    id: root

    property real hue: 0
    property real sat: 0
    property real val: 1
    property color tint: "white"

    signal moved(real s, real v)

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Qt.hsva(root.hue, 1, 1, 1)
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: "#ffffffff"
            }

            GradientStop {
                position: 1
                color: "#00ffffff"
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "#00000000"
            }

            GradientStop {
                position: 1
                color: "#ff000000"
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: "transparent"
        border.width: 1
        border.color: Theme.m3OutlineVariant
    }

    Rectangle {
        x: root.sat * root.width - width / 2
        y: (1 - root.val) * root.height - height / 2
        width: 22
        height: 22
        radius: 11
        color: root.tint
        border.width: 3
        border.color: "#ffffff"

        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: "#66000000"
        }
    }

    MouseArea {
        anchors.fill: parent
        preventStealing: true
        cursorShape: Qt.CrossCursor
        onPressed: mouse => root.moved(Motion.clamp01(mouse.x / width), 1 - Motion.clamp01(mouse.y / height))
        onPositionChanged: mouse => {
            if (pressed)
                root.moved(Motion.clamp01(mouse.x / width), 1 - Motion.clamp01(mouse.y / height));
        }
    }
}
