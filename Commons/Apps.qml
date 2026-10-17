pragma Singleton

import QtQuick
import Quickshell

QtObject {
    id: root

    readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay).sort((a, b) => a.name.localeCompare(b.name))

    property var iconCache: ({})
    property int warmIndex: 0

    function iconSource(name) {
        let p = iconCache[name];
        if (p === undefined) {
            p = Quickshell.iconPath(name, true);
            iconCache[name] = p;
        }
        return p;
    }

    function warm() {
        warmIndex = 0;
        warmer.running = true;
    }

    onAllChanged: warm()

    readonly property Timer warmer: Timer {
        interval: 16
        repeat: true

        onTriggered: {
            const list = root.all;
            let i = root.warmIndex;
            const end = Math.min(i + 8, list.length);
            for (; i < end; i++) {
                if (list[i].icon)
                    root.iconSource(list[i].icon);
            }
            root.warmIndex = i;
            if (i >= list.length)
                running = false;
        }
    }

    function isSetting(entry) {
        return Array.from(entry.categories || []).indexOf("Settings") !== -1;
    }

    function score(entry, q) {
        const name = entry.name.toLowerCase();
        if (name === q)
            return 120;
        if (name.startsWith(q))
            return 100;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q)))
            return 80;
        if (name.includes(q))
            return 60;
        const extra = [entry.genericName, entry.comment].concat(Array.from(entry.keywords || [])).join(" ").toLowerCase();
        return extra.includes(q) ? 30 : 0;
    }

    function find(query, settings, limit) {
        const q = query.trim().toLowerCase();
        if (q.length === 0)
            return [];
        return all.filter(e => root.isSetting(e) === settings).map(e => ({ entry: e, score: root.score(e, q) })).filter(r => r.score > 0).sort((a, b) => (b.score - a.score) || (a.entry.name.length - b.entry.name.length)).slice(0, limit).map(r => r.entry);
    }
}
