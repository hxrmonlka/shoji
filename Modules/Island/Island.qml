import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: win

    readonly property int pillHeight: 44
    readonly property int panelWidth: 720
    readonly property int panelHeight: 460
    readonly property bool expanded: ShellState.expanded

    anchors.top: true
    margins.top: 8
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: panelWidth
    implicitHeight: panelHeight
    color: "transparent"
    mask: Region { item: island }

    WlrLayershell.namespace: "shoji-island"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.expanded = false
    }

    Connections {
        target: ToplevelManager

        function onActiveToplevelChanged(): void {
            if (win.expanded && ToplevelManager.activeToplevel)
                ShellState.expanded = false;
        }
    }

    Rectangle {
        id: island

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: win.expanded ? win.panelWidth : header.implicitWidth + 32
        height: win.expanded ? win.panelHeight : win.pillHeight
        radius: win.expanded ? 32 : height / 2
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant
        clip: true

        Behavior on width {
            NumberAnimation {
                duration: Motion.medium4
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.emphasized
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: Motion.medium4
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.emphasized
            }
        }

        Behavior on radius {
            NumberAnimation {
                duration: Motion.medium4
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.emphasized
            }
        }

        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: win.pillHeight
            enabled: !win.expanded
            cursorShape: Qt.PointingHandCursor
            onClicked: ShellState.expanded = !ShellState.expanded
        }

        Row {
            id: header

            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            height: win.pillHeight
            spacing: 14
            opacity: win.expanded ? 0 : 1
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: win.expanded ? Motion.short3 : Motion.medium2
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: win.expanded ? Motion.emphasizedAccelerate : Motion.emphasizedDecelerate
                }
            }

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
            anchors.fill: parent
            opacity: win.expanded ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: win.expanded ? Motion.medium2 : Motion.short3
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: win.expanded ? Motion.emphasizedDecelerate : Motion.emphasizedAccelerate
                }
            }
        }
    }
}
