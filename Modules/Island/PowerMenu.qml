import QtQuick
import Quickshell
import qs.Commons

Item {
    id: root

    property int index: 0
    readonly property int columns: 3

    readonly property var actions: [
        { id: "lock", label: "Lock", icon: "\uf023" },
        { id: "suspend", label: "Suspend", icon: "\uf186" },
        { id: "shoji", label: "Restart Shoji", icon: "\uf021" },
        { id: "poweroff", label: "Shutdown", icon: "\uf011" },
        { id: "reboot", label: "Reboot", icon: "\uf01e" },
        { id: "firmware", label: "Reboot to firmware", icon: "\uf2db" }
    ]

    function run(id: string): void {
        ShellState.power = false;
        switch (id) {
        case "lock":
            LockState.lock();
            break;
        case "suspend":
            LockState.lock();
            Quickshell.execDetached(["sh", "-c", "sleep 0.6; systemctl suspend"]);
            break;
        case "shoji":
            Quickshell.reload(true);
            break;
        case "poweroff":
            Quickshell.execDetached(["systemctl", "poweroff"]);
            break;
        case "reboot":
            Quickshell.execDetached(["systemctl", "reboot"]);
            break;
        case "firmware":
            Quickshell.execDetached(["systemctl", "reboot", "--firmware-setup"]);
            break;
        }
    }

    function step(delta: int): void {
        const n = actions.length;
        index = ((index + delta) % n + n) % n;
    }

    function handleKey(event): void {
        switch (event.key) {
        case Qt.Key_Escape:
            ShellState.power = false;
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            step(-1);
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
        case Qt.Key_Tab:
            step(1);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            step(-columns);
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            step(columns);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            run(actions[index].id);
            break;
        default:
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6)
                run(actions[event.key - Qt.Key_1].id);
            else
                return;
        }
        event.accepted = true;
    }

    Connections {
        target: ShellState

        function onPowerChanged() {
            if (ShellState.power)
                root.index = 0;
        }
    }

    Grid {
        anchors.fill: parent
        anchors.margins: 20
        columns: root.columns
        spacing: 10

        Repeater {
            model: root.actions

            Rectangle {
                id: tile

                required property var modelData
                required property int index
                readonly property bool selected: root.index === index

                width: (root.width - 40 - 2 * 10) / 3
                height: (root.height - 40 - 10) / 2
                radius: 22
                color: fill.color

                ColorSpring {
                    id: fill

                    target: tile.selected ? Theme.m3PrimaryContainer : Theme.m3SurfaceContainerHigh
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.modelData.icon
                        color: tile.selected ? Theme.m3OnPrimaryContainer : Theme.m3Primary
                        font.family: Theme.fontIcon
                        font.pixelSize: 24
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.modelData.label
                        color: tile.selected ? Theme.m3OnPrimaryContainer : Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }

                Ripple {
                    id: ripple1

                    anchors.fill: parent
                    radius: parent.radius
                }

                MouseArea {
                    id: rippleArea1

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => ripple1.press(rippleArea1, mouse)
                    onEntered: root.index = tile.index
                    onClicked: root.run(tile.modelData.id)
                }
            }
        }
    }
}
