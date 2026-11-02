pragma Singleton

import QtQuick
import Quickshell.Services.Pipewire

QtObject {
    id: root

    readonly property var nodes: Pipewire.nodes.values
    readonly property int count: nodes.filter(n => root.isScreenConsumer(n)).length
    readonly property bool sharing: count > 0

    function isCamera(node): bool {
        const p = node.properties;
        return p["media.role"] === "Camera" || p["device.api"] === "v4l2" || p["device.api"] === "libcamera" || p["api.v4l2.path"] !== undefined;
    }

    function isScreenConsumer(node): bool {
        if (!node.ready || node.properties["media.class"] !== "Stream/Input/Video")
            return false;
        return Pipewire.links.values.some(l => l.target === node && l.source && !root.isCamera(l.source));
    }

    readonly property PwObjectTracker tracker: PwObjectTracker {
        objects: root.nodes
    }
}
