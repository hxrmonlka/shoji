pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string name: ""

    readonly property FileView file: FileView {
        path: "/etc/hostname"
        onLoaded: root.name = text().trim()
    }
}
