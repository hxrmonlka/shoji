pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property var items: []
    property int nextId: 1

    function key(day) {
        return Qt.formatDate(day, "yyyy-MM-dd");
    }

    function forDate(day) {
        const k = key(day);
        return items.filter(t => t.date === k).sort((a, b) => (Number(a.done) - Number(b.done)) || (a.id - b.id));
    }

    function hasAny(day) {
        const k = key(day);
        return items.some(t => t.date === k);
    }

    function hasOpen(day) {
        const k = key(day);
        return items.some(t => t.date === k && !t.done);
    }

    function add(day, text) {
        const trimmed = text.trim();
        if (trimmed.length === 0)
            return;
        commit(items.concat([{ id: nextId, date: key(day), text: trimmed, done: false }]), nextId + 1);
    }

    function edit(id, text) {
        const trimmed = text.trim();
        if (trimmed.length === 0)
            return;
        commit(items.map(t => t.id === id ? Object.assign({}, t, { text: trimmed }) : t), nextId);
    }

    function toggle(id) {
        commit(items.map(t => t.id === id ? Object.assign({}, t, { done: !t.done }) : t), nextId);
    }

    function remove(id) {
        commit(items.filter(t => t.id !== id), nextId);
    }

    function commit(list, next) {
        items = list;
        nextId = next;
        file.setText(JSON.stringify({ nextId: nextId, items: items }, null, 2));
    }

    function restore(raw) {
        try {
            const data = JSON.parse(raw);
            const list = Array.isArray(data.items) ? data.items : [];
            items = list;
            nextId = list.reduce((m, t) => Math.max(m, t.id + 1), data.nextId || 1);
        } catch (e) {
            items = [];
            nextId = 1;
        }
    }

    readonly property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.local/state/shoji/todos.json"
        atomicWrites: true
        printErrors: false
        onLoaded: root.restore(text())
    }
}
