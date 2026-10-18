import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Media
import qs.Modules.Control
import qs.Modules.Notifications

PanelWindow {
    id: win

    readonly property int pillHeight: Settings.pillHeight
    readonly property int panelWidth: Settings.panelWidth
    readonly property int panelHeight: Settings.panelHeight
    readonly property int circleSize: Settings.circleSize
    readonly property int circleGap: Settings.circleGap
    readonly property int contentWidth: Math.max(panelWidth, Settings.mediaPanelWidth, Settings.controlPanelWidth, pillWidth + 2 * (circleGap + circleSize))
    readonly property int contentHeight: Math.max(panelHeight, Settings.mediaPanelHeight, Settings.controlPanelHeight, circleSize)
    readonly property bool expanded: ShellState.expanded
    readonly property real progress: Math.max(0, morph.value)
    readonly property bool mediaOpen: ShellState.media
    readonly property real mediaProgress: Math.max(0, mediaSpring.value)
    readonly property bool controlOpen: ShellState.control
    readonly property real controlProgress: Math.max(0, controlSpring.value)
    readonly property real pillWidth: header.implicitWidth + Settings.pillPadding * 2
    readonly property int popupWidth: 440
    readonly property int popupHeight: 84
    readonly property bool popupOpen: Notifs.popup !== null && !expanded && !mediaOpen && !controlOpen
    readonly property real popupProgress: Math.max(0, popupSpring.value)
    readonly property real restWidth: Motion.lerp(pillWidth, popupWidth, popupProgress)
    readonly property real restHeight: Motion.lerp(pillHeight, popupHeight, popupProgress)

    anchors.top: true
    margins.top: Settings.topMargin
    exclusiveZone: pillHeight
    implicitWidth: contentWidth + 96
    implicitHeight: contentHeight + 56
    color: "transparent"
    mask: Region {
        item: island

        Region {
            item: media
        }

        Region {
            item: control
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
        id: popupSpring

        target: win.popupOpen ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    Spring {
        id: mediaSpring

        target: win.mediaOpen ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    Spring {
        id: controlSpring

        target: win.controlOpen ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            ShellState.expanded = false;
            ShellState.media = false;
            ShellState.control = false;
        }
    }

    Connections {
        target: ToplevelManager

        function onActiveToplevelChanged(): void {
            if (!ToplevelManager.activeToplevel)
                return;
            ShellState.expanded = false;
            ShellState.media = false;
            ShellState.control = false;
        }
    }

    Rectangle {
        id: island

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: Motion.lerp(win.restWidth, win.panelWidth, win.progress)
        height: Motion.lerp(win.restHeight, win.panelHeight, win.progress)
        radius: Motion.lerp(Motion.lerp(win.pillHeight / 2, Math.min(Settings.panelRadius, 28), win.popupProgress), Settings.panelRadius, win.progress)
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant
        clip: true
        opacity: 1 - Motion.clamp01(Math.max(win.mediaProgress, win.controlProgress) / 0.3)
        visible: opacity > 0

        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: win.pillHeight
            enabled: !win.expanded && win.mediaProgress < 0.05 && win.controlProgress < 0.05
            cursorShape: Qt.PointingHandCursor
            onClicked: ShellState.expanded = !ShellState.expanded
        }

        Row {
            id: header

            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            height: win.pillHeight
            spacing: Settings.pillSpacing
            opacity: (1 - Motion.clamp01(win.progress / 0.25)) * (1 - Motion.clamp01(win.popupProgress / 0.3))
            visible: opacity > 0

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf313"
                color: Theme.m3Primary
                font.family: Theme.fontIcon
                font.pixelSize: Math.round(win.pillHeight * 0.45)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(ShellState.clock.date, "HH:mm")
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: Math.round(win.pillHeight * 0.34)
                font.weight: Font.DemiBold
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(ShellState.clock.date, "ddd MMM d")
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: Math.round(win.pillHeight * 0.3)
            }

            Workspaces {
                anchors.verticalCenter: parent.verticalCenter
                screen: win.screen
            }
        }

        NotificationPopup {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: win.popupWidth
            height: win.popupHeight
            opacity: Motion.clamp01((win.popupProgress - 0.4) / 0.4) * (1 - Motion.clamp01(win.progress / 0.25))
            visible: opacity > 0
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

        size: win.circleSize
        restX: win.width / 2 - win.restWidth / 2 - win.circleGap - win.circleSize
        openX: win.width / 2 - Settings.mediaPanelWidth / 2
        panelWidth: Settings.mediaPanelWidth
        panelHeight: Settings.mediaPanelHeight
        panelRadius: Settings.panelRadius
        progress: win.mediaProgress
        hiddenBy: Math.max(win.progress, win.controlProgress) / 0.3
        onClicked: ShellState.media = true
    }

    ControlCircle {
        id: control

        size: win.circleSize
        restX: win.width / 2 + win.restWidth / 2 + win.circleGap
        openX: win.width / 2 - Settings.controlPanelWidth / 2
        panelWidth: Settings.controlPanelWidth
        panelHeight: Settings.controlPanelHeight
        panelRadius: Settings.panelRadius
        progress: win.controlProgress
        hiddenBy: Math.max(win.progress, win.mediaProgress) / 0.3
        onClicked: ShellState.control = true
    }
}
