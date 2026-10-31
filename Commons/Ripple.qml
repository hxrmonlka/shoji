import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
    id: root

    property real radius: 0
    property color color: Theme.m3OnSurface
    property real originX: width / 2
    property real originY: height / 2
    readonly property real reach: Math.sqrt(width * width + height * height)

    visible: Settings.ripple

    function trigger(x, y) {
        if (!Settings.ripple)
            return;
        originX = x;
        originY = y;
        grow.value = 0;
        grow.velocity = 0;
        grow.kick();
        fade.value = 1;
        fade.velocity = 0;
        fade.kick();
    }

    function press(source, mouse) {
        const p = source.mapToItem(root, mouse.x, mouse.y);
        trigger(p.x, p.y);
    }

    Spring {
        id: grow

        target: 1
        token: ({ stiffness: 500, damping: 1 })
        epsilon: 0.002
    }

    Spring {
        id: fade

        target: 0
        token: ({ stiffness: 90, damping: 1 })
        epsilon: 0.002
    }

    Item {
        id: wave

        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            readonly property real r: root.reach * Motion.clamp01(grow.value)

            x: root.originX - r
            y: root.originY - r
            width: r * 2
            height: r * 2
            radius: r
            color: root.color
            opacity: 0.16 * Motion.clamp01(fade.value)
        }
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: wave
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        visible: fade.value > 0.002
    }
}
