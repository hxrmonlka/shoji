import QtQuick
import qs.Commons

Item {
    id: root

    readonly property bool wanted: Settings.mergeCircles && Settings.visualizer && Media.playing
    readonly property var taps: [2, 9, 17, 26, 35]
    readonly property real fullWidth: taps.length * 3 + (taps.length - 1) * 2

    width: Math.max(0, presence.value) * (fullWidth + Settings.pillSpacing) - Settings.pillSpacing
    height: 16
    visible: presence.value > 0.001
    opacity: Motion.clamp01(presence.value)
    clip: true

    Spring {
        id: presence

        target: root.wanted ? 1 : 0
        token: Motion.effectsSlow
        epsilon: 0.002
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        Repeater {
            model: root.taps

            Item {
                required property int modelData

                width: 3
                height: 16

                Rectangle {
                    anchors.centerIn: parent
                    width: 3
                    height: Math.max(3, (Cava.values[parent.modelData] ?? 0) * 16)
                    radius: 1.5
                    color: Theme.m3Primary
                }
            }
        }
    }
}
