pragma Singleton

import QtQuick
import Quickshell

QtObject {
    property bool expanded: false
    property bool spotlight: false
    property bool media: false
    property string tab: "calendar"

    readonly property var tabs: [
        { id: "launcher", label: "Launcher", icon: "\uf00a" },
        { id: "calendar", label: "Calendar", icon: "\uf073" },
        { id: "wallpapers", label: "Wallpapers", icon: "\uf03e" }
    ]

    onExpandedChanged: {
        if (expanded) {
            media = false;
            spotlight = false;
        }
    }

    onMediaChanged: {
        if (media) {
            expanded = false;
            spotlight = false;
        }
    }

    onSpotlightChanged: {
        if (spotlight) {
            expanded = false;
            media = false;
        }
    }

    readonly property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }
}
