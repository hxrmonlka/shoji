import QtQuick
import qs.Commons

Item {
    id: root

    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0
    readonly property bool pressed: area.pressed
    readonly property real shown: pressed ? pending : value
    readonly property real fraction: to > from ? Motion.clamp01((shown - from) / (to - from)) : 0

    property real pending: value

    signal moved(real v)
    signal committed(real v)

    implicitHeight: 28
    implicitWidth: 160
    opacity: enabled ? 1 : 0.4

    function snap(x) {
        let v = from + Motion.clamp01(x / width) * (to - from);
        if (step > 0)
            v = Math.round((v - from) / step) * step + from;
        return Math.max(from, Math.min(to, v));
    }

    Spring {
        id: fill

        target: root.fraction
        token: root.pressed ? Motion.effectsFast : Motion.effectsDefault
        epsilon: 0.0005
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 12
        radius: 6
        color: Theme.m3SurfaceContainerHighest

        Rectangle {
            width: Math.max(parent.height, (parent.width - 8) * fill.value)
            height: parent.height
            radius: parent.radius
            color: Theme.m3Primary
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => {
            root.pending = root.snap(mouse.x);
            root.moved(root.pending);
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const v = root.snap(mouse.x);
            if (v !== root.pending) {
                root.pending = v;
                root.moved(v);
            }
        }
        onReleased: root.committed(root.pending)
    }
}
