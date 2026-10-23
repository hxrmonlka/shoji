pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/state/shoji/settings.json"

    readonly property var schema: [
        { key: "pillHeight", group: "island", label: "Pill height", min: 32, max: 72, step: 1, def: 44 },
        { key: "pillPadding", group: "island", label: "Pill padding", min: 8, max: 40, step: 1, def: 16 },
        { key: "pillSpacing", group: "island", label: "Pill spacing", min: 6, max: 28, step: 1, def: 14 },
        { key: "topMargin", group: "island", label: "Top margin", min: 0, max: 40, step: 1, def: 8 },
        { key: "panelWidth", group: "island", label: "Panel width", min: 560, max: 1000, step: 10, def: 720 },
        { key: "panelHeight", group: "island", label: "Panel height", min: 360, max: 700, step: 10, def: 460 },
        { key: "panelRadius", group: "island", label: "Panel radius", min: 12, max: 48, step: 1, def: 32 },
        { key: "autoHideDelay", group: "island", label: "Auto-hide ms", min: 200, max: 10000, step: 250, def: 2000 },
        { key: "hoverOpenDelay", group: "island", label: "Hover to open ms (0 = off)", min: 0, max: 2000, step: 50, def: 500 },
        { key: "scrollStep", group: "island", label: "Scroll step (%)", min: 1, max: 20, step: 1, def: 2 },
        { key: "circleSize", group: "circles", label: "Circle size", min: 32, max: 72, step: 1, def: 44 },
        { key: "circleGap", group: "circles", label: "Circle gap", min: 4, max: 32, step: 1, def: 10 },
        { key: "mediaPanelWidth", group: "circles", label: "Media width", min: 400, max: 900, step: 10, def: 600 },
        { key: "mediaPanelHeight", group: "circles", label: "Media height", min: 240, max: 520, step: 10, def: 300 },
        { key: "controlPanelWidth", group: "circles", label: "Control width", min: 320, max: 560, step: 10, def: 380 },
        { key: "controlSideWidth", group: "circles", label: "Control side width", min: 240, max: 480, step: 10, def: 300 },
        { key: "controlPanelHeight", group: "circles", label: "Control height", min: 360, max: 640, step: 10, def: 500 },
        { key: "nightTemperature", group: "display", label: "Night temperature", min: 2500, max: 6000, step: 100, def: 4000 },
        { key: "lockPamConfig", type: "string", def: "login" },
        { key: "logoutCommand", type: "string", def: "loginctl terminate-session \"$XDG_SESSION_ID\"" },
        { key: "screenshotDir", type: "string", def: "~/Pictures/Screenshots" },
        { key: "focusOnCommand", type: "string", def: "" },
        { key: "focusOffCommand", type: "string", def: "" },
        { key: "nightCommand", type: "string", def: "gammastep -m wayland -O {temp}" },
        { key: "aliceDotfiles", type: "string", def: "" }
    ]

    readonly property var defs: schema.reduce((m, e) => {
        m[e.key] = e;
        return m;
    }, {})

    property var values: ({})

    readonly property int pillHeight: get("pillHeight")
    readonly property int pillPadding: get("pillPadding")
    readonly property int pillSpacing: get("pillSpacing")
    readonly property int topMargin: get("topMargin")
    readonly property int panelWidth: get("panelWidth")
    readonly property int panelHeight: get("panelHeight")
    readonly property int panelRadius: get("panelRadius")
    readonly property int autoHideDelay: get("autoHideDelay")
    readonly property int hoverOpenDelay: get("hoverOpenDelay")
    readonly property int scrollStep: get("scrollStep")
    readonly property int circleSize: get("circleSize")
    readonly property int circleGap: get("circleGap")
    readonly property int mediaPanelWidth: get("mediaPanelWidth")
    readonly property int mediaPanelHeight: get("mediaPanelHeight")
    readonly property int controlPanelWidth: get("controlPanelWidth")
    readonly property int controlSideWidth: get("controlSideWidth")
    readonly property int controlPanelHeight: get("controlPanelHeight")
    readonly property int nightTemperature: get("nightTemperature")
    readonly property string lockPamConfig: get("lockPamConfig")
    readonly property string logoutCommand: get("logoutCommand")
    readonly property string screenshotDir: get("screenshotDir")
    readonly property string focusOnCommand: get("focusOnCommand")
    readonly property string focusOffCommand: get("focusOffCommand")
    readonly property string nightCommand: get("nightCommand")
    readonly property string aliceDotfiles: get("aliceDotfiles")

    function get(key) {
        const d = defs[key];
        const v = values[key];
        if (d.type === "string")
            return typeof v === "string" ? v : d.def;
        const n = typeof v === "number" && isFinite(v) ? v : d.def;
        return Math.round(Math.max(d.min, Math.min(d.max, n)));
    }

    function set(key, raw) {
        const d = defs[key];
        if (!d)
            return false;
        let v;
        if (d.type === "string") {
            v = String(raw);
        } else {
            v = Number(raw);
            if (!isFinite(v))
                return false;
        }
        const next = Object.assign({}, values);
        next[key] = v;
        values = next;
        saver.restart();
        return true;
    }

    function reset() {
        values = ({});
        saver.restart();
    }

    function restore(raw) {
        try {
            const data = JSON.parse(raw);
            values = data !== null && typeof data === "object" && !Array.isArray(data) ? data : ({});
        } catch (e) {
            values = ({});
        }
    }

    function reload() {
        file.reload();
    }

    readonly property Timer saver: Timer {
        interval: 250
        onTriggered: file.setText(JSON.stringify(root.values, null, 2) + "\n")
    }

    readonly property FileView file: FileView {
        path: root.path
        atomicWrites: true
        printErrors: false
        onLoaded: root.restore(text())
    }
}
