pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool picking: false
    property string mode: "copy"
    property string stamp: ""
    property bool swatchReady: false
    property bool copied: false
    property real hue: 0
    property real sat: 0
    property real val: 1

    readonly property string frameDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shoji"
    readonly property string swatchPath: frameDir + "/swatch.png"
    readonly property string script: Quickshell.shellPath("scripts/colorpick.sh")
    readonly property color current: Qt.hsva(hue, sat, val, 1)
    readonly property int red: Math.round(current.r * 255)
    readonly property int green: Math.round(current.g * 255)
    readonly property int blue: Math.round(current.b * 255)
    readonly property string hex: "#" + pad(red) + pad(green) + pad(blue)
    readonly property bool busy: capturer.running || settle.running

    function pad(n) {
        return (n < 16 ? "0" : "") + n.toString(16);
    }

    function apply(c) {
        const h = c.hsvHue;
        if (h >= 0)
            hue = h;
        sat = Motion.clamp01(c.hsvSaturation);
        val = Motion.clamp01(c.hsvValue);
    }

    function setHue(h) {
        hue = Motion.clamp01(h);
    }

    function setSv(s, v) {
        sat = Motion.clamp01(s);
        val = Motion.clamp01(v);
    }

    function setChannel(ch, v) {
        const n = Math.max(0, Math.min(255, Math.round(v))) / 255;
        const c = current;
        apply(Qt.rgba(ch === "r" ? n : c.r, ch === "g" ? n : c.g, ch === "b" ? n : c.b, 1));
    }

    function setHex(text) {
        const m = /^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/.exec(String(text).trim());
        if (!m)
            return false;
        let h = m[1];
        if (h.length === 3)
            h = h.split("").map(x => x + x).join("");
        apply(Qt.rgba(parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255, parseInt(h.substr(4, 2), 16) / 255, 1));
        return true;
    }

    function begin(m: string): void {
        if (picking || busy || LockState.locked)
            return;
        mode = m;
        stamp = String(Date.now());
        ShellState.hidePanels();
        ShellState.spotlight = false;
        settle.restart();
    }

    function cancel(): void {
        if (!picking)
            return;
        picking = false;
        cleaner.exec(["sh", script, "clean", frameDir]);
    }

    function finish(c, swatch) {
        if (!picking)
            return;
        picking = false;
        swatchReady = swatch;
        apply(c);
        cleaner.exec(["sh", script, "clean", frameDir]);
        if (mode === "copy") {
            copyHex(true);
        } else {
            ShellState.tab = "color";
            ShellState.expanded = true;
            ShellState.pin();
        }
    }

    function copyHex(notify) {
        if (copier.running)
            return;
        copier.exec(["sh", script, "copy", hex, notify && swatchReady ? swatchPath : ""]);
        if (!notify) {
            copied = true;
            copiedTimer.restart();
        }
    }

    readonly property Timer settle: Timer {
        interval: 380
        onTriggered: capturer.exec(["sh", root.script, "capture", root.frameDir, root.stamp].concat(Quickshell.screens.map(s => s.name)))
    }

    readonly property Timer copiedTimer: Timer {
        interval: 1400
        onTriggered: root.copied = false
    }

    readonly property Process capturer: Process {
        onExited: code => {
            if (code === 0)
                root.picking = true;
        }
    }

    readonly property Process copier: Process {}

    readonly property Process cleaner: Process {}
}
