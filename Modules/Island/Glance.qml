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
            font.variableAxes: ({
                    "wght": 900,
                    "ROND": 100
                })
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
        width: 232
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

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: miniViz.visible ? parent.width - miniViz.width - parent.spacing : parent.width
                        text: Media.available ? Media.title : "Nothing playing"
                        color: Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Item {
                        id: miniViz

                        readonly property bool wanted: Settings.visualizer && Media.anyPlaying
                        readonly property int barCount: PillCava.bars
                        readonly property real fullWidth: barCount * 3 + (barCount - 1) * 2

                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, vizPresence.value) * fullWidth
                        height: 16
                        visible: vizPresence.value > 0.001
                        opacity: Motion.clamp01(vizPresence.value)
                        clip: true

                        Spring {
                            id: vizPresence

                            target: miniViz.wanted ? 1 : 0
                            token: Motion.effectsSlow
                            epsilon: 0.002
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 2

                            Repeater {
                                model: miniViz.barCount

                                Item {
                                    required property int index

                                    width: 3
                                    height: 16

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 3
                                        height: 3 + Math.max(0, Math.min(1, PillCava.values[parent.index] ?? 0)) * 13
                                        radius: 1.5
                                        color: Theme.m3Primary
                                    }
                                }
                            }
                        }
                    }
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
                spacing: 12

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

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Power.laptopModeEnabled && Power.batteryAvailable
                    text: Power.batteryIcon
                    color: Power.batteryLow ? Theme.m3Error : Power.batteryCharging ? Theme.m3Primary : Theme.m3OnSurface
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                }
            }

            Workspaces {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Math.max(0, parent.width - icons.width - 10))
                visible: Settings.showWorkspaces
                screen: root.screen
            }
        }
    }
}
