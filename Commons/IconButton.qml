import QtQuick
import qs.Commons

Rectangle {
    id: root

    property string icon: ""
    property bool active: false
    property int iconSize: 15

    signal clicked

    implicitWidth: 36
    implicitHeight: 36
    radius: height / 2
    color: fill.color

    ColorSpring {
        id: fill

        target: root.active ? Theme.m3PrimaryContainer : area.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
    }

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
        font.family: Theme.fontIcon
        font.pixelSize: root.iconSize
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
