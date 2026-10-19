import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Control

Item {
    id: root

    property real cpu: 0
    property real ram: 0
    property var procs: []
    property real prevTotal: 0
    property real prevIdle: 0
    property string sortKey: "mem"
    property bool sortDesc: true
    property int menuPid: 0
    property string menuName: ""
    property var menuAnchor: null
    property bool menuShown: false

    readonly property bool menuWanted: menuPid > 0 && menuAnchor !== null
    readonly property int cpuW: 64
    readonly property int memW: 92
    readonly property int pidW: 56

    readonly property var shown: {
        const dir = sortDesc ? -1 : 1;
        return procs.slice().sort((a, b) => {
            if (sortKey === "name")
                return dir * a.name.localeCompare(b.name);
            const av = sortKey === "cpu" ? a.cpu : sortKey === "mem" ? a.mem : a.pid;
            const bv = sortKey === "cpu" ? b.cpu : sortKey === "mem" ? b.mem : b.pid;
            return dir * (av - bv);
        });
    }

    function refresh(): void {
        if (probe.running || menuWanted)
            return;
        probe.exec(["sh", "-c", "export LC_ALL=C; head -n1 /proc/stat; echo ---; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; echo ---; ps -eo pid,pcpu,rss,comm --sort=-pcpu | head -n 16"]);
    }

    function ingest(text): void {
        const parts = text.split("\n---\n");
        if (parts.length < 3)
            return;
        const f = parts[0].trim().split(/\s+/).slice(1).map(Number);
        if (f.length >= 5) {
            const total = f.reduce((a, b) => a + b, 0);
            const idle = f[3] + f[4];
            if (prevTotal > 0 && total > prevTotal)
                cpu = Motion.clamp01(1 - (idle - prevIdle) / (total - prevTotal));
            prevTotal = total;
            prevIdle = idle;
        }
        const mem = {};
        parts[1].trim().split("\n").forEach(line => {
            const kv = line.trim().split(/\s+/);
            if (kv.length >= 2)
                mem[kv[0].replace(":", "")] = Number(kv[1]);
        });
        if (mem.MemTotal > 0)
            ram = Motion.clamp01(1 - (mem.MemAvailable || 0) / mem.MemTotal);
        procs = parts[2].trim().split("\n").slice(1).map(line => {
            const m = line.trim().match(/^(\d+)\s+([\d.]+)\s+(\d+)\s+(.+)$/);
            return m ? { pid: Number(m[1]), cpu: Number(m[2]), mem: Number(m[3]), name: m[4] } : null;
        }).filter(e => e !== null).slice(0, 15);
    }

    function fmtMem(kb): string {
        if (kb >= 1048576)
            return (kb / 1048576).toFixed(1) + " GB";
        if (kb >= 1024)
            return (kb / 1024).toFixed(1) + " MB";
        return kb + " KB";
    }

    function setSort(key): void {
        if (sortKey === key) {
            sortDesc = !sortDesc;
            return;
        }
        sortKey = key;
        sortDesc = key !== "name";
    }

    function openMenu(proc, anchor): void {
        if (menuPid === proc.pid) {
            menuPid = 0;
            return;
        }
        menuAnchor = anchor;
        menuName = proc.name;
        menuPid = proc.pid;
    }

    onMenuWantedChanged: {
        ShellState.hold(menuWanted);
        if (menuWanted) {
            showTimer.restart();
        } else {
            showTimer.stop();
            menuShown = false;
        }
    }

    Component.onCompleted: root.refresh()
    Component.onDestruction: if (root.menuWanted) ShellState.hold(false)

    readonly property Process probe: Process {
        stdout: StdioCollector {
            onStreamFinished: root.ingest(text)
        }
    }

    readonly property Timer poll: Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    readonly property Timer prime: Timer {
        interval: 350
        running: true
        onTriggered: root.refresh()
    }

    readonly property Timer showTimer: Timer {
        interval: 80
        onTriggered: root.menuShown = true
    }

    TrayCatcher {
        active: root.menuWanted
        onDismissed: root.menuPid = 0
    }

    ProcessMenu {
        target: root.menuAnchor
        visible: root.menuShown
        pid: root.menuPid
        name: root.menuName
        onDone: root.menuPid = 0
    }

    component Head: Item {
        id: head

        property string key: ""
        property string label: ""
        property bool lead: false
        property bool tail: false
        readonly property bool active: root.sortKey === head.key

        implicitHeight: 30

        Rectangle {
            anchors.centerIn: parent
            visible: head.active
            width: headRow.implicitWidth + 24
            height: 26
            radius: 13
            color: Theme.m3PrimaryContainer

            Row {
                id: headRow

                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: head.label
                    color: Theme.m3OnPrimaryContainer
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.sortDesc ? "\uf0d7" : "\uf0d8"
                    color: Theme.m3OnPrimaryContainer
                    font.family: Theme.fontIcon
                    font.pixelSize: 10
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: head.lead ? parent.left : undefined
            anchors.right: head.tail ? parent.right : undefined
            anchors.horizontalCenter: head.lead || head.tail ? undefined : parent.horizontalCenter
            visible: !head.active
            text: head.label
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setSort(head.key)
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                spacing: 8

                Head {
                    Layout.fillWidth: true
                    key: "name"
                    label: "Name"
                    lead: true
                }

                Head {
                    Layout.preferredWidth: root.cpuW
                    key: "cpu"
                    label: "CPU"
                }

                Head {
                    Layout.preferredWidth: root.memW
                    key: "mem"
                    label: "Memory"
                }

                Head {
                    Layout.preferredWidth: root.pidW
                    key: "pid"
                    label: "PID"
                    tail: true
                }
            }

            ListView {
                id: list

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel {
                    values: root.shown
                }

                delegate: Item {
                    id: prow

                    required property var modelData

                    width: list.width
                    height: 36

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: rowFill.color

                        ColorSpring {
                            id: rowFill

                            target: rowArea.containsMouse ? Theme.m3SurfaceContainerHigh : "transparent"
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            color: Theme.m3OnSurface
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                        }

                        Rectangle {
                            Layout.preferredWidth: root.cpuW
                            implicitHeight: 24
                            radius: 12
                            color: Theme.m3SurfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: modelData.cpu.toFixed(1) + "%"
                                color: Theme.m3OnSurface
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: root.memW
                            implicitHeight: 24
                            radius: 12
                            color: Theme.m3SurfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: root.fmtMem(modelData.mem)
                                color: Theme.m3OnSurface
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            Layout.preferredWidth: root.pidW
                            horizontalAlignment: Text.AlignRight
                            text: String(modelData.pid)
                            color: Theme.m3OnSurfaceVariant
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: rowArea

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                root.openMenu(modelData, prow);
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillHeight: true
            spacing: 18

            Meter {
                Layout.fillHeight: true
                Layout.preferredWidth: 52
                frac: root.cpu
                label: "CPU"
            }

            Meter {
                Layout.fillHeight: true
                Layout.preferredWidth: 52
                frac: root.ram
                label: "RAM"
            }
        }
    }

    component Meter: Item {
        id: meter

        property real frac: 0
        property string label: ""

        Spring {
            id: anim

            target: Motion.clamp01(meter.frac)
            token: Motion.effectsDefault
            epsilon: 0.0005
        }

        Text {
            id: pct

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(anim.value * 100) + "%"
            color: Theme.m3OnSurface
            font.family: Theme.fontUi
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Rectangle {
            id: track

            anchors.top: pct.bottom
            anchors.topMargin: 8
            anchors.bottom: cap.top
            anchors.bottomMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            width: 26
            radius: width / 2
            color: Theme.m3SurfaceContainerHighest

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 8
                height: Math.max(width, (parent.height - 8) * anim.value)
                radius: width / 2
                color: Theme.m3Primary
            }
        }

        Text {
            id: cap

            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: meter.label
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
}
