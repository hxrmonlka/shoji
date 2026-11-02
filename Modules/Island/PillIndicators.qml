import QtQuick
import qs.Commons

Item {
    id: root

    readonly property real iconSize: Math.round(Settings.pillHeight * 0.36)
    readonly property real slotWidth: iconSize + 6
    readonly property bool micMuted: Audio.micReady && Audio.micMuted
    readonly property bool micShown: Settings.pillIndicators && (micMuted || micLinger)
    readonly property bool shareShown: Settings.pillIndicators && Capture.sharing
    property bool micLinger: false

    width: row.width + Settings.pillSpacing * Math.min(1, row.width / slotWidth) - Settings.pillSpacing
    height: Settings.pillHeight
    visible: row.width > 0.01
    clip: true

    onMicMutedChanged: {
        if (!micMuted && Audio.micReady) {
            micLinger = true;
            lingerTimer.restart();
        } else {
            micLinger = false;
            lingerTimer.stop();
        }
    }

    Timer {
        id: lingerTimer

        interval: 1000
        onTriggered: root.micLinger = false
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter

        Item {
            id: micSlot

            width: Math.max(0, micPresence.value) * root.slotWidth
            height: root.height
            clip: true
            visible: width > 0.01

            Spring {
                id: micPresence

                target: root.micShown ? 1 : 0
                token: Motion.spatialDefault
                epsilon: 0.002
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.micMuted ? "\uf131" : "\uf130"
                color: root.micMuted ? Theme.m3Tertiary : Theme.m3Primary
                opacity: Motion.clamp01(micPresence.value)
                scale: 0.6 + 0.4 * Motion.clamp01(micPresence.value)
                font.family: Theme.fontIcon
                font.pixelSize: root.iconSize
            }
        }

        Item {
            id: shareSlot

            width: Math.max(0, sharePresence.value) * root.slotWidth
            height: root.height
            clip: true
            visible: width > 0.01

            Spring {
                id: sharePresence

                target: root.shareShown ? 1 : 0
                token: Motion.spatialDefault
                epsilon: 0.002
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf108"
                color: Theme.m3Tertiary
                opacity: Motion.clamp01(sharePresence.value)
                scale: 0.6 + 0.4 * Motion.clamp01(sharePresence.value)
                font.family: Theme.fontIcon
                font.pixelSize: root.iconSize
            }
        }
    }
}
