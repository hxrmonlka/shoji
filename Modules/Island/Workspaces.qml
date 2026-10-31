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
        value: Math.max(0, dots.implicitWidth - 6)
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
        spacing: 0
        opacity: 1 - Motion.clamp01(swap.value / 0.5)
        visible: opacity > 0

        Repeater {
            model: WindowManager.screenProjection(root.screen).windowsets

            Item {
                id: slot

                required property var modelData
                readonly property bool shown: modelData.shouldDisplay && modelData.name !== "overview"

                width: Math.max(0, presence.value) * (grow.value + 6)
                height: 8
                visible: presence.value > 0.001

                Spring {
                    id: presence

                    target: slot.shown ? 1 : 0
                    token: Motion.effectsSlow
                    epsilon: 0.002
                }

                Spring {
                    id: grow

                    target: slot.modelData.active ? 22 : 8
                    token: Motion.spatialFast
                    epsilon: 0.02
                }

                ColorSpring {
                    id: tint

                    target: slot.modelData.active ? Theme.m3Primary : slot.modelData.urgent ? Theme.m3OnPrimaryContainer : Theme.m3SurfaceContainerHighest
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: grow.value
                    height: 8
                    radius: 4
                    color: tint.color
                    opacity: Motion.clamp01(presence.value)

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: slot.shown
                        cursorShape: Qt.PointingHandCursor
                        onClicked: slot.modelData.activate()
                    }
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
