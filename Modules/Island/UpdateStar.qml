import QtQuick
import qs.Commons

Item {
    id: root

    property int size: 30
    readonly property bool done: LuminaUpdate.phase === "done"
    readonly property bool syncing: LuminaUpdate.phase === "syncing"

    width: Motion.lerp(0, glyph.implicitWidth, grow.value)
    height: glyph.implicitHeight
    visible: grow.value > 0.01

    Spring {
        id: grow

        target: LuminaUpdate.shown ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    ColorSpring {
        id: tint

        target: root.done ? Theme.m3Tertiary : Theme.m3Primary
    }

    Text {
        id: glyph

        anchors.centerIn: parent
        text: root.done ? "\u2726" : "\u2727"
        color: tint.color
        opacity: Motion.clamp01(grow.value) * pulse.level
        font.family: Theme.fontIcon
        font.pixelSize: root.size
    }

    QtObject {
        id: pulse

        property real level: 1

        readonly property SequentialAnimation loop: SequentialAnimation {
            running: root.syncing
            loops: Animation.Infinite
            onRunningChanged: {
                if (!running)
                    pulse.level = 1;
            }

            NumberAnimation {
                target: pulse
                property: "level"
                to: 0.35
                duration: 600
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: pulse
                property: "level"
                to: 1
                duration: 600
                easing.type: Easing.InOutSine
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        enabled: LuminaUpdate.phase === "available"
        cursorShape: Qt.PointingHandCursor
        onClicked: LuminaUpdate.sync()
    }
}
