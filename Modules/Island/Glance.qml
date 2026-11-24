import QtQuick
import Quickshell.Bluetooth
import qs.Commons

Item {
    id: root

    required property var screen

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter !== null && btAdapter.enabled
    readonly property bool wifiOn: Network.wifiEnabled
    readonly property string volumeIcon: Audio.muted || Audio.volume <= 0.001 ? "\uf026" : Audio.volume > 0.5 ? "\uf028" : "\uf027"

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            text: Qt.formatDateTime(ShellState.clock.date, "HH:mm")
            color: Theme.m3OnSurface
            font.family: Theme.fontClock
            font.pixelSize: 56
            font.weight: Font.Black
            font.variableAxes: ({ "wght": 900, "ROND": 100 })
        }

        Text {
            width: 180
            text: Qt.formatDateTime(ShellState.clock.date, "dddd, MMMM d")
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 13
            elide: Text.ElideRight
        }
    }

    Column {
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        width: 216
        spacing: 12

        Row {
            width: parent.width
            spacing: 10

            Item {
                width: 52
                height: 52

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: Theme.m3SurfaceContainerHigh
                    visible: art.status !== Image.Ready

                    Text {
                        anchors.centerIn: parent
                        text: "\uf001"
                        color: Theme.m3OnSurfaceVariant
                        font.family: Theme.fontIcon
                        font.pixelSize: 20
                    }
                }

                RoundedImage {
                    id: art

                    anchors.fill: parent
                    radius: 14
                    source: Media.artUrl
                    sourceSize: Qt.size(104, 104)
                    visible: status === Image.Ready
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 62
                spacing: 2

                Text {
                    width: parent.width
                    text: Media.available ? Media.title : "Nothing playing"
                    color: Theme.m3OnSurface
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: Media.artist
                    visible: text !== ""
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            width: parent.width
            height: 22

            Row {
                id: icons

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf1eb"
                    color: root.wifiOn ? Theme.m3OnSurface : Theme.m3Outline
                    opacity: root.wifiOn ? 1 : 0.55
                    font.family: Theme.fontIcon
                    font.pixelSize: 15

                    Behavior on color {
                        ColorAnimation {
                            duration: 160
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf293"
                    color: root.btOn ? Theme.m3OnSurface : Theme.m3Outline
                    opacity: root.btOn ? 1 : 0.55
                    font.family: Theme.fontIcon
                    font.pixelSize: 15

                    Behavior on color {
                        ColorAnimation {
                            duration: 160
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.volumeIcon
                    color: Theme.m3OnSurface
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                }

                GlanceBell {
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Workspaces {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Math.max(0, parent.width - icons.width - 10))
                clip: true
                visible: Settings.showWorkspaces
                screen: root.screen
            }
        }
    }
}
