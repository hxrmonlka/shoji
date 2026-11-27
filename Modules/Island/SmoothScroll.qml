import QtQuick
import qs.Commons

Item {
    id: root

    required property Flickable view
    property real contentSize: 0
    property real step: 130
    property real touchpadScale: 1.4
    property real maxStretch: 84
    readonly property real maxY: Math.max(0, contentSize - view.height)
    property real goal: 0
    property real pull: 0
    readonly property real stretch: rubber(pull)

    function rubber(p) {
        const r = (1 - 1 / (Math.abs(p) * 0.55 / maxStretch + 1)) * maxStretch;
        return p < 0 ? -r : r;
    }

    function clampGoal(y) {
        return Math.max(0, Math.min(maxY, y));
    }

    function scrollTo(y) {
        goal = clampGoal(y);
    }

    function reveal(top, size) {
        if (top < goal)
            goal = clampGoal(top);
        else if (top + size > goal + view.height)
            goal = clampGoal(top + size - view.height);
    }

    function reset() {
        goal = 0;
        pull = 0;
        scroll.value = 0;
        scroll.velocity = 0;
        band.value = 0;
        band.velocity = 0;
    }

    function scrollBy(dy) {
        if (contentSize <= view.height + 0.5)
            return;
        let d = dy;
        if (pull !== 0) {
            const next = pull + d;
            if (pull * next > 0) {
                pull = next;
                rest.restart();
                return;
            }
            d = next;
            pull = 0;
        }
        const target = goal + d;
        if (target < 0) {
            pull = Math.max(-600, target);
            goal = 0;
        } else if (target > maxY) {
            pull = Math.min(600, target - maxY);
            goal = maxY;
        } else {
            goal = target;
        }
        if (pull !== 0)
            rest.restart();
    }

    onMaxYChanged: if (goal > maxY) goal = maxY

    Timer {
        id: rest

        interval: 120
        onTriggered: root.pull = 0
    }

    Spring {
        id: scroll

        target: root.goal
        token: Motion.effectsDefault
        epsilon: 0.1
    }

    Spring {
        id: band

        target: root.stretch
        token: root.pull !== 0 ? Motion.effectsFast : Motion.spatialDefault
        epsilon: 0.1
    }

    Binding {
        target: root.view
        property: "contentY"
        value: scroll.value + band.value
        restoreMode: Binding.RestoreNone
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const dy = event.pixelDelta.y !== 0 ? -event.pixelDelta.y * root.touchpadScale : -event.angleDelta.y / 120 * root.step;
            root.scrollBy(dy);
            event.accepted = true;
        }
    }
}
