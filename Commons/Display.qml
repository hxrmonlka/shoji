pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool focus: false
    property bool night: false
    property bool focusAvailable: false
    property bool focusWanted: false
    property bool focusLoaded: false
    property bool focusProbed: false

    readonly property string nightCommand: Settings.nightCommand.replace("{temp}", String(Settings.nightTemperature))

    function restore() {
        focusProbe.running = true;
    }

    function setFocus(on) {
        if (!focusAvailable)
            return;
        if (on && night)
            night = false;
        focusWanted = on;
        focus = on;
        focusStore.setText(JSON.stringify({ focus: on }) + "\n");
        applyFocus();
    }

    function applyFocus() {
        Quickshell.execDetached(["mmsg", "dispatch", focus ? "setgray,on" : "setgray,off"]);
    }

    function settleFocus() {
        if (!focusLoaded || !focusProbed)
            return;
        if (focusWanted && focusAvailable) {
            focus = true;
            applyFocus();
        } else if (!focusAvailable) {
            focus = false;
        }
    }

    function setNight(on) {
        if (on && focus)
            setFocus(false);
        night = on;
    }

    function lock() {
        ShellState.control = false;
        LockState.lock();
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

    readonly property Process focusProbe: Process {
        command: ["sh", "-c", "command -v mmsg >/dev/null 2>&1"]
        onExited: code => {
            root.focusAvailable = code === 0;
            root.focusProbed = true;
            root.settleFocus();
        }
    }

    readonly property FileView focusStore: FileView {
        path: Quickshell.env("HOME") + "/.local/state/shoji/display.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                root.focusWanted = JSON.parse(text()).focus === true;
            } catch (e) {
                root.focusWanted = false;
            }
            root.focusLoaded = true;
            root.settleFocus();
        }
        onLoadFailed: {
            root.focusLoaded = true;
            root.settleFocus();
        }
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
