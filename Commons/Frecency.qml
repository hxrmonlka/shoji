pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.local/state/shoji/frecency.json"
    readonly property real halfLifeDays: 14
    readonly property real minScore: 0.25
    readonly property real pruneScore: 0.05
    readonly property int topCount: 12

    property var entries: ({})
    property bool loaded: false

    function decayed(entry, now) {
        const days = Math.max(0, (now - entry.t) / 86400000);
        return entry.s * Math.pow(0.5, days / halfLifeDays);
    }

    function score(id) {
        const e = entries[id];
        return e ? decayed(e, Date.now()) : 0;
    }

    function record(id) {
        if (!Settings.spotlightFrecency || typeof id !== "string" || id.length === 0)
            return;
        const now = Date.now();
        const next = {};
        Object.keys(entries).forEach(k => {
            if (decayed(entries[k], now) >= pruneScore)
                next[k] = entries[k];
        });
        next[id] = { s: score(id) + 1, t: now };
        entries = next;
        saver.restart();
    }

    function restore(raw) {
        const next = {};
        try {
            const data = JSON.parse(raw);
            if (data !== null && typeof data === "object" && !Array.isArray(data)) {
                Object.keys(data).forEach(k => {
                    const e = data[k];
                    if (e && typeof e.s === "number" && isFinite(e.s) && typeof e.t === "number" && isFinite(e.t))
                        next[k] = { s: e.s, t: e.t };
                });
            }
        } catch (e) {
        }
        entries = next;
        loaded = true;
    }

    readonly property Timer saver: Timer {
        interval: 500
        onTriggered: file.setText(JSON.stringify(root.entries) + "\n")
    }

    readonly property FileView file: FileView {
        path: root.path
        atomicWrites: true
        printErrors: false
        onLoaded: root.restore(text())
        onLoadFailed: root.loaded = true
    }
}
