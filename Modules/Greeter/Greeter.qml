import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Lock

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: Theme.m3Surface

            LockScreen {
                anchors.fill: parent
                auth: GreeterState
                greeter: true
            }
        }
    }
}
