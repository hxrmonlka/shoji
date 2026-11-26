import QtQuick
import qs.Commons

Item {
    id: root

    property int number: 0
    property string title: ""

    height: 34

    Text {
        id: num

        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 7
        visible: root.number > 0
        text: (root.number < 10 ? "0" : "") + root.number
        color: Theme.m3Primary
        font.family: Theme.fontUi
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 1
    }

    Text {
        id: label

        anchors.left: num.visible ? num.right : parent.left
        anchors.leftMargin: num.visible ? 10 : 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        text: root.title
        color: Theme.m3OnSurface
        font.family: Theme.fontUi
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    Rectangle {
        anchors.left: label.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: label.verticalCenter
        height: 1
        color: Theme.m3OutlineVariant
    }
}
