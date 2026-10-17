import QtQuick
import qs.Commons

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string trailing: ""
    property bool active: false

    signal clicked

    implicitHeight: 40
    radius: 14
    color: fill.color

    ColorSpring {
        id: fill

        target: root.active ? Theme.m3PrimaryContainer : area.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
    }

    Text {
        id: lead

        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        horizontalAlignment: Text.AlignHCenter
        text: root.icon
        color: root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
        font.family: Theme.fontIcon
        font.pixelSize: 14
    }

    Text {
        anchors.left: lead.right
        anchors.leftMargin: 10
        anchors.right: tail.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        elide: Text.ElideRight
        color: root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurface
        font.family: Theme.fontUi
        font.pixelSize: 13
    }

    Text {
        id: tail

        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.trailing
        color: root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
        font.family: Theme.fontIcon
        font.pixelSize: 12
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
