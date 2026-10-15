import QtQuick
import qs.Commons

Item {
    id: root

    visible: false
    property bool ready: false
    property color target: "transparent"
    property var token: Motion.effectsFast
    property color from: target
    property color previous: target
    readonly property color color: Motion.mix(from, target, progress.value)

    Component.onCompleted: {
        from = target;
        previous = target;
        ready = true;
    }

    onTargetChanged: {
        if (!ready)
            return;
        from = Motion.mix(from, previous, progress.value);
        previous = target;
        progress.value = 0;
        progress.velocity = 0;
        progress.kick();
    }

    Spring {
        id: progress

        target: 1
        value: 1
        token: root.token
        epsilon: 0.002
    }
}
