pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

QtObject {
    id: root

    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => p.isPlaying) ?? players[0] ?? null
    readonly property bool available: player !== null
    readonly property bool playing: available && player.isPlaying
    readonly property string title: available ? (player.trackTitle || "Unknown title") : ""
    readonly property string artist: available ? player.trackArtist : ""
    readonly property string source: available ? player.identity : ""
    readonly property string artUrl: available ? player.trackArtUrl : ""
    readonly property real length: available && player.lengthSupported ? player.length : 0
    readonly property real position: available ? player.position : 0
    readonly property real progress: length > 0 ? Motion.clamp01(position / length) : 0
    readonly property bool canSeek: available && player.canSeek && player.positionSupported && length > 0

    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && n.audio)
    readonly property var matched: streams.filter(n => root.matches(n))
    readonly property string volumeMode: matched.length > 0 ? "pipewire" : (available && player.volumeSupported ? "mpris" : "none")
    readonly property real volume: volumeMode === "pipewire" ? matched.reduce((s, n) => s + n.audio.volume, 0) / matched.length : volumeMode === "mpris" ? player.volume : 0
    readonly property bool muted: volumeMode === "pipewire" && matched.every(n => n.audio.muted)

    function norm(s) {
        return (s || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function matches(node) {
        if (!available)
            return false;
        const p = node.properties;
        const hay = [p["application.name"], p["application.process.binary"], p["application.id"], p["application.icon-name"]].map(norm).filter(s => s.length > 1);
        const keys = [player.desktopEntry, player.identity].map(norm).filter(s => s.length > 1);
        return keys.some(k => hay.some(h => h.includes(k) || k.includes(h)));
    }

    function setVolume(v) {
        const value = Motion.clamp01(v);
        if (volumeMode === "pipewire")
            matched.forEach(n => n.audio.volume = value);
        else if (volumeMode === "mpris")
            player.volume = value;
    }

    function toggleMute() {
        if (volumeMode !== "pipewire")
            return;
        const next = !muted;
        matched.forEach(n => n.audio.muted = next);
    }

    function seekTo(fraction) {
        if (canSeek)
            player.position = Motion.clamp01(fraction) * length;
    }

    function format(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    readonly property PwObjectTracker tracker: PwObjectTracker {
        objects: root.streams
    }

    readonly property Timer ticker: Timer {
        interval: 500
        repeat: true
        running: root.playing
        onTriggered: root.player.positionChanged()
    }
}
