import QtQuick
import Quickshell
import qs.Commons

Item {
    id: root

    property string icon: ""
    property int size: 32
    property string fallback: "\uf2d0"

    implicitWidth: size
    implicitHeight: size

    Image {
        id: img

        anchors.fill: parent
        source: root.icon ? Apps.iconSource(root.icon) : ""
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        visible: status === Image.Ready
    }

    Text {
        anchors.centerIn: parent
        visible: !img.visible
        text: root.fallback
        color: Theme.m3OnSurfaceVariant
        font.family: Theme.fontIcon
        font.pixelSize: root.size * 0.6
    }
}
