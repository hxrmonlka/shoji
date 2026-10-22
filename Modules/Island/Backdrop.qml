import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: win

    readonly property bool armed: ShellState.panelsOpen

    visible: !LockState.locked
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    mask: Region {
        width: win.armed ? win.width : 0
        height: win.armed ? win.height : 0
    }

    WlrLayershell.namespace: "shoji-backdrop"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        enabled: win.armed
        acceptedButtons: Qt.AllButtons
        onPressed: ShellState.hidePanels()
    }
}
