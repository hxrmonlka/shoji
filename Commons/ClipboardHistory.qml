pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/shoji/clip"
    readonly property var mimes: ({ png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", bmp: "image/bmp", gif: "image/gif", webp: "image/webp" })
    readonly property string decodeScript: 'd="$1"; shift; mkdir -p "$d"; for f; do [ -s "$d/$f" ] || cliphist decode "${f%%.*}" > "$d/$f"; done; find "$d" -type f -mtime +7 -delete'
    readonly property string copyScript: 'if [ -n "$2" ]; then cliphist decode "$1" | wl-copy --type "$2"; else cliphist decode "$1" | wl-copy; fi'
    readonly property string textWatch: 't=$(wl-paste --list-types); case "$t" in *x-kde-passwordManagerHint*|*text/uri-list*) exit 0;; esac; cliphist store; echo c'

    property var entries: []
    property var pending: []
    property var buffer: []
    property bool dirty: false

    function start(): void {
        refresh();
    }

    function parse(lines) {
        const out = [];
        for (const line of lines) {
            const tab = line.indexOf("\t");
            if (tab < 1)
                continue;
            const id = line.substring(0, tab);
            const preview = line.substring(tab + 1);
            const img = /^\[\[ binary data (\S+ \S+) (\w+) (\d+)x(\d+) \]\]$/.exec(preview);
            if (img) {
                const ext = img[2].toLowerCase();
                out.push({ id: id, kind: "image", preview: preview, ext: ext, size: img[1], dims: img[3] + "x" + img[4], path: root.cacheDir + "/" + id + "." + ext });
            } else if (preview.startsWith("file://")) {
                const files = preview.split(/\s+(?=file:\/\/)/).map(u => {
                    let p = u.replace(/^file:\/\//, "");
                    try {
                        p = decodeURIComponent(p);
                    } catch (e) {}
                    return p;
                });
                out.push({ id: id, kind: "files", preview: files.map(f => f.substring(f.lastIndexOf("/") + 1)).join(", "), count: files.length, first: files[0] });
            } else {
                out.push({ id: id, kind: "text", preview: preview });
            }
            if (out.length >= 200)
                break;
        }
        return out;
    }

    function refresh(): void {
        if (listProc.running || decodeProc.running) {
            dirty = true;
            return;
        }
        buffer = [];
        dirty = false;
        listProc.exec(["cliphist", "list"]);
    }

    function schedule(ms: int): void {
        debounce.interval = ms;
        debounce.restart();
    }

    function copy(entry): void {
        const type = entry.kind === "image" ? (mimes[entry.ext] ?? "") : entry.kind === "files" ? "text/uri-list" : "";
        Quickshell.execDetached(["sh", "-c", copyScript, "shoji-clip", entry.id, type]);
        schedule(300);
    }

    function remove(entry): void {
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete; rm -f \"$2\"", "shoji-clip", entry.id, entry.path ?? ""]);
        entries = entries.filter(e => e.id !== entry.id);
        schedule(300);
    }

    function wipe(): void {
        Quickshell.execDetached(["sh", "-c", "cliphist wipe; rm -rf \"$1\"", "shoji-clip", cacheDir]);
        entries = [];
        schedule(300);
    }

    readonly property Timer debounce: Timer {
        interval: 150
        onTriggered: root.refresh()
    }

    readonly property Process listProc: Process {
        stdout: SplitParser {
            onRead: line => root.buffer.push(line)
        }

        onExited: {
            const items = root.parse(root.buffer);
            const images = items.filter(i => i.kind === "image");
            root.pending = items;
            if (images.length > 0) {
                decodeProc.exec(["sh", "-c", root.decodeScript, "shoji-clip", root.cacheDir].concat(images.map(i => i.id + "." + i.ext)));
            } else {
                root.entries = items;
                if (root.dirty)
                    root.refresh();
            }
        }
    }

    readonly property Process decodeProc: Process {
        onExited: {
            root.entries = root.pending;
            if (root.dirty)
                root.refresh();
        }
    }

    readonly property Process watchText: Process {
        command: ["wl-paste", "--type", "text", "--watch", "sh", "-c", root.textWatch]
        running: true
        stdout: SplitParser {
            onRead: root.schedule(150)
        }
    }

    readonly property Process watchImage: Process {
        command: ["wl-paste", "--type", "image", "--watch", "sh", "-c", "cliphist store; echo c"]
        running: true
        stdout: SplitParser {
            onRead: root.schedule(150)
        }
    }

    readonly property Process watchFiles: Process {
        command: ["wl-paste", "--type", "text/uri-list", "--watch", "sh", "-c", "cliphist store; echo c"]
        running: true
        stdout: SplitParser {
            onRead: root.schedule(150)
        }
    }
}
