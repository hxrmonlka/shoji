import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

Item {
    id: root

    property string detail: ""
    property string kept: ""
    property var btPaired: []

    signal closeRequested

    readonly property string title: kept === "wifi" ? "Wi-Fi" : kept === "bt" ? "Bluetooth" : kept === "vpn" ? "VPN" : ""
    readonly property var rows: kept === "wifi" ? Network.networks.slice(0, 8) : kept === "bt" ? btPaired : kept === "vpn" ? Network.vpns : []

    onDetailChanged: {
        if (detail !== "")
            kept = detail;
    }

    function rowIcon() {
        return kept === "wifi" ? "\uf1eb" : kept === "bt" ? "\uf293" : "\uf023";
    }

    function rowLabel(m) {
        return kept === "wifi" ? m.ssid : m.name;
    }

    function rowTrailing(m) {
        if (kept === "wifi")
            return m.active ? "\uf00c" : m.secure ? "\uf023" : "";
        if (kept === "bt")
            return m.connected ? "\uf00c" : "";
        return m.active ? "\uf00c" : "";
    }

    function rowActive(m) {
        return kept === "bt" ? m.connected : m.active;
    }

    function rowClick(m) {
        if (kept === "wifi")
            Network.connect(m.ssid);
        else if (kept === "bt")
            m.connected = !m.connected;
        else
            Network.setVpn(m.name, !m.active);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: root.title
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            IconButton {
                implicitWidth: 32
                implicitHeight: 32
                iconSize: 12
                icon: "\uf00d"
                onClicked: root.closeRequested()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.kept === "bt" && root.btPaired.length === 0
            text: "No paired devices"
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 12
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: list.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list

                width: parent.width
                spacing: 2

                Repeater {
                    model: ScriptModel {
                        values: root.rows
                        objectProp: root.kept === "wifi" ? "ssid" : "name"
                    }

                    Item {
                        id: slot

                        required property var modelData
                        required property int index
                        property bool shown: false

                        width: list.width
                        height: 40
                        opacity: shown ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 220
                            }
                        }

                        transform: Translate {
                            x: slot.shown ? 0 : 18

                            Behavior on x {
                                NumberAnimation {
                                    duration: 320
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
                                }
                            }
                        }

                        Timer {
                            interval: Math.min(slot.index, 10) * 35 + 60
                            running: true
                            onTriggered: slot.shown = true
                        }

                        ListRow {
                            anchors.fill: parent
                            icon: root.rowIcon()
                            label: root.rowLabel(slot.modelData)
                            trailing: root.rowTrailing(slot.modelData)
                            active: root.rowActive(slot.modelData)
                            onClicked: root.rowClick(slot.modelData)
                        }
                    }
                }
            }
        }
    }
}
