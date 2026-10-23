pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string phase: "idle"

    readonly property bool shown: phase !== "idle"

    function check(): void {
        if (phase === "syncing" || phase === "done" || checker.running)
            return;
        checker.running = true;
    }

    function sync(): void {
        if (phase !== "available" || syncer.running)
            return;
        phase = "syncing";
        syncer.running = true;
    }

    function parse(text: string): void {
        if (phase === "syncing" || phase === "done")
            return;
        const parts = text.trim().split(/\s+/);
        phase = parts.length >= 2 && parts[0] !== parts[1] ? "available" : "idle";
    }

    function finished(ok: bool): void {
        if (ok) {
            phase = "done";
            doneTimer.restart();
        } else {
            phase = "available";
        }
    }

    readonly property Process checker: Process {
        command: ["sh", Quickshell.shellPath("scripts/lumina-check.sh"), Settings.aliceDotfiles]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    readonly property Process syncer: Process {
        command: ["sh", "-c", "if [ -z \"$ALICE_DOTFILES\" ] && [ -n \"$1\" ]; then export ALICE_DOTFILES=\"$1\"; fi; exec lumina sync self/rev", "sh", Settings.aliceDotfiles]
        onExited: code => root.finished(code === 0)
    }

    readonly property Timer doneTimer: Timer {
        interval: 3000
        onTriggered: {
            root.phase = "idle";
            root.check();
        }
    }

    readonly property Timer poll: Timer {
        interval: 6 * 60 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.check()
    }
}
