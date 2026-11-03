pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool active: false
    property int minutes: 0
    property real endsAt: 0
    property real now: Date.now()

    readonly property var choices: [
        { name: "30 minutes", minutes: 30 },
        { name: "1 hour", minutes: 60 },
        { name: "2 hours", minutes: 120 },
        { name: "Always", minutes: 0 }
    ]

    readonly property int remaining: active && endsAt > 0 ? Math.max(0, Math.ceil((endsAt - now) / 1000)) : 0

    readonly property string subtitle: {
        if (!active)
            return "Off";
        if (endsAt === 0)
            return "Always";
        const m = Math.floor(remaining / 60);
        const s = remaining % 60;
        return m + ":" + (s < 10 ? "0" : "") + s + " left";
    }

    function start(mins: int): void {
        minutes = mins;
        endsAt = mins > 0 ? Date.now() + mins * 60000 : 0;
        now = Date.now();
        active = true;
    }

    function stop(): void {
        active = false;
        endsAt = 0;
    }

    function toggle(): void {
        if (active)
            stop();
        else
            start(0);
    }

    readonly property Timer ticker: Timer {
        interval: 1000
        repeat: true
        running: root.active && root.endsAt > 0
        onTriggered: {
            root.now = Date.now();
            if (root.now >= root.endsAt)
                root.stop();
        }
    }

    readonly property Process inhibitor: Process {
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=shoji", "--why=Keep awake", "--mode=block", "sleep", "infinity"]
        running: root.active
    }
}
