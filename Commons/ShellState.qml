pragma Singleton

import QtQuick
import Quickshell

QtObject {
    property bool expanded: false
    property string tab: "calendar"

    readonly property var tabs: [
        { id: "calendar", label: "Calendar", icon: "\uf073" }
    ]

    readonly property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }
}
