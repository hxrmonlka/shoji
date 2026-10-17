pragma Singleton

import QtQuick
import Quickshell

QtObject {
    property bool expanded: false
    property bool spotlight: false
    property bool media: false
    property bool control: false
    property string tab: "calendar"

    readonly property var tabs: [
        { id: "launcher", label: "Launcher", icon: "\uf00a" },
        { id: "calendar", label: "Calendar", icon: "\uf073" },
        { id: "wallpapers", label: "Wallpapers", icon: "\uf03e" },
        { id: "settings", label: "Settings", icon: "\uf013" }
    ]

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

    readonly property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }
}
