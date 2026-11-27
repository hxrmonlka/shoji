import QtQuick
import qs.Commons

Rectangle {
    id: root

    property string icon: ""
    property bool active: false
    property int iconSize: 15
    property real iconRotation: 0
    property bool squash: false
    property bool plain: false
    property bool hoverBackground: true
    readonly property bool pressed: area.pressed

    signal clicked

    implicitWidth: 36
    implicitHeight: 36
    radius: height / 2
    color: fill.color
    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: root.squash ? squasher.xScale : 1
        yScale: root.squash ? squasher.yScale : 1
    }

    Squash {
        id: squasher

        pressed: root.squash && area.pressed
    }

    ColorSpring {
        id: fill

        target: root.active && !root.plain ? Theme.m3PrimaryContainer : root.hoverBackground && area.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
    }

    ColorSpring {
        id: glyph

        target: root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
    }

    Ripple {
        id: ripple

        anchors.fill: parent
        radius: root.radius
    }

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: root.plain ? glyph.color : root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
        font.family: Theme.fontIcon
        font.pixelSize: root.iconSize
        rotation: root.iconRotation
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => ripple.press(area, mouse)
        onClicked: root.clicked()
    }
}
