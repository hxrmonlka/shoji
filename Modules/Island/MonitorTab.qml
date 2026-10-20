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
    property real cpuTemp: 0
    property real ramUsedKb: 0
    property real ramTotalKb: 0
    property bool gpuAvailable: false
    property real gpu: 0
    property real gpuTemp: 0
    property real vramUsed: 0
    property real vramTotal: 0
    property real diskRead: 0
    property real diskWrite: 0
    property real netDown: 0
    property real netUp: 0
    property real prevTime: 0
    property real prevDiskR: 0
    property real prevDiskW: 0
    property real prevNetRx: 0
    property real prevNetTx: 0
    property var cpuH: []
    property var ramH: []
    property var gpuH: []
    property var diskRH: []
    property var diskWH: []
    property var netDH: []
    property var netUH: []
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
    readonly property int history: 45

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
        probe.exec(["sh", Quickshell.shellPath("scripts/sysstat.sh")]);
    }

    function push(arr, v): var {
        return arr.concat([v]).slice(-history);
    }

    function ingest(text): void {
        const parts = text.split("\n---\n");
        if (parts.length < 4)
            return;
        const f = parts[0].trim().split(/\s+/).slice(1).map(Number);
        if (f.length >= 5) {
            const total = f.reduce((a, b) => a + b, 0);
            const idle = f[3] + f[4];
            if (prevTotal > 0 && total > prevTotal) {
                cpu = Motion.clamp01(1 - (idle - prevIdle) / (total - prevTotal));
                cpuH = push(cpuH, cpu);
            }
            prevTotal = total;
            prevIdle = idle;
        }
        const mem = {};
        parts[1].trim().split("\n").forEach(line => {
            const kv = line.trim().split(/\s+/);
            if (kv.length >= 2)
                mem[kv[0].replace(":", "")] = Number(kv[1]);
        });
        if (mem.MemTotal > 0) {
            ramTotalKb = mem.MemTotal;
            ramUsedKb = mem.MemTotal - (mem.MemAvailable || 0);
            ram = Motion.clamp01(ramUsedKb / ramTotalKb);
            ramH = push(ramH, ram);
        }
        const sys = {};
        parts[2].trim().split("\n").forEach(line => {
            const a = line.trim().split(/\s+/);
            sys[a[0]] = a.slice(1);
        });
        cpuTemp = sys.cputemp && sys.cputemp.length > 0 ? Number(sys.cputemp[0]) / 1000 : 0;
        const g = sys.gpu || ["none"];
        gpuAvailable = g[0] !== "none" && g.length >= 4;
        if (gpuAvailable) {
            gpu = Motion.clamp01(Number(g[0]) / 100);
            gpuTemp = Number(g[1]);
            vramUsed = Number(g[2]);
            vramTotal = Number(g[3]);
            gpuH = push(gpuH, gpu);
        }
        const now = Number(sys.t ? sys.t[0] : 0);
        const dr = Number(sys.disk ? sys.disk[0] : 0);
        const dw = Number(sys.disk ? sys.disk[1] : 0);
        const rx = Number(sys.net ? sys.net[0] : 0);
        const tx = Number(sys.net ? sys.net[1] : 0);
        if (prevTime > 0 && now > prevTime) {
            const dt = now - prevTime;
            diskRead = Math.max(0, (dr - prevDiskR) * 512 / dt);
            diskWrite = Math.max(0, (dw - prevDiskW) * 512 / dt);
            netDown = Math.max(0, (rx - prevNetRx) / dt);
            netUp = Math.max(0, (tx - prevNetTx) / dt);
            diskRH = push(diskRH, diskRead);
            diskWH = push(diskWH, diskWrite);
            netDH = push(netDH, netDown);
            netUH = push(netUH, netUp);
        }
        prevTime = now;
        prevDiskR = dr;
        prevDiskW = dw;
        prevNetRx = rx;
        prevNetTx = tx;
        procs = parts[3].trim().split("\n").slice(1).map(line => {
            const m = line.trim().match(/^(\d+)\s+([\d.]+)\s+(\d+)\s+(.+)$/);
            return m ? { pid: Number(m[1]), cpu: Number(m[2]), mem: Number(m[3]), name: m[4] } : null;
        }).filter(e => e !== null).slice(0, 15);
    }

    function fmtRate(bps): string {
        if (bps >= 1073741824)
            return (bps / 1073741824).toFixed(1) + " GB/s";
        if (bps >= 1048576)
            return (bps / 1048576).toFixed(1) + " MB/s";
        if (bps >= 1024)
            return Math.round(bps / 1024) + " KB/s";
        return Math.round(bps) + " B/s";
    }

    function fmtMb(mb): string {
        return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : Math.round(mb) + " MB";
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

        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 252
            spacing: 6

            StatCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "CPU"
                detail: root.cpuTemp > 0 ? Math.round(root.cpuTemp) + "\u00b0C" : ""
                value: Math.round(root.cpu * 100) + "%"
                series: root.cpuH
            }

            StatCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "Memory"
                detail: root.fmtMem(root.ramUsedKb) + " / " + root.fmtMem(root.ramTotalKb)
                value: Math.round(root.ram * 100) + "%"
                series: root.ramH
            }

            StatCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.gpuAvailable
                label: "GPU"
                detail: (root.gpuTemp > 0 ? Math.round(root.gpuTemp) + "\u00b0C  " : "") + (root.vramTotal > 0 ? root.fmtMb(root.vramUsed) + " / " + root.fmtMb(root.vramTotal) : "")
                value: Math.round(root.gpu * 100) + "%"
                series: root.gpuH
            }

            StatCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "Disk"
                detail: "W " + root.fmtRate(root.diskWrite)
                value: "R " + root.fmtRate(root.diskRead)
                series: root.diskRH
                series2: root.diskWH
                maxValue: 1048576
                auto: true
            }

            StatCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "Network"
                detail: "\u2191 " + root.fmtRate(root.netUp)
                value: "\u2193 " + root.fmtRate(root.netDown)
                series: root.netDH
                series2: root.netUH
                maxValue: 131072
                auto: true
            }
        }
    }
}
