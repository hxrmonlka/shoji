pragma Singleton

import QtQuick

QtObject {
    readonly property var spatialFast: ({ stiffness: 800, damping: 0.6 })
    readonly property var spatialDefault: ({ stiffness: 380, damping: 0.8 })
    readonly property var spatialSlow: ({ stiffness: 200, damping: 0.8 })
    readonly property var effectsFast: ({ stiffness: 3800, damping: 1 })
    readonly property var effectsDefault: ({ stiffness: 1600, damping: 1 })
    readonly property var effectsSlow: ({ stiffness: 800, damping: 1 })

    function clamp01(x) {
        return Math.max(0, Math.min(1, x));
    }

    function lerp(a, b, t) {
        return a + (b - a) * t;
    }

    function mix(a, b, t) {
        const from = a.a === 0 ? Qt.rgba(b.r, b.g, b.b, 0) : a;
        const to = b.a === 0 ? Qt.rgba(a.r, a.g, a.b, 0) : b;
        return Qt.rgba(lerp(from.r, to.r, t), lerp(from.g, to.g, t), lerp(from.b, to.b, t), lerp(from.a, to.a, t));
    }
}
