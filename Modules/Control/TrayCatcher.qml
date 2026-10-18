import QtQuick
import Quickshell
import Quickshell.Wayland

Variants {
    id: root

    property bool active: false

    signal dismissed

    model: Quickshell.screens

    delegate: PanelWindow {
        required property var modelData

        screen: modelData
        visible: root.active
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.namespace: "shoji-menu-catcher"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: root.dismissed()
        }
    }
}
