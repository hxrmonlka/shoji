pragma Singleton

import QtQuick
import Quickshell

QtObject {
    id: root

    property bool expanded: false
    property bool spotlight: false
    property bool media: false
    property bool control: false
    property bool power: false
    property bool settingsOpen: false
    property string tab: "calendar"
    property bool tabOnly: false
    property bool controlDetail: false
    property int pointersInside: 0
    property int holds: 0
    property bool pinned: false
    property bool scrolling: false
    property string osdKind: "volume"

    readonly property bool panelsOpen: expanded || media || control || power

    readonly property var baseTabs: [
        { id: "launcher", label: "Launcher", icon: "\uf00a" },
        { id: "calendar", label: "Calendar", icon: "\uf073" },
        { id: "monitor", label: "Monitor", icon: "\uf200", w: 820, h: 500, keep: true },
        { id: "wallpapers", label: "Wallpapers", icon: "\uf03e" },
        { id: "clipboard", label: "Clipboard", icon: "\uf0ea" },
        { id: "color", label: "Color", icon: "\uf1fb" }
    ]

    readonly property var tabs: Settings.mergeCircles ? baseTabs.concat([
        { id: "media", label: "Media", icon: "\uf001", w: Settings.mediaPanelWidth + 32, h: Settings.mediaPanelHeight + 68 },
        { id: "control", label: "Control", icon: "\uf1de", w: Settings.controlSideWidth + Settings.controlPanelWidth + 32, h: Settings.controlPanelHeight + 68 }
    ]) : baseTabs

    function hidePanels(): void {
        expanded = false;
        media = false;
        control = false;
        power = false;
    }

    function openSettings(): void {
        hidePanels();
        spotlight = false;
        settingsOpen = true;
    }

    function closeSettings(): void {
        settingsOpen = false;
    }

    function toggleSettings(): void {
        if (settingsOpen)
            closeSettings();
        else
            openSettings();
    }

    function openTab(id: string): void {
        if (!tabs.some(t => t.id === id))
            return;
        tabOnly = false;
        tab = id;
        expanded = true;
        pin();
    }

    function openTabSolo(id: string): void {
        openTab(id);
        if (tabs.some(t => t.id === id))
            tabOnly = Settings.ipcTabOnly;
    }

    function toggleTabSolo(id: string): void {
        if (expanded && tab === id)
            expanded = false;
        else
            openTabSolo(id);
    }

    function closeTab(id: string): void {
        if (expanded && tab === id)
            expanded = false;
    }

    function toggleTab(id: string): void {
        if (expanded && tab === id)
            expanded = false;
        else
            openTab(id);
    }

    function pointerEntered(): void {
        pointersInside++;
        root.syncAutoHide();
    }

    function pointerExited(): void {
        pointersInside = Math.max(0, pointersInside - 1);
        if (pointersInside === 0)
            pinned = false;
        root.syncAutoHide();
    }

    function adjust(kind: string, dy: real): void {
        if (dy === 0)
            return;
        const delta = dy / 120 * Settings.scrollStep / 100;
        if (kind === "volume") {
            if (!Audio.ready)
                return;
            Audio.setVolume(Audio.volume + delta);
        } else {
            if (!Brightness.available) {
                Brightness.refresh();
                return;
            }
            Brightness.nudge(delta);
        }
        markScroll(kind);
    }

    function markScroll(kind: string): void {
        if (!Settings.osd)
            return;
        osdKind = kind;
        scrolling = true;
        scrollTimer.restart();
    }

    function hold(on: bool): void {
        holds = Math.max(0, holds + (on ? 1 : -1));
        root.syncAutoHide();
    }

    function pin(): void {
        pinned = panelsOpen;
        root.syncAutoHide();
    }

    function syncAutoHide(): void {
        if (panelsOpen && !power && !pinned && pointersInside === 0 && holds === 0)
            autoHide.restart();
        else
            autoHide.stop();
    }

    onPanelsOpenChanged: {
        if (!panelsOpen)
            pinned = false;
        root.syncAutoHide();
    }

    onExpandedChanged: {
        if (expanded) {
            tabOnly = false;
            media = false;
            control = false;
            power = false;
            spotlight = false;
        }
    }

    onMediaChanged: {
        if (media) {
            expanded = false;
            control = false;
            power = false;
            spotlight = false;
        }
    }

    onControlChanged: {
        if (control) {
            expanded = false;
            media = false;
            power = false;
            spotlight = false;
            Brightness.refresh();
        }
    }

    onSpotlightChanged: {
        if (spotlight) {
            expanded = false;
            media = false;
            control = false;
            power = false;
        }
    }

    onPowerChanged: {
        if (power) {
            expanded = false;
            media = false;
            control = false;
            spotlight = false;
        }
    }

    readonly property Timer scrollTimer: Timer {
        interval: 900
        onTriggered: root.scrolling = false
    }

    readonly property Timer autoHide: Timer {
        interval: Settings.autoHideDelay
        onTriggered: root.hidePanels()
    }

    readonly property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }
}
