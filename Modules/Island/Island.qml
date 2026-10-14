import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: win

    readonly property int pillHeight: 44
    readonly property int panelSize: 400
    readonly property bool expanded: State.expanded

    anchors.top: true
    margins.top: 8
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: panelSize
    implicitHeight: panelSize
    color: "transparent"
    mask: Region { item: island }

    WlrLayershell.namespace: "shoji-island"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: State.expanded = false
    }

    Rectangle {
        id: island

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: win.expanded ? win.panelSize : header.implicitWidth + 32
        height: win.expanded ? win.panelSize : win.pillHeight
        radius: win.expanded ? 32 : height / 2
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.outlineVariant
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
            cursorShape: Qt.PointingHandCursor
            onClicked: State.expanded = !State.expanded
        }

        Row {
            id: header

            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            height: win.pillHeight
            spacing: 14

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf313"
                color: Theme.primary
                font.family: Theme.fontIcon
                font.pixelSize: 20
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(State.clock.date, "HH:mm")
                color: Theme.onSurface
                font.family: Theme.fontUi
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(State.clock.date, "ddd MMM d")
                color: Theme.onSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: 13
            }

            Workspaces {
                anchors.verticalCenter: parent.verticalCenter
                screen: win.screen
            }
        }

        Calendar {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: win.pillHeight + 8
            anchors.leftMargin: 24
            anchors.rightMargin: 24
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
