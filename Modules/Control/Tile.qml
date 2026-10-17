import QtQuick
import qs.Commons

Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool expandable: false
    property bool expanded: false

    signal toggled
    signal expandRequested

    implicitHeight: 64
    radius: 20
    color: fill.color
    opacity: enabled ? 1 : 0.5

    ColorSpring {
        id: fill

        target: root.active ? Theme.m3PrimaryContainer : area.containsMouse ? Theme.m3SurfaceContainerHighest : Theme.m3SurfaceContainerHigh
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: chevron.visible ? chevron.left : parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurface
            font.family: Theme.fontIcon
            font.pixelSize: 18
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32
            spacing: 1

            Text {
                width: parent.width
                text: root.title
                elide: Text.ElideRight
                color: root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                text: root.subtitle
                visible: text.length > 0
                elide: Text.ElideRight
                color: root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                opacity: 0.8
                font.family: Theme.fontUi
                font.pixelSize: 11
            }
        }
    }

    MouseArea {
        id: area

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: chevron.visible ? chevron.left : parent.right
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    Item {
        id: chevron

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 40
        visible: root.expandable

        Text {
            anchors.centerIn: parent
            text: "\uf054"
            rotation: root.expanded ? 90 : 0
            color: root.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
            font.family: Theme.fontIcon
            font.pixelSize: 12

            Behavior on rotation {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expandRequested()
        }
    }
}
