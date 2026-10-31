import QtQuick
import QtQuick.Layouts
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: "Wallpapers"
                        color: Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Wallpapers.busy ? "Applying theme..." : Wallpapers.chooserMissing ? "Install zenity or kdialog to pick a folder" : Wallpapers.count + (Wallpapers.count === 1 ? " image in " : " images in ") + Wallpapers.dirLabel
                        elide: Text.ElideMiddle
                        color: Theme.m3OnSurfaceVariant
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: folderFill.color

                    ColorSpring {
                        id: folderFill

                        target: Wallpapers.choosing ? Theme.m3PrimaryContainer : folderArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf07b"
                        color: Wallpapers.choosing ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                        font.family: Theme.fontIcon
                        font.pixelSize: 14
                    }

                    Ripple {
                        id: ripple1

                        anchors.fill: parent
                        radius: parent.radius
                    }

                    MouseArea {
                        id: folderArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => ripple1.press(folderArea, mouse)
                        onClicked: Wallpapers.choose()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: shuffleFill.color

                    ColorSpring {
                        id: shuffleFill

                        target: shuffleArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf074"
                        color: Theme.m3OnSurfaceVariant
                        font.family: Theme.fontIcon
                        font.pixelSize: 14
                    }

                    Ripple {
                        id: ripple2

                        anchors.fill: parent
                        radius: parent.radius
                    }

                    MouseArea {
                        id: shuffleArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => ripple2.press(shuffleArea, mouse)
                        onClicked: Wallpapers.random()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.m3OutlineVariant
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: grid

                    readonly property int columns: 4

                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: Math.floor(width / columns)
                    cellHeight: Math.round(cellWidth * 0.64)
                    opacity: dim.value
                    model: Wallpapers.folder

                    delegate: Item {
                        id: cell

                        required property string filePath
                        required property url fileUrl
                        readonly property bool selected: Wallpapers.current === filePath
                        property int failedRev: -1
                        readonly property bool useThumb: Wallpapers.thumbsReady && failedRev !== Wallpapers.thumbsRev

                        width: grid.cellWidth
                        height: grid.cellHeight

                        Item {
                            anchors.fill: parent
                            anchors.margins: 5
                            scale: lift.value

                            RoundedImage {
                                anchors.fill: parent
                                radius: 14
                                source: cell.useThumb ? Wallpapers.thumbUrl(cell.filePath) : cell.fileUrl
                                sourceSize: Qt.size(400, 256)
                                onStatusChanged: if (status === Image.Error && cell.useThumb) cell.failedRev = Wallpapers.thumbsRev
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 14
                                color: "transparent"
                                border.width: 3
                                border.color: ring.color

                                ColorSpring {
                                    id: ring

                                    target: cell.selected ? Theme.m3Primary : "transparent"
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                width: 22
                                height: 22
                                radius: 11
                                color: Theme.m3Primary
                                visible: cell.selected

                                Text {
                                    anchors.centerIn: parent
                                    text: "\uf00c"
                                    color: Theme.m3OnPrimary
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 11
                                }
                            }

                            Spring {
                                id: lift

                                target: tileArea.containsMouse ? 1.03 : 1
                                token: Motion.spatialFast
                                epsilon: 0.0005
                            }

                            Ripple {
                                id: ripple3

                                anchors.fill: parent
                                radius: 14
                            }

                            MouseArea {
                                id: tileArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPressed: mouse => ripple3.press(tileArea, mouse)
                                onClicked: Wallpapers.apply(cell.filePath)
                            }
                        }
                    }

                    Spring {
                        id: dim

                        target: Wallpapers.busy ? 0.6 : 1
                        token: Motion.effectsDefault
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: Wallpapers.count === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: "No images in " + Wallpapers.dirLabel
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }
            }
        }
    }
}
