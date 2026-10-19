import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Control

PopupWindow {
    id: root

    property var target: null
    property int pid: 0
    property string name: ""

    signal done

    anchor.item: root.target
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.Slide
    anchor.margins.top: 6
    grabFocus: true
    color: "transparent"
    implicitWidth: 208
    implicitHeight: col.implicitHeight + 28
    mask: Region {
        item: card
    }

    onVisibleChanged: {
        if (!visible)
            done();
    }

    Rectangle {
        id: card

        x: 6
        y: 6
        width: parent.width - 12
        height: parent.height - 12
        radius: 20
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant

        ColumnLayout {
            id: col

            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                text: root.name
                elide: Text.ElideRight
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            ListRow {
                Layout.fillWidth: true
                icon: "\uf0c5"
                label: "Copy PID"
                onClicked: {
                    Quickshell.clipboardText = String(root.pid);
                    root.done();
                }
            }

            ListRow {
                Layout.fillWidth: true
                icon: "\uf120"
                label: "Copy command"
                onClicked: reader.exec(["sh", "-c", "tr -s '\\0' ' ' < /proc/" + root.pid + "/cmdline"])
            }

            ListRow {
                Layout.fillWidth: true
                icon: "\uf011"
                label: "Terminate"
                onClicked: {
                    sig.exec(["kill", "-TERM", String(root.pid)]);
                    root.done();
                }
            }

            ListRow {
                Layout.fillWidth: true
                icon: "\uf0e7"
                label: "Force kill"
                onClicked: {
                    sig.exec(["kill", "-KILL", String(root.pid)]);
                    root.done();
                }
            }
        }
    }

    readonly property Process reader: Process {
        stdout: StdioCollector {
            onStreamFinished: Quickshell.clipboardText = text.trim()
        }
        onExited: code => {
            if (code !== 0)
                Quickshell.clipboardText = root.name;
            root.done();
        }
    }

    readonly property Process sig: Process {
    }
}
