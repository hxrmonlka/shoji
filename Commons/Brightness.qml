pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property real value: 0
    property bool available: false
    property real pending: -1
    property real queued: 0

    function refresh() {
        if (!reader.running)
            reader.running = true;
    }

    function nudge(delta) {
        queued += delta;
        if (pending >= 0) {
            const q = queued;
            queued = 0;
            set(value + q);
            return;
        }
        refresh();
    }

    function set(v) {
        value = Motion.clamp01(v);
        pending = value;
        sender.restart();
    }

    function parse(text) {
        const parts = text.trim().split("\n")[0].split(",");
        const pct = parseInt(parts[3]);
        if (isNaN(pct)) {
            available = false;
            return;
        }
        available = true;
        if (pending < 0)
            value = pct / 100;
        if (queued !== 0) {
            const q = queued;
            queued = 0;
            set(value + q);
        }
    }

    readonly property Process reader: Process {
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: code => {
            if (code !== 0)
                root.available = false;
        }
    }

    readonly property Timer sender: Timer {
        interval: 50
        onTriggered: {
            const pct = Math.max(1, Math.round(root.pending * 100));
            Quickshell.execDetached(["brightnessctl", "-q", "set", pct + "%"]);
            root.pending = -1;
        }
    }
}
