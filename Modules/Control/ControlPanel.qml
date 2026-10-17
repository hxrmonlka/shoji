import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.Commons

Item {
    id: root

    property string detail: ""
    property bool appsOpen: false

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btPaired: Bluetooth.devices.values.filter(d => d.paired)
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)

    function toggleDetail(name) {
        detail = detail === name ? "" : name;
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col

            x: 20
            y: 20
            width: flick.width - 40
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                IconButton {
                    icon: Audio.icon()
                    active: !Audio.muted && Audio.ready
                    onClicked: Audio.toggleMute()
                }

                ValueSlider {
                    Layout.fillWidth: true
                    value: Audio.volume
                    enabled: Audio.ready
                    onMoved: v => Audio.setVolume(v)
                }

                IconButton {
                    icon: "\uf078"
                    iconSize: 11
                    active: root.appsOpen
                    onClicked: root.appsOpen = !root.appsOpen
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.appsOpen

                Text {
                    Layout.fillWidth: true
                    visible: Audio.streams.length === 0
                    text: "No apps playing audio"
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                }

                Repeater {
                    model: root.appsOpen ? Audio.streams : []

                    RowLayout {
                        id: appRow

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.preferredWidth: 96
                            text: Audio.streamName(appRow.modelData)
                            elide: Text.ElideRight
                            color: Theme.m3OnSurfaceVariant
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                        }

                        ValueSlider {
                            Layout.fillWidth: true
                            value: appRow.modelData.audio.volume
                            onMoved: v => Audio.setStreamVolume(appRow.modelData, v)
                        }

                        IconButton {
                            implicitWidth: 28
                            implicitHeight: 28
                            iconSize: 12
                            icon: appRow.modelData.audio.muted ? "\uf026" : "\uf028"
                            active: !appRow.modelData.audio.muted
                            onClicked: Audio.toggleStreamMute(appRow.modelData)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: Brightness.available

                Text {
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignHCenter
                    text: "\uf185"
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontIcon
                    font.pixelSize: 16
                }

                ValueSlider {
                    Layout.fillWidth: true
                    value: Brightness.value
                    onMoved: v => Brightness.set(v)
                }

                Item {
                    Layout.preferredWidth: 36
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 10
                uniformCellWidths: true

                Tile {
                    Layout.fillWidth: true
                    icon: "\uf1eb"
                    title: "Wi-Fi"
                    subtitle: !Network.wifiEnabled ? "Off" : Network.ssid || "Not connected"
                    active: Network.wifiEnabled
                    expandable: Network.wifiEnabled
                    expanded: root.detail === "wifi"
                    onToggled: Network.setWifi(!Network.wifiEnabled)
                    onExpandRequested: root.toggleDetail("wifi")
                }

                Tile {
                    Layout.fillWidth: true
                    icon: "\uf293"
                    title: "Bluetooth"
                    subtitle: !root.btAdapter ? "Unavailable" : !root.btAdapter.enabled ? "Off" : root.btConnected.length > 0 ? root.btConnected.map(d => d.name).join(", ") : "On"
                    active: root.btAdapter !== null && root.btAdapter.enabled
                    enabled: root.btAdapter !== null
                    expandable: active
                    expanded: root.detail === "bt"
                    onToggled: root.btAdapter.enabled = !root.btAdapter.enabled
                    onExpandRequested: root.toggleDetail("bt")
                }

                Tile {
                    Layout.fillWidth: true
                    icon: "\uf023"
                    title: "VPN"
                    subtitle: Network.vpns.length === 0 ? "No profiles" : Network.vpnActive ? Network.activeVpns.map(v => v.name).join(", ") : "Off"
                    active: Network.vpnActive
                    enabled: Network.vpns.length > 0
                    expandable: Network.vpns.length > 0
                    expanded: root.detail === "vpn"
                    onToggled: {
                        if (Network.vpnActive)
                            Network.activeVpns.forEach(v => Network.setVpn(v.name, false));
                        else
                            Network.setVpn(Network.vpns[0].name, true);
                    }
                    onExpandRequested: root.toggleDetail("vpn")
                }

                Tile {
                    Layout.fillWidth: true
                    icon: "\uf06e"
                    title: "Focus"
                    subtitle: Display.focusAvailable ? "Grayscale" : "No backend set"
                    active: Display.focus
                    enabled: Display.focusAvailable
                    onToggled: Display.setFocus(!Display.focus)
                }

                Tile {
                    Layout.fillWidth: true
                    icon: "\uf186"
                    title: "Night mode"
                    subtitle: Settings.nightTemperature + "K"
                    active: Display.night
                    onToggled: Display.setNight(!Display.night)
                }

                Tile {
                    Layout.fillWidth: true
                    icon: "\uf084"
                    title: "Lock"
                    subtitle: "Lock screen"
                    onToggled: Display.lock()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: root.detail === "wifi"

                Repeater {
                    model: root.detail === "wifi" ? Network.networks.slice(0, 8) : []

                    ListRow {
                        required property var modelData

                        Layout.fillWidth: true
                        icon: "\uf1eb"
                        label: modelData.ssid
                        trailing: modelData.active ? "\uf00c" : modelData.secure ? "\uf023" : ""
                        active: modelData.active
                        onClicked: Network.connect(modelData.ssid)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: root.detail === "bt"

                Text {
                    Layout.fillWidth: true
                    visible: root.btPaired.length === 0
                    text: "No paired devices"
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                }

                Repeater {
                    model: root.detail === "bt" ? root.btPaired : []

                    ListRow {
                        required property var modelData

                        Layout.fillWidth: true
                        icon: "\uf293"
                        label: modelData.name
                        trailing: modelData.connected ? "\uf00c" : ""
                        active: modelData.connected
                        onClicked: modelData.connected = !modelData.connected
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: root.detail === "vpn"

                Repeater {
                    model: root.detail === "vpn" ? Network.vpns : []

                    ListRow {
                        required property var modelData

                        Layout.fillWidth: true
                        icon: "\uf023"
                        label: modelData.name
                        trailing: modelData.active ? "\uf00c" : ""
                        active: modelData.active
                        onClicked: Network.setVpn(modelData.name, !modelData.active)
                    }
                }
            }
        }
    }
}
