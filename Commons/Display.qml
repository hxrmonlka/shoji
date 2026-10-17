pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool focus: false
    property bool night: false

    readonly property bool focusAvailable: Settings.focusOnCommand.length > 0 && Settings.focusOffCommand.length > 0
    readonly property string nightCommand: Settings.nightCommand.replace("{temp}", String(Settings.nightTemperature))

    function setFocus(on) {
        if (!focusAvailable)
            return;
        focus = on;
        Quickshell.execDetached(["sh", "-c", on ? Settings.focusOnCommand : Settings.focusOffCommand]);
    }

    function setNight(on) {
        night = on;
    }

    function lock() {
        ShellState.control = false;
        Quickshell.execDetached(["sh", "-c", Settings.lockCommand]);
    }

    onNightCommandChanged: {
        if (!night)
            return;
        night = false;
        restart.start();
    }

    readonly property Timer restart: Timer {
        interval: 200
        onTriggered: root.night = true
    }

    readonly property Process nightProc: Process {
        command: ["sh", "-c", "exec " + root.nightCommand]
        running: root.night
        onExited: {
            if (root.night)
                root.night = false;
        }
    }
}
