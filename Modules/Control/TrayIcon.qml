import QtQuick
import qs.Commons

Rectangle {
    id: root

    required property var item
    property bool active: false

    signal menuRequested

    implicitWidth: 40
    implicitHeight: 40
    radius: 14
    color: fill.color

    ColorSpring {
        id: fill

        target: root.active ? Theme.m3PrimaryContainer : area.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
    }

    Image {
        anchors.centerIn: parent
        width: 22
        height: 22
        source: root.item.icon
        sourceSize: Qt.size(44, 44)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                if (root.item.hasMenu)
                    root.menuRequested();
                else
                    root.item.secondaryActivate();
            } else if (mouse.button === Qt.MiddleButton) {
                root.item.secondaryActivate();
            } else if (root.item.onlyMenu && root.item.hasMenu) {
                root.menuRequested();
            } else {
                root.item.activate();
            }
        }
    }
}
