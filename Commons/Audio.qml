pragma Singleton

import QtQuick
import Quickshell.Services.Pipewire

QtObject {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready && sink.audio.muted
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && n.audio)

    function setVolume(v) {
        if (ready)
            sink.audio.volume = Motion.clamp01(v);
    }

    function toggleMute() {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }

    function streamName(node) {
        const p = node.properties;
        return p["application.name"] || node.description || node.name || "Unknown";
    }

    function setStreamVolume(node, v) {
        node.audio.volume = Motion.clamp01(v);
    }

    function toggleStreamMute(node) {
        node.audio.muted = !node.audio.muted;
    }

    function icon() {
        if (muted || volume <= 0)
            return "\uf026";
        return volume < 0.5 ? "\uf027" : "\uf028";
    }

    readonly property PwObjectTracker tracker: PwObjectTracker {
        objects: root.sink ? [root.sink].concat(root.streams) : root.streams
    }
}
