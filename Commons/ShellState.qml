pragma Singleton

import QtQuick
import Quickshell

QtObject {
    id: root

    property bool expanded: false
    property bool spotlight: false
    property bool media: false
    property bool control: false
    property string tab: "calendar"
    property int pointersInside: 0
    property int holds: 0
    property bool scrolling: false
    property string osdKind: "volume"

    readonly property bool panelsOpen: expanded || media || control

    readonly property var tabs: [
        { id: "launcher", label: "Launcher", icon: "\uf00a" },
        { id: "calendar", label: "Calendar", icon: "\uf073" },
        { id: "monitor", label: "Monitor", icon: "\uf200", w: 820, h: 500 },
        { id: "wallpapers", label: "Wallpapers", icon: "\uf03e" },
        { id: "settings", label: "Settings", icon: "\uf013" }
    ]

    function hidePanels(): void {
        expanded = false;
        media = false;
        control = false;
    }

    function pointerEntered(): void {
        pointersInside++;
        root.syncAutoHide();
    }

    function pointerExited(): void {
        pointersInside = Math.max(0, pointersInside - 1);
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
        } else if (Brightness.available) {
            if (!scrolling)
                Brightness.refresh();
            Brightness.set(Brightness.value + delta);
        } else {
            return;
        }
        markScroll(kind);
    }

    function markScroll(kind: string): void {
        osdKind = kind;
        scrolling = true;
        scrollTimer.restart();
    }

    function hold(on: bool): void {
        holds = Math.max(0, holds + (on ? 1 : -1));
        root.syncAutoHide();
    }

    function syncAutoHide(): void {
        if (panelsOpen && pointersInside === 0 && holds === 0)
            autoHide.restart();
        else
            autoHide.stop();
    }

    onPanelsOpenChanged: root.syncAutoHide()

    onExpandedChanged: {
        if (expanded) {
            media = false;
            control = false;
            spotlight = false;
        }
    }

    onMediaChanged: {
        if (media) {
            expanded = false;
            control = false;
            spotlight = false;
        }
    }

    onControlChanged: {
        if (control) {
            expanded = false;
            media = false;
            spotlight = false;
            Brightness.refresh();
        }
    }

    onSpotlightChanged: {
        if (spotlight) {
            expanded = false;
            media = false;
            control = false;
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
