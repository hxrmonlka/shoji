import QtQuick
import qs.Commons

Item {
    id: root

    readonly property bool wanted: PillCava.wanted
    readonly property int barCount: PillCava.bars
    readonly property real fullWidth: barCount * 3 + (barCount - 1) * 2

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
            model: root.barCount

            Item {
                required property int index

                width: 3
                height: 16

                Rectangle {
                    anchors.centerIn: parent
                    width: 3
                    height: 3 + Math.max(0, Math.min(1, PillCava.values[parent.index] ?? 0)) * 13
                    radius: 1.5
                    color: Theme.m3Primary
                }
            }
        }
    }
}
