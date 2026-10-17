import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Media

PanelWindow {
    id: win

    readonly property int pillHeight: 44
    readonly property int panelWidth: 720
    readonly property int panelHeight: 460
    readonly property bool expanded: ShellState.expanded
    readonly property real progress: Math.max(0, morph.value)
    readonly property bool mediaOpen: ShellState.media
    readonly property real mediaProgress: Math.max(0, mediaSpring.value)
    readonly property real pillWidth: header.implicitWidth + 32

    anchors.top: true
    margins.top: 8
    exclusiveZone: pillHeight
    implicitWidth: panelWidth + 96
    implicitHeight: panelHeight + 56
    color: "transparent"
    mask: Region {
        item: island

        Region {
            item: media
        }
    }

    WlrLayershell.namespace: "shoji-island"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Spring {
        id: morph

        target: win.expanded ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    Spring {
        id: mediaSpring

        target: win.mediaOpen ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            ShellState.expanded = false;
            ShellState.media = false;
        }
    }

    Connections {
        target: ToplevelManager

        function onActiveToplevelChanged(): void {
            if (!ToplevelManager.activeToplevel)
                return;
            ShellState.expanded = false;
            ShellState.media = false;
        }
    }

    Rectangle {
        id: island

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: Motion.lerp(win.pillWidth, win.panelWidth, win.progress)
        height: Motion.lerp(win.pillHeight, win.panelHeight, win.progress)
        radius: Motion.lerp(win.pillHeight / 2, 32, win.progress)
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant
        clip: true
        opacity: 1 - Motion.clamp01(win.mediaProgress / 0.3)
        visible: opacity > 0

        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: win.pillHeight
            enabled: !win.expanded && win.mediaProgress < 0.05
            cursorShape: Qt.PointingHandCursor
            onClicked: ShellState.expanded = !ShellState.expanded
        }

        Row {
            id: header

            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            height: win.pillHeight
            spacing: 14
            opacity: 1 - Motion.clamp01(win.progress / 0.25)
            visible: opacity > 0

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf313"
                color: Theme.m3Primary
                font.family: Theme.fontIcon
                font.pixelSize: 20
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(ShellState.clock.date, "HH:mm")
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(ShellState.clock.date, "ddd MMM d")
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: 13
            }

            Workspaces {
                anchors.verticalCenter: parent.verticalCenter
                screen: win.screen
            }
        }

        Body {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: win.panelWidth
            height: win.panelHeight
            opacity: Motion.clamp01((win.progress - 0.4) / 0.4)
            visible: opacity > 0
        }
    }

    MediaCircle {
        id: media

        size: win.pillHeight
        restX: win.width / 2 - win.pillWidth / 2 - 10 - win.pillHeight
        openX: win.width / 2 - 300
        panelWidth: 600
        panelHeight: 300
        progress: win.mediaProgress
        hiddenBy: win.progress / 0.3
        onClicked: ShellState.media = true
    }
}
