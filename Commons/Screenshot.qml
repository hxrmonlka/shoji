pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool selecting: false
    property string pendingMode: ""
    property string pendingArg: ""
    property string last: ""

    readonly property bool busy: runner.running || settle.running

    function begin(mode: string, arg: string): void {
        if (busy || selecting)
            return;
        ShellState.hidePanels();
        ShellState.spotlight = false;
        if (mode === "region") {
            selecting = true;
            return;
        }
        pendingMode = mode;
        pendingArg = arg;
        settle.restart();
    }

    function fullscreen(output: string): void {
        begin("fullscreen", output);
    }

    function window(): void {
        begin("window", "");
    }

    function region(): void {
        begin("region", "");
    }

    function cancel(): void {
        selecting = false;
    }

    function finishRegion(x: int, y: int, w: int, h: int): void {
        selecting = false;
        pendingMode = "region";
        pendingArg = x + "," + y + " " + w + "x" + h;
        settle.interval = 160;
        settle.restart();
    }

    readonly property Timer settle: Timer {
        interval: 380
        onTriggered: {
            interval = 380;
            runner.exec(["sh", Quickshell.shellPath("scripts/screenshot.sh"), root.pendingMode, Settings.screenshotDir, root.pendingArg]);
        }
    }

    readonly property Process runner: Process {
        stdout: StdioCollector {
            onStreamFinished: root.last = text.trim()
        }
    }
}
