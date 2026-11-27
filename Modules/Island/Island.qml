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
    readonly property int tabWidth: (tabEntry.w ?? Settings.panelWidth) + (ShellState.tab === "control" && ShellState.controlDetail ? Settings.controlSideWidth : 0)
    readonly property real mergedHide: Settings.mergeCircles ? 1 : 0
    readonly property int tabHeight: (tabEntry.h ?? Settings.panelHeight) - (ShellState.tabOnly ? 36 : 0)
    readonly property int maxTabWidth: ShellState.tabs.reduce((m, t) => Math.max(m, t.w ?? Settings.panelWidth), 0)
    readonly property int maxTabHeight: ShellState.tabs.reduce((m, t) => Math.max(m, t.h ?? Settings.panelHeight), 0)
    readonly property int controlBaseWidth: Settings.controlSideWidth + Settings.controlPanelWidth
    readonly property int powerWidth: 540
    readonly property int powerHeight: 240
    readonly property int spotlightWidth: 680
    readonly property int spotlightMaxHeight: 520
    readonly property bool spotlightScreen: (win.screen ? win.screen.name : "") === (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
    readonly property bool spotlightOpen: ShellState.spotlight && spotlightScreen
    readonly property real spotlightProgress: Math.max(0, spotlightSpring.value)
    readonly property int contentWidth: Math.max(maxTabWidth, powerWidth, spotlightWidth, Settings.mediaPanelWidth, controlBaseWidth + 2 * Settings.controlSideWidth, pillWidth + 2 * (circleGap + circleSize))
    readonly property int contentHeight: Math.max(maxTabHeight, powerHeight, spotlightMaxHeight, Settings.mediaPanelHeight, Settings.controlPanelHeight, circleSize)
    readonly property bool expanded: ShellState.expanded
    readonly property real progress: Math.max(0, morph.value)
    readonly property bool mediaOpen: ShellState.media
    readonly property real mediaProgress: Math.max(0, mediaSpring.value)
    readonly property bool powerOpen: ShellState.power
    readonly property real powerProgress: Math.max(0, powerSpring.value)
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
    readonly property real mergeProgress: Math.max(popupProgress, osdProgress, powerProgress, spotlightProgress)
    readonly property int glanceWidth: 500
    readonly property int glanceHeight: 132
    readonly property int glanceRadius: 28
    property bool glanceFrom: false
    readonly property bool glanceOpen: ShellState.glance || (win.expanded && glanceFrom)
    readonly property real glanceProgress: Math.max(0, glanceSpring.value)
    readonly property real impact: 0.3
    readonly property real shellProgress: Motion.soft(morph.value, impact)
    readonly property real shellPopup: Motion.soft(popupSpring.value, impact)
    readonly property real shellOsd: Motion.soft(osdSpring.value, impact)
    readonly property real shellPower: Motion.soft(powerSpring.value, impact)
    readonly property real shellSpotlight: Motion.soft(spotlightSpring.value, impact)
    readonly property real shellGlance: Motion.soft(glanceSpring.value, impact)
    readonly property real shellRestWidth: Motion.lerp(Motion.lerp(Motion.lerp(pillWidth, popupWidth, shellPopup), osdWidth, shellOsd), glanceWidth, shellGlance)
    readonly property real shellRestHeight: Motion.lerp(Motion.lerp(Motion.lerp(pillHeight, popupHeight, shellPopup), osdHeight, shellOsd), glanceHeight, shellGlance)

    property bool keysGrabbed: false
    property bool handoff: false
    property real fromX: 0
    property real fromW: 0
    property real fromH: 0
    property real fromR: 0

    function captureHandoff(): void {
        let src = null;
        if (progress > 0.05)
            src = island;
        else if (mediaProgress > 0.05)
            src = media;
        else if (controlProgress > 0.05)
            src = control;
        if (!src) {
            handoff = false;
            return;
        }
        fromX = src.x;
        fromW = src.width;
        fromH = src.height;
        fromR = src === island ? island.radius : src.radiusNow;
        handoff = true;
    }

    function captureSource() {
        if (progress > 0.05)
            return island;
        if (mediaProgress > 0.05)
            return media;
        if (controlProgress > 0.05)
            return control;
        return island;
    }

    function captureFrame() {
        const src = captureSource();
        const isIsland = src === island;
        const screenWidth = screen ? screen.width : win.width;
        const resting = isIsland && progress < 0.01 && mediaProgress < 0.01 && controlProgress < 0.01 && mergeProgress < 0.01 && glanceProgress < 0.01;
        return {
            w: src.width,
            h: src.height,
            r: isIsland ? island.radius : src.radiusNow,
            cx: screenWidth / 2 + (src.x + src.width / 2 - win.width / 2),
            top: Settings.topMargin + src.y,
            fill: isIsland ? island.color : Theme.m3SurfaceContainer,
            border: Theme.m3OutlineVariant,
            atRest: resting,
            fallback: false
        };
    }

    function restFrame() {
        const screenWidth = screen ? screen.width : win.width;
        return {
            w: Math.round(pillWidth),
            h: pillHeight,
            r: pillHeight / 2,
            cx: screenWidth / 2,
            top: Settings.topMargin,
            fill: Theme.glass(Theme.m3SurfaceContainer),
            border: Theme.m3OutlineVariant,
            atRest: true,
            fallback: false
        };
    }

    function grabCapture(done): bool {
        return captureSource().grabToImage(done);
    }

    function settleHandoff(): void {
        if (!handoff)
            return;
        const p = mediaOpen ? mediaProgress : controlOpen ? controlProgress : 0;
        if (p > 0.999)
            handoff = false;
    }

    Component.onCompleted: IslandHandoff.register(screen ? screen.name : "", win)
    Component.onDestruction: IslandHandoff.unregister(screen ? screen.name : "", win)

    onMediaProgressChanged: settleHandoff()
    onControlProgressChanged: settleHandoff()

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

    visible: !LockState.locked || IslandHandoff.holding
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
    WlrLayershell.keyboardFocus: keysGrabbed || (ShellState.panelsOpen && (!ShellState.spotlight || spotlightOpen)) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    Spring {
        id: morph

        target: win.expanded ? 1 : 0
        token: win.expanded ? Motion.spatialDefault : Motion.settle
        epsilon: 0.0005
    }

    Spring {
        id: spotlightSpring

        target: win.spotlightOpen ? 1 : 0
        token: win.spotlightOpen ? Motion.spatialDefault : Motion.settle
        epsilon: 0.0005
    }

    Spring {
        id: spotlightH

        target: spotlightPanel.wantedHeight
        token: Motion.spatialDefault
        epsilon: 0.05
    }

    Spring {
        id: glanceSpring

        target: win.glanceOpen ? 1 : 0
        token: win.glanceOpen ? Motion.spatialDefault : Motion.settle
        epsilon: 0.0005
    }

    Connections {
        target: ShellState

        function onExpandedChanged(): void {
            win.glanceFrom = ShellState.expanded && win.glanceProgress > 0.3;
        }
    }

    Spring {
        id: popupSpring

        target: win.popupOpen ? 1 : 0
        token: win.popupOpen ? Motion.spatialDefault : Motion.settle
        epsilon: 0.0005
    }

    Timer {
        id: keyTimer

        interval: 1200
        onTriggered: win.keysGrabbed = false
    }

    IdleInhibitor {
        window: win
        enabled: KeepAwake.active
    }

    function claimFocus() {
        if (ShellState.spotlight || (ShellState.expanded && ShellState.tab === "clipboard"))
            return;
        keys.forceActiveFocus();
    }

    Connections {
        target: ShellState

        function onExpandedChanged() {
            Qt.callLater(win.claimFocus);
        }

        function onMediaChanged() {
            if (ShellState.media)
                win.captureHandoff();
            Qt.callLater(win.claimFocus);
        }

        function onControlChanged() {
            if (ShellState.control)
                win.captureHandoff();
            Qt.callLater(win.claimFocus);
        }

        function onReclaimFocus() {
            Qt.callLater(win.claimFocus);
        }

        function onPowerChanged() {
            Qt.callLater(win.claimFocus);
        }

        function onSpotlightChanged() {
            Qt.callLater(win.claimFocus);
        }

        function onTabChanged() {
            Qt.callLater(win.claimFocus);
        }
    }

    Spring {
        id: osdSpring

        target: win.osdOpen ? 1 : 0
        token: win.osdOpen ? Motion.spatialDefault : Motion.settle
        epsilon: 0.0005
    }

    Spring {
        id: mediaSpring

        target: win.mediaOpen ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    Spring {
        id: powerSpring

        target: win.powerOpen ? 1 : 0
        token: win.powerOpen ? Motion.spatialDefault : Motion.settle
        epsilon: 0.0005
    }

    Spring {
        id: controlSpring

        target: win.controlOpen ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    Spring {
        id: headSpring

        target: win.expanded ? 0 : 1
        token: win.expanded ? Motion.effectsFast : Motion.lag
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
        id: keys

        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const mediaOpen = ShellState.media || (ShellState.expanded && ShellState.tab === "media");
            if (ShellState.power) {
                powerMenu.handleKey(event);
            } else if (mediaOpen && event.key === Qt.Key_Space && !event.isAutoRepeat) {
                if (Media.player)
                    Media.player.togglePlaying();
                event.accepted = true;
            } else if (mediaOpen && Media.multiple && (event.key === Qt.Key_Left || event.key === Qt.Key_Right) && !event.isAutoRepeat) {
                Media.step(event.key === Qt.Key_Right ? 1 : -1);
                event.accepted = true;
            }
        }
        Keys.onEscapePressed: {
            ShellState.glance = false;
            ShellState.power = false;
            ShellState.spotlight = false;
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
        width: Motion.lerp(Motion.lerp(Motion.lerp(win.shellRestWidth, panelW.value, win.shellProgress), win.powerWidth, win.shellPower), win.spotlightWidth, win.shellSpotlight)
        height: Motion.lerp(Motion.lerp(Motion.lerp(win.shellRestHeight, panelH.value, win.shellProgress), win.powerHeight, win.shellPower), spotlightH.value, win.shellSpotlight)
        radius: Motion.lerp(Motion.lerp(Motion.lerp(Motion.lerp(win.pillHeight / 2, Math.min(Settings.panelRadius, 28), win.popupProgress), win.osdHeight / 2, win.osdProgress), win.glanceRadius, Motion.clamp01(win.glanceProgress)), Settings.panelRadius, Math.max(win.progress, win.powerProgress, win.spotlightProgress))
        color: Theme.glass(Theme.m3SurfaceContainer)
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
            enabled: !win.expanded && !ShellState.glance && !win.powerOpen && !ShellState.spotlight && win.mediaProgress < 0.05 && win.controlProgress < 0.05
            cursorShape: Qt.PointingHandCursor
            onClicked: ShellState.openGlance()
        }

        MouseArea {
            anchors.fill: parent
            enabled: ShellState.glance && !win.expanded
            cursorShape: Qt.PointingHandCursor
            onClicked: ShellState.expanded = true
        }

        Row {
            id: header

            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.min(0, (parent.height - win.pillHeight) / 2)
            height: win.pillHeight
            spacing: Settings.pillSpacing
            scale: 0.94 + 0.06 * headSpring.value
            opacity: (1 - Motion.clamp01(win.progress / 0.25)) * Motion.clamp01(headSpring.value) * (1 - Motion.clamp01(win.mergeProgress / 0.3)) * (1 - Motion.clamp01(win.glanceProgress / 0.3))
            visible: opacity > 0

            UpdateStar {
                anchors.verticalCenter: parent.verticalCenter
                size: Math.round(win.pillHeight * 0.7)
            }

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

            PillViz {
                anchors.verticalCenter: parent.verticalCenter
            }

            PillIndicators {
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Glance {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: win.glanceWidth
            height: win.glanceHeight
            screen: win.screen
            opacity: Motion.clamp01((win.glanceProgress - 0.4) / 0.4) * (1 - Motion.clamp01(win.progress / 0.25))
            visible: opacity > 0
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

        SpotlightPanel {
            id: spotlightPanel

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: win.spotlightWidth
            height: spotlightH.value
            maxHeight: win.spotlightMaxHeight
            active: win.spotlightScreen
            opacity: Motion.clamp01((win.spotlightProgress - 0.4) / 0.4)
            visible: opacity > 0
        }

        PowerMenu {
            id: powerMenu

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: win.powerWidth
            height: win.powerHeight
            opacity: Motion.clamp01((win.powerProgress - 0.5) / 0.4)
            visible: opacity > 0
        }

        PointerWatcher {}

        HoverOpener {
            armed: win.hoverArmed
            onTriggered: ShellState.openGlance()
        }
    }

    MediaCircle {
        id: media

        size: Settings.mergeCircles ? 0 : win.circleSize
        restX: Motion.lerp(win.width / 2 - win.pillWidth / 2 - win.circleGap - win.circleSize, win.width / 2 - win.circleSize / 2, win.mergeProgress)
        openX: win.width / 2 - Settings.mediaPanelWidth / 2
        panelWidth: Settings.mediaPanelWidth
        panelHeight: Settings.mediaPanelHeight
        panelRadius: Settings.panelRadius
        progress: win.mediaProgress
        hiddenBy: Math.max(win.mediaOpen && win.handoff ? 0 : Math.max(win.progress, win.controlProgress) / 0.3, win.mergeProgress / 0.7, win.glanceProgress / 0.3, win.mergedHide)
        handoff: win.handoff
        fromX: win.fromX
        fromW: win.fromW
        fromH: win.fromH
        fromR: win.fromR
        onClicked: ShellState.media = true

        PointerWatcher {}

        HoverOpener {
            armed: win.hoverArmed
            onTriggered: ShellState.media = true
        }
    }

    ControlCircle {
        id: control

        size: Settings.mergeCircles ? 0 : win.circleSize
        restX: Motion.lerp(win.width / 2 + win.pillWidth / 2 + win.circleGap, win.width / 2 - win.circleSize / 2, win.mergeProgress)
        openX: win.width / 2 - win.controlBaseWidth / 2
        panelWidth: win.controlBaseWidth
        detailWidth: Settings.controlSideWidth
        panelHeight: Settings.controlPanelHeight
        panelRadius: Settings.panelRadius
        progress: win.controlProgress
        hiddenBy: Math.max(win.controlOpen && win.handoff ? 0 : Math.max(win.progress, win.mediaProgress) / 0.3, win.mergeProgress / 0.7, win.glanceProgress / 0.3, win.mergedHide)
        handoff: win.handoff
        fromX: win.fromX
        fromW: win.fromW
        fromH: win.fromH
        fromR: win.fromR
        onClicked: ShellState.control = true

        PointerWatcher {}

        HoverOpener {
            armed: win.hoverArmed
            onTriggered: ShellState.control = true
        }
    }
}
