pragma Singleton

import QtQuick
import Quickshell

QtObject {
    property bool expanded: false
    property bool spotlight: false
    property string tab: "calendar"

    readonly property var tabs: [
        { id: "launcher", label: "Launcher", icon: "\uf00a" },
        { id: "calendar", label: "Calendar", icon: "\uf073" }
    ]

    readonly property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }
}
