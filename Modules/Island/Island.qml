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
    readonly property int circleSize: Settings.circleSize
    readonly property int circleGap: Settings.circleGap
    readonly property var tabEntry: ShellState.tabs.find(t => t.id === ShellState.tab) ?? ({})
    readonly property int tabWidth: tabEntry.w ?? Settings.panelWidth
    readonly property int tabHeight: tabEntry.h ?? Settings.panelHeight
    readonly property int maxTabWidth: ShellState.tabs.reduce((m, t) => Math.max(m, t.w ?? Settings.panelWidth), 0)
    readonly property int maxTabHeight: ShellState.tabs.reduce((m, t) => Math.max(m, t.h ?? Settings.panelHeight), 0)
    readonly property int contentWidth: Math.max(maxTabWidth, Settings.mediaPanelWidth, Settings.controlPanelWidth, pillWidth + 2 * (circleGap + circleSize))
    readonly property int contentHeight: Math.max(maxTabHeight, Settings.mediaPanelHeight, Settings.controlPanelHeight, circleSize)
    readonly property bool expanded: ShellState.expanded
    readonly property real progress: Math.max(0, morph.value)
    readonly property bool mediaOpen: ShellState.media
    readonly property real mediaProgress: Math.max(0, mediaSpring.value)
    readonly property bool controlOpen: ShellState.control
    readonly property real controlProgress: Math.max(0, controlSpring.value)
    readonly property real pillWidth: header.implicitWidth + Settings.pillPadding * 2
    readonly property int popupWidth: 440
    readonly property int popupHeight: 84
    readonly property int osdWidth: 340
    readonly property int osdHeight: 56
    readonly property bool osdOpen: ShellState.scrolling && !ShellState.panelsOpen
    readonly property bool popupOpen: Notifs.popup !== null && !ShellState.panelsOpen && !ShellState.scrolling
    readonly property bool hoverArmed: !ShellState.panelsOpen && !ShellState.spotlight && !ShellState.scrolling && !keysGrabbed && !popupOpen
    readonly property real popupProgress: Math.max(0, popupSpring.value)
    readonly property real osdProgress: Math.max(0, osdSpring.value)
    readonly property real mergeProgress: Math.max(popupProgress, osdProgress)
    readonly property real restWidth: Motion.lerp(Motion.lerp(pillWidth, popupWidth, popupProgress), osdWidth, osdProgress)
    readonly property real restHeight: Motion.lerp(Motion.lerp(pillHeight, popupHeight, popupProgress), osdHeight, osdProgress)

    property bool keysGrabbed: false

    function onWheelEvent(event) {
        const mods = event.modifiers;
        const dy = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
        console.log("shoji-wheel dy=" + event.angleDelta.y + " dx=" + event.angleDelta.x + " mods=" + mods + " grabbed=" + keysGrabbed);
        keysGrabbed = true;
        keyTimer.restart();
        if (mods & Qt.ControlModifier)
            ShellState.adjust("volume", dy);
        else if (mods & Qt.AltModifier)
            ShellState.adjust("brightness", dy);
    }

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
    WlrLayershell.keyboardFocus: keysGrabbed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

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

    Timer {
        id: keyTimer

        interval: 1200
        onTriggered: win.keysGrabbed = false
    }

    Spring {
        id: osdSpring

        target: win.osdOpen ? 1 : 0
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

    Spring {
        id: panelW

        target: win.tabWidth
        token: Motion.spatialDefault
        epsilon: 0.05
    }

    Spring {
        id: panelH

        target: win.tabHeight
        token: Motion.spatialDefault
        epsilon: 0.05
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

    component PointerWatcher: HoverHandler {
        property bool pointing: false

        onHoveredChanged: {
            if (hovered === pointing)
                return;
            pointing = hovered;
            if (hovered)
                ShellState.pointerEntered();
            else
                ShellState.pointerExited();
        }

        Component.onDestruction: {
            if (pointing)
                ShellState.pointerExited();
        }
    }

    component HoverOpener: HoverHandler {
        id: opener

        property bool armed: false

        signal triggered

        readonly property Timer openTimer: Timer {
            interval: Settings.hoverOpenDelay
            onTriggered: {
                if (opener.hovered && opener.armed)
                    opener.triggered();
            }
        }

        onHoveredChanged: {
            if (hovered && armed && Settings.hoverOpenDelay > 0)
                openTimer.restart();
            else
                openTimer.stop();
        }

        onArmedChanged: {
            if (!armed)
                openTimer.stop();
        }
    }

    Rectangle {
        id: island

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: Motion.lerp(win.restWidth, panelW.value, win.progress)
        height: Motion.lerp(win.restHeight, panelH.value, win.progress)
        radius: Motion.lerp(Motion.lerp(Motion.lerp(win.pillHeight / 2, Math.min(Settings.panelRadius, 28), win.popupProgress), win.osdHeight / 2, win.osdProgress), Settings.panelRadius, win.progress)
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant
        clip: true
        opacity: 1 - Motion.clamp01(Math.max(win.mediaProgress, win.controlProgress) / 0.3)
        visible: opacity > 0

        MouseArea {
            anchors.fill: parent
            enabled: !ShellState.panelsOpen
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                win.onWheelEvent(wheel);
                wheel.accepted = true;
            }
        }

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
            opacity: (1 - Motion.clamp01(win.progress / 0.25)) * (1 - Motion.clamp01(win.mergeProgress / 0.3))
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

        OsdBar {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: win.osdWidth
            height: win.osdHeight
            opacity: Motion.clamp01((win.osdProgress - 0.4) / 0.4) * (1 - Motion.clamp01(win.progress / 0.25))
            visible: opacity > 0
        }

        Body {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: panelW.value
            height: panelH.value
            opacity: Motion.clamp01((win.progress - 0.4) / 0.4)
            visible: opacity > 0
        }

        PointerWatcher {}

        HoverOpener {
            armed: win.hoverArmed
            onTriggered: ShellState.expanded = true
        }
    }

    MediaCircle {
        id: media

        size: win.circleSize
        restX: Motion.lerp(win.width / 2 - win.pillWidth / 2 - win.circleGap - win.circleSize, win.width / 2 - win.circleSize / 2, win.mergeProgress)
        openX: win.width / 2 - Settings.mediaPanelWidth / 2
        panelWidth: Settings.mediaPanelWidth
        panelHeight: Settings.mediaPanelHeight
        panelRadius: Settings.panelRadius
        progress: win.mediaProgress
        hiddenBy: Math.max(win.progress / 0.3, win.controlProgress / 0.3, win.mergeProgress / 0.7)
        onClicked: ShellState.media = true

        PointerWatcher {}

        HoverOpener {
            armed: win.hoverArmed
            onTriggered: ShellState.media = true
        }
    }

    ControlCircle {
        id: control

        size: win.circleSize
        restX: Motion.lerp(win.width / 2 + win.pillWidth / 2 + win.circleGap, win.width / 2 - win.circleSize / 2, win.mergeProgress)
        openX: win.width / 2 - Settings.controlPanelWidth / 2
        panelWidth: Settings.controlPanelWidth
        panelHeight: Settings.controlPanelHeight
        panelRadius: Settings.panelRadius
        progress: win.controlProgress
        hiddenBy: Math.max(win.progress / 0.3, win.mediaProgress / 0.3, win.mergeProgress / 0.7)
        onClicked: ShellState.control = true

        PointerWatcher {}

        HoverOpener {
            armed: win.hoverArmed
            onTriggered: ShellState.control = true
        }
    }
}
