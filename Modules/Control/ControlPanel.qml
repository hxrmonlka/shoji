import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import qs.Commons

Item {
    id: root

    property string detail: ""
    property bool tabHost: false
    property bool appsOpen: false
    property real appsProgress: 0
    property string trayId: ""
    property var trayAnchor: null

    readonly property var trayItems: SystemTray.items.values
    readonly property var trayItem: trayItems.find(i => i.id === trayId) ?? null

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btPaired: Bluetooth.devices.values.filter(d => d.paired)
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)

    function reset() {
        trayId = "";
        detail = "";
    }

    onDetailChanged: {
        if (tabHost)
            ShellState.controlDetail = detail !== "";
    }

    onAppsOpenChanged: {
        appsAnim.stop();
        appsAnim.to = appsOpen ? 1 : 0;
        appsAnim.duration = appsOpen ? 300 : 130;
        appsAnim.easing.bezierCurve = appsOpen ? [0.16, 1, 0.3, 1, 1, 1] : [0.7, 0, 0.84, 0, 1, 1];
        appsAnim.start();
    }

    NumberAnimation {
        id: appsAnim

        target: root
        property: "appsProgress"
        easing.type: Easing.BezierSpline
    }

    function toggleDetail(name) {
        detail = detail === name ? "" : name;
    }

    function toggleTray(id, anchorItem) {
        if (trayId === id) {
            trayId = "";
            return;
        }
        trayAnchor = anchorItem;
        trayId = id;
    }

    Connections {
        target: ShellState

        function onControlChanged(): void {
            if (!ShellState.control && !root.tabHost) {
                root.trayId = "";
                root.detail = "";
            }
        }

        function onExpandedChanged(): void {
            if (root.tabHost && !ShellState.expanded)
                root.reset();
        }

        function onTabChanged(): void {
            if (root.tabHost && ShellState.tab !== "control")
                root.reset();
        }
    }

    Connections {
        target: Power

        function onLaptopModeEnabledChanged(): void {
            if (!Power.laptopModeEnabled && root.detail === "power")
                root.detail = "";
        }
    }

    readonly property bool menuWanted: trayItem !== null && trayItem.hasMenu && trayAnchor !== null
    property bool menuShown: false

    onMenuWantedChanged: {
        ShellState.hold(menuWanted);
        if (menuWanted) {
            showTimer.restart();
        } else {
            showTimer.stop();
            menuShown = false;
        }
    }

    Component.onDestruction: if (root.menuWanted)
        ShellState.hold(false)

    Timer {
        id: showTimer

        interval: 80
        onTriggered: root.menuShown = true
    }

    TrayCatcher {
        active: root.menuWanted
        onDismissed: root.trayId = ""
    }

    TrayContextMenu {
        target: root.trayAnchor
        visible: root.menuShown
        handle: root.trayItem ? root.trayItem.menu : null
        title: root.trayItem ? (root.trayItem.tooltipTitle || root.trayItem.title) : ""
        onDone: root.trayId = ""
    }

    readonly property real sideWidth: Settings.controlSideWidth
    readonly property real mainWidth: Settings.controlPanelWidth
    readonly property real detailWidth: Math.max(0, width - sideWidth - mainWidth)
    readonly property real detailProgress: Math.min(1, detailWidth / Math.max(1, sideWidth))

    NotificationsColumn {
        x: 0
        y: 0
        width: root.sideWidth
        height: root.height
    }

    Rectangle {
        x: root.sideWidth
        y: 16
        width: 1
        height: root.height - 32
        color: Theme.m3OutlineVariant
    }

    Rectangle {
        x: root.sideWidth + root.mainWidth
        y: 16
        width: 1
        height: root.height - 32
        color: Theme.m3OutlineVariant
        opacity: Motion.clamp01(root.detailProgress * 3)
    }

    DetailColumn {
        x: root.sideWidth + root.mainWidth
        y: 0
        width: root.sideWidth
        height: root.height
        detail: root.detail
        btPaired: root.btPaired
        opacity: Motion.clamp01((root.detailProgress - 0.3) / 0.5)
        visible: root.detailWidth > 1
        onCloseRequested: root.detail = ""
    }

    Flickable {
        id: flick

        x: root.sideWidth
        y: 0
        width: root.mainWidth
        height: root.height
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
                    label: "Volume"
                    showValue: true
                    to: Audio.maxVolume
                    valueText: Math.round(shown * 100) + "%"
                    value: Audio.volume
                    enabled: Audio.ready
                    onMoved: v => Audio.setVolume(v)
                }

                IconButton {
                    icon: "\uf078"
                    iconSize: 11
                    iconRotation: 180 * root.appsProgress
                    active: root.appsOpen
                    onClicked: root.appsOpen = !root.appsOpen
                }
            }

            Item {
                id: appsClip

                Layout.fillWidth: true
                Layout.topMargin: -col.spacing * (1 - root.appsProgress)
                Layout.preferredHeight: appsInner.implicitHeight * root.appsProgress
                clip: true
                visible: root.appsProgress > 0

                ColumnLayout {
                    id: appsInner

                    width: parent.width
                    spacing: 6
                    transform: Translate {
                        y: -8 * (1 - root.appsProgress)
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: Audio.streams.length === 0
                        text: "No apps playing audio"
                        color: Theme.m3OnSurfaceVariant
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        opacity: Motion.clamp01(root.appsProgress * 1.5)
                    }

                    Repeater {
                        model: root.appsProgress > 0 ? Audio.streams : []

                        RowLayout {
                            id: appRow

                            required property var modelData
                            required property int index

                            readonly property real reveal: Motion.clamp01((root.appsProgress - Math.min(index, 5) * 0.12) / 0.4)

                            Layout.fillWidth: true
                            spacing: 8
                            opacity: reveal
                            transform: Translate {
                                y: -6 * (1 - appRow.reveal)
                            }

                            ValueSlider {
                                Layout.fillWidth: true
                                label: Audio.streamName(appRow.modelData)
                                showValue: true
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
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: Audio.micReady

                IconButton {
                    icon: Audio.micIcon()
                    active: !Audio.micMuted
                    onClicked: Audio.toggleMicMute()
                }

                ValueSlider {
                    Layout.fillWidth: true
                    label: "Microphone"
                    showValue: true
                    value: Audio.micVolume
                    onMoved: v => Audio.setMicVolume(v)
                }

                Item {
                    Layout.preferredWidth: 36
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
                    label: "Brightness"
                    showValue: true
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
                    subtitle: Display.focusAvailable ? "Grayscale" : "Unavailable"
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
                    icon: "\uf013"
                    title: "Settings"
                    subtitle: "Shoji"
                    active: ShellState.settingsOpen
                    onToggled: ShellState.toggleSettings()
                }

                Tile {
                    Layout.fillWidth: true
                    icon: "\uf0f4"
                    title: "Keep awake"
                    subtitle: KeepAwake.subtitle
                    active: KeepAwake.active
                    expandable: true
                    expanded: root.detail === "awake"
                    onToggled: KeepAwake.toggle()
                    onExpandRequested: root.toggleDetail("awake")
                }

                Tile {
                    Layout.fillWidth: true
                    icon: Power.profileIcon
                    title: "Laptop mode"
                    subtitle: Power.laptopModeEnabled ? Power.profileLabel : (Power.hasPerformanceProfile ? "Off · Performance" : "Off")
                    active: Power.laptopModeEnabled
                    expandable: Power.laptopModeEnabled
                    expanded: root.detail === "power"
                    onToggled: Power.toggleLaptopMode()
                    onExpandRequested: root.toggleDetail("power")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: Settings.trayIcons && root.trayItems.length > 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.m3OutlineVariant
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: SystemTray.items

                        delegate: TrayIcon {
                            id: trayIcon

                            required property var modelData

                            item: modelData
                            active: root.trayId === modelData.id
                            onMenuRequested: root.toggleTray(modelData.id, trayIcon)
                        }
                    }
                }
            }
        }
    }
}
