pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string script: 'if command -v fd >/dev/null 2>&1; then exec fd -F -i -t f -t d --max-results 60 --color never -- "$1" "$2"; else exec find "$2" -maxdepth 5 -not -path "*/.*" -iname "*$1*" \\( -type d -printf "%p/\\n" -o -type f -printf "%p\\n" \\); fi'

    property string query: ""
    property var results: []
    property var buffer: []
    property bool dirty: false
    readonly property bool running: proc.running || debounce.running

    function search(text) {
        query = text.trim();
        if (query.length < 2) {
            debounce.stop();
            dirty = false;
            results = [];
            return;
        }
        debounce.restart();
    }

    function request() {
        if (proc.running) {
            dirty = true;
            return;
        }
        run();
    }

    function run() {
        buffer = [];
        proc.exec(["sh", "-c", script, "shoji-files", query, Quickshell.env("HOME")]);
    }

    function rank(paths, q) {
        const needle = q.toLowerCase();
        return paths.map(p => {
            const isDir = p.endsWith("/");
            const clean = isDir ? p.slice(0, -1) : p;
            const name = clean.substring(clean.lastIndexOf("/") + 1);
            const lower = name.toLowerCase();
            return { path: clean, name: name, dir: isDir, rank: lower === needle ? 0 : lower.startsWith(needle) ? 1 : 2 };
        }).sort((a, b) => (a.rank - b.rank) || (a.path.length - b.path.length)).slice(0, 8);
    }

    readonly property Timer debounce: Timer {
        interval: 180
        onTriggered: root.request()
    }

    readonly property Process proc: Process {
        stdout: SplitParser {
            onRead: line => root.buffer.push(line)
        }
        onExited: {
            if (root.dirty) {
                root.dirty = false;
                root.run();
            } else {
                root.results = root.query.length < 2 ? [] : root.rank(root.buffer, root.query);
            }
        }
    }
}
