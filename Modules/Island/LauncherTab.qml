import QtQuick
import Quickshell
import qs.Commons

Item {
    id: root

    Keys.onEscapePressed: ShellState.expanded = false

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: "transparent"
        border.width: 1
        border.color: Theme.m3OutlineVariant

        GridView {
            id: grid

            readonly property int columns: 6

            anchors.fill: parent
            anchors.margins: 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: Math.floor(width / columns)
            cellHeight: 92
            model: ScriptModel {
                values: Apps.all
            }

            delegate: Item {
                id: tile

                required property var modelData

                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 16
                    color: tileFill.color

                    ColorSpring {
                        id: tileFill

                        target: area.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6

                        AppIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            icon: tile.modelData.icon
                            size: 40
                        }

                        Text {
                            width: tile.width - 20
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.name
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: Theme.m3OnSurface
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            tile.modelData.execute();
                            ShellState.expanded = false;
                        }
                    }
                }
            }
        }
    }
}
