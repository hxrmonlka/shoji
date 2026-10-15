import QtQuick
import qs.Commons

Item {
    id: root

    visible: false
    property real target: 0
    property var token: Motion.spatialDefault
    property real value: 0
    property real velocity: 0
    property real epsilon: 0.001
    readonly property bool running: frames.running

    function kick() {
        frames.running = true;
    }

    function advance(dt) {
        const w = Math.sqrt(token.stiffness);
        const z = Math.min(token.damping, 1);
        const y0 = value - target;
        const v0 = velocity;
        const e = Math.exp(-z * w * dt);
        let y;
        let v;
        if (z < 1) {
            const wd = w * Math.sqrt(1 - z * z);
            const c = Math.cos(wd * dt);
            const s = Math.sin(wd * dt);
            y = e * (y0 * c + ((v0 + z * w * y0) / wd) * s);
            v = e * (v0 * c - ((z * w * v0 + w * w * y0) / wd) * s);
        } else {
            const b = v0 + w * y0;
            y = e * (y0 + b * dt);
            v = e * (v0 - w * b * dt);
        }
        if (Math.abs(y) < epsilon && Math.abs(v) < epsilon * 4) {
            value = target;
            velocity = 0;
            return false;
        }
        value = target + y;
        velocity = v;
        return true;
    }

    Component.onCompleted: value = target

    onTargetChanged: kick()

    FrameAnimation {
        id: frames

        onTriggered: {
            if (!root.advance(Math.min(frameTime, 0.1)))
                running = false;
        }
    }
}
