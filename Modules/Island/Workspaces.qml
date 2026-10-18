import QtQuick
import Quickshell
import Quickshell.WindowManager
import qs.Commons

Item {
    id: root

    required property var screen

    readonly property var sets: Array.from(WindowManager.screenProjection(root.screen).windowsets)
    readonly property var overviewSet: sets.find(w => w.name === "overview") ?? null
    readonly property bool overview: overviewSet !== null
    property real dotsWidth: 0

    implicitWidth: Motion.lerp(dotsWidth, badge.implicitWidth, swap.value)
    implicitHeight: 22

    Binding on dotsWidth {
        when: !root.overview && dots.implicitWidth > 0
        value: dots.implicitWidth
    }

    Spring {
        id: swap

        target: root.overview ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    Row {
        id: dots

        anchors.centerIn: parent
        spacing: 6
        opacity: 1 - Motion.clamp01(swap.value / 0.5)
        visible: opacity > 0

        Repeater {
            model: WindowManager.screenProjection(root.screen).windowsets

            Rectangle {
                id: dot

                required property var modelData

                visible: modelData.shouldDisplay && modelData.name !== "overview"
                width: grow.value
                height: 8
                radius: 4
                color: tint.color

                Spring {
                    id: grow

                    target: dot.modelData.active ? 22 : 8
                    token: Motion.spatialFast
                    epsilon: 0.02
                }

                ColorSpring {
                    id: tint

                    target: dot.modelData.active ? Theme.m3Primary : dot.modelData.urgent ? Theme.m3OnPrimaryContainer : Theme.m3SurfaceContainerHighest
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dot.modelData.activate()
                }
            }
        }
    }

    Rectangle {
        id: badge

        anchors.centerIn: parent
        implicitWidth: badgeRow.implicitWidth + 20
        width: implicitWidth
        height: root.implicitHeight
        radius: height / 2
        color: Theme.m3PrimaryContainer
        opacity: Motion.clamp01((swap.value - 0.5) / 0.5)
        visible: opacity > 0

        Row {
            id: badgeRow

            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf009"
                color: Theme.m3OnPrimaryContainer
                font.family: Theme.fontIcon
                font.pixelSize: 11
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Overview"
                color: Theme.m3OnPrimaryContainer
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.overviewSet)
                    root.overviewSet.activate();
            }
        }
    }
}
