pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/state/shoji/settings.json"

    readonly property var categories: [
        { id: "island", title: "Island", icon: "\uf2d0" },
        { id: "circles", title: "Circles", icon: "\uf111" },
        { id: "display", title: "Display", icon: "\uf108" },
        { id: "features", title: "Features", icon: "\uf205" },
        { id: "theming", title: "App theming", icon: "\uf53f" },
        { id: "lock", title: "Lock screen", icon: "\uf023" },
        { id: "system", title: "System", icon: "\uf085" }
    ]

    readonly property var schema: [
        { key: "pillHeight", cat: "island", section: "Pill", label: "Pill height", min: 32, max: 72, step: 1, def: 44 },
        { key: "pillPadding", cat: "island", section: "Pill", label: "Pill padding", min: 8, max: 40, step: 1, def: 16 },
        { key: "pillSpacing", cat: "island", section: "Pill", label: "Pill spacing", min: 6, max: 28, step: 1, def: 14 },
        { key: "topMargin", cat: "island", section: "Pill", label: "Top margin", min: 0, max: 40, step: 1, def: 8 },
        { key: "panelWidth", cat: "island", section: "Panel", label: "Panel width", min: 560, max: 1000, step: 10, def: 720 },
        { key: "panelHeight", cat: "island", section: "Panel", label: "Panel height", min: 360, max: 700, step: 10, def: 460 },
        { key: "panelRadius", cat: "island", section: "Panel", label: "Panel radius", min: 12, max: 48, step: 1, def: 32 },
        { key: "autoHideDelay", cat: "island", section: "Behavior", label: "Auto-hide delay (ms)", min: 200, max: 10000, step: 250, def: 2000 },
        { key: "hoverOpenDelay", cat: "island", section: "Behavior", label: "Hover to open (ms)", desc: "0 turns hover opening off.", min: 0, max: 2000, step: 50, def: 500 },
        { key: "scrollStep", cat: "island", section: "Behavior", label: "Scroll step (%)", desc: "Volume and brightness change per scroll notch.", min: 1, max: 20, step: 1, def: 2 },
        { key: "circleSize", cat: "circles", section: "Buttons", label: "Circle size", min: 32, max: 72, step: 1, def: 44 },
        { key: "circleGap", cat: "circles", section: "Buttons", label: "Circle gap", min: 4, max: 32, step: 1, def: 10 },
        { key: "mediaPanelWidth", cat: "circles", section: "Media panel", label: "Media width", min: 400, max: 900, step: 10, def: 600 },
        { key: "mediaPanelHeight", cat: "circles", section: "Media panel", label: "Media height", min: 240, max: 520, step: 10, def: 300 },
        { key: "controlPanelWidth", cat: "circles", section: "Control panel", label: "Control width", min: 320, max: 560, step: 10, def: 380 },
        { key: "controlSideWidth", cat: "circles", section: "Control panel", label: "Control side width", min: 240, max: 480, step: 10, def: 300 },
        { key: "controlPanelHeight", cat: "circles", section: "Control panel", label: "Control height", min: 360, max: 640, step: 10, def: 500 },
        { key: "nightTemperature", cat: "display", section: "Night mode", label: "Night temperature (K)", min: 2500, max: 6000, step: 100, def: 4000 },
        { key: "nightCommand", cat: "display", section: "Night mode", label: "Night command", desc: "Use {temp} for the temperature.", type: "string", def: "gammastep -m wayland -O {temp}" },
        { key: "updateStar", cat: "features", section: "Island", label: "Update star", desc: "Show the Lumina update star in the pill.", type: "bool", def: true },
        { key: "showWorkspaces", cat: "features", section: "Island", label: "Workspaces in the pill", desc: "Show the workspace switcher next to the date.", type: "bool", def: true },
        { key: "notificationPopups", cat: "features", section: "Overlays", label: "Notification pop-ups", desc: "Notifications still reach the notification center when off.", type: "bool", def: true },
        { key: "osd", cat: "features", section: "Overlays", label: "Volume and brightness bar", desc: "Show the bar while scrolling with Ctrl or Alt.", type: "bool", def: true },
        { key: "trayIcons", cat: "features", section: "Panels", label: "System tray", desc: "Show tray icons in the Control Panel.", type: "bool", def: true },
        { key: "visualizer", cat: "features", section: "Panels", label: "Audio visualizer", desc: "Run cava for the media panel bars.", type: "bool", def: true },
        { key: "clipboardHistory", cat: "features", section: "Background", label: "Clipboard history", desc: "Record copied text, images and files with cliphist.", type: "bool", def: true },
        { key: "themeMango", cat: "theming", section: "Apps", label: "MangoWM", desc: "Border, bar and shadow colors in mango/shoji/colors.conf.", type: "bool", def: true },
        { key: "themeKitty", cat: "theming", section: "Apps", label: "kitty", desc: "Terminal and tab colors in kitty/shoji-theme.conf.", type: "bool", def: true },
        { key: "themeBtop", cat: "theming", section: "Apps", label: "btop", desc: "Theme file btop/themes/shoji.theme.", type: "bool", def: true },
        { key: "themeEquicord", cat: "theming", section: "Apps", label: "Equicord", desc: "Theme file Equicord/themes/shoji-equicord.css.", type: "bool", def: true },
        { key: "themeGtk", cat: "theming", section: "Apps", label: "GTK 3 and 4", desc: "Colors and shapes for GTK apps, including Thunar.", type: "bool", def: true },
        { key: "themeHelium", cat: "theming", section: "Apps", label: "Helium", desc: "Needs a writable /etc/chromium/policies/managed/shoji-color.json.", type: "bool", def: true },
        { key: "themeRadius", cat: "theming", section: "Shape", label: "GTK corner radius", desc: "Cards and menus use this radius. Buttons and fields use two thirds of it.", min: 4, max: 24, step: 1, def: 12 },
        { key: "lockPamConfig", cat: "lock", section: "Authentication", label: "PAM service", desc: "Name of the PAM config used to check the password.", type: "string", def: "login" },
        { key: "logoutCommand", cat: "lock", section: "Power menu", label: "Logout command", desc: "Run by the Logout entry on the lock screen.", type: "string", def: "loginctl terminate-session \"$XDG_SESSION_ID\"" },
        { key: "screenshotDir", cat: "system", section: "Paths", label: "Screenshot folder", type: "string", def: "~/Pictures/Screenshots" },
        { key: "aliceDotfiles", cat: "system", section: "Paths", label: "Alice dotfiles path", desc: "Used by the Lumina update check as ALICE_DOTFILES.", type: "string", def: "" }
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
    readonly property bool updateStar: get("updateStar")
    readonly property bool showWorkspaces: get("showWorkspaces")
    readonly property bool notificationPopups: get("notificationPopups")
    readonly property bool osd: get("osd")
    readonly property bool trayIcons: get("trayIcons")
    readonly property bool visualizer: get("visualizer")
    readonly property bool clipboardHistory: get("clipboardHistory")
    readonly property bool themeMango: get("themeMango")
    readonly property bool themeKitty: get("themeKitty")
    readonly property bool themeBtop: get("themeBtop")
    readonly property bool themeEquicord: get("themeEquicord")
    readonly property bool themeGtk: get("themeGtk")
    readonly property bool themeHelium: get("themeHelium")
    readonly property int themeRadius: get("themeRadius")
    readonly property string lockPamConfig: get("lockPamConfig")
    readonly property string logoutCommand: get("logoutCommand")
    readonly property string screenshotDir: get("screenshotDir")
    readonly property string nightCommand: get("nightCommand")
    readonly property string aliceDotfiles: get("aliceDotfiles")

    function get(key) {
        const d = defs[key];
        const v = values[key];
        if (d.type === "string")
            return typeof v === "string" ? v : d.def;
        if (d.type === "bool")
            return typeof v === "boolean" ? v : d.def;
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
        } else if (d.type === "bool") {
            if (typeof raw === "boolean") {
                v = raw;
            } else {
                const t = String(raw).toLowerCase();
                if (t === "true" || t === "1" || t === "on" || t === "yes")
                    v = true;
                else if (t === "false" || t === "0" || t === "off" || t === "no")
                    v = false;
                else
                    return false;
            }
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

    function catTitle(id) {
        const c = categories.find(e => e.id === id);
        return c ? c.title : id;
    }

    function resetCategory(id) {
        const next = Object.assign({}, values);
        schema.forEach(e => {
            if (e.cat === id)
                delete next[e.key];
        });
        values = next;
        saver.restart();
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
