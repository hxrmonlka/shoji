pragma Singleton

import QtQuick
import Quickshell

QtObject {
    property bool expanded: false
    readonly property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }
}
