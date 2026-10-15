import QtQuick
import qs.Commons

Item {
    id: root

    required property var tabs
    required property string current

    signal picked(string tabId)

    implicitHeight: 44

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
            model: root.tabs

            Rectangle {
                id: chip

                required property var modelData
                readonly property bool active: modelData.id === root.current

                width: chipRow.implicitWidth + 28
                height: 32
                radius: 16
                color: chipFill.color

                ColorSpring {
                    id: chipFill

                    target: chip.active ? Theme.m3PrimaryContainer : chipArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
                }

                Row {
                    id: chipRow

                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.icon
                        color: chip.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                        font.family: Theme.fontIcon
                        font.pixelSize: 14
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.label
                        color: chip.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: chipArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(chip.modelData.id)
                }
            }
        }
    }
}
