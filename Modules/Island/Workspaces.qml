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
    readonly property real edgeBleed: 6
    readonly property real reveal: Math.max(0, revealSpring.value)
    readonly property real fade: Motion.clamp01(fadeSpring.value)
    readonly property real labelReveal: Motion.clamp01((reveal - 0.35) / 0.65)
    readonly property real badgeFullWidth: 10 + iconMetrics.advanceWidth + 6 + labelMetrics.advanceWidth + 10
    property real dotsWidth: 0

    implicitWidth: Motion.lerp(dotsWidth, badgeFullWidth, reveal)
    implicitHeight: 22

    Binding on dotsWidth {
        when: !root.overview && dots.implicitWidth > 0
        restoreMode: Binding.RestoreNone
        value: Math.max(0, dots.implicitWidth - 6)
    }

    TextMetrics {
        id: iconMetrics

        text: "\uf009"
        font.family: Theme.fontIcon
        font.pixelSize: 11
    }

    TextMetrics {
        id: labelMetrics

        text: "Overview"
        font.family: Theme.fontUi
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    Spring {
        id: revealSpring

        target: root.overview ? 1 : 0
        token: Motion.settle
        epsilon: 0.0005
    }

    Spring {
        id: fadeSpring

        target: root.overview ? 1 : 0
        token: Motion.effectsSlow
        epsilon: 0.001
    }

    Item {
        id: stage

        anchors.fill: parent
        anchors.margins: -root.edgeBleed
        clip: true

        Row {
            id: dots

            anchors.centerIn: parent
            spacing: 0
            opacity: 1 - Motion.clamp01(root.fade / 0.4)
            scale: 1 - 0.3 * Motion.clamp01(root.reveal)
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

                        target: slot.modelData.active ? Theme.m3Primary : slot.modelData.urgent ? Theme.m3OnPrimaryContainer : Theme.glassInner(Theme.m3SurfaceContainerHighest)
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
            width: Motion.lerp(height, root.badgeFullWidth, root.reveal)
            height: root.implicitHeight
            radius: height / 2
            color: Theme.m3PrimaryContainer
            opacity: Motion.clamp01(root.fade / 0.3)
            scale: Motion.lerp(0.7, 1, root.reveal)
            visible: opacity > 0
            clip: true

            Row {
                anchors.centerIn: parent
                spacing: 6 * root.labelReveal

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf009"
                    color: Theme.m3OnPrimaryContainer
                    font.family: Theme.fontIcon
                    font.pixelSize: 11
                    opacity: Motion.clamp01(root.fade / 0.4)
                    scale: Motion.lerp(0.4, 1, root.reveal)
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: labelMetrics.advanceWidth * root.labelReveal
                    height: label.implicitHeight
                    clip: true
                    opacity: root.labelReveal

                    Text {
                        id: label

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Overview"
                        color: Theme.m3OnPrimaryContainer
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
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
}
