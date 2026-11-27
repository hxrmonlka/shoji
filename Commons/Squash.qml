import QtQuick
import qs.Commons

Item {
    id: root

    property bool pressed: false
    property real amount: 0.1
    property real rebound: 0.4
    readonly property real xScale: 1 + amount * spring.value
    readonly property real yScale: 1 - amount * spring.value

    visible: false

    onPressedChanged: {
        if (pressed) {
            release.stop();
            spring.target = 1;
        } else {
            spring.target = -rebound;
            release.restart();
        }
    }

    Timer {
        id: release

        interval: 70
        onTriggered: spring.target = 0
    }

    Spring {
        id: spring

        token: root.pressed ? Motion.effectsFast : Motion.impact
        epsilon: 0.002
    }
}
