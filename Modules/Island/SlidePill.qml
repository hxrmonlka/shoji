import QtQuick
import qs.Commons

Rectangle {
    id: root

    property real from: 0
    property real to: 0
    property bool pressed: false
    property int dir: 1

    height: 30
    radius: height / 2
    color: Theme.m3PrimaryContainer
    x: left.value
    width: Math.max(0, right.value - left.value)
    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: squash.xScale
        yScale: squash.yScale
    }

    onFromChanged: dir = from >= left.value ? 1 : -1

    Squash {
        id: squash

        pressed: root.pressed
    }

    Spring {
        id: left

        target: root.from
        token: root.dir > 0 ? Motion.spatialSlow : Motion.spatialDefault
        epsilon: 0.05
    }

    Spring {
        id: right

        target: root.to
        token: root.dir > 0 ? Motion.spatialDefault : Motion.spatialSlow
        epsilon: 0.05
    }
}
