pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"
    readonly property string cachePath: cacheHome + "/shoji/schemes.json"
    readonly property string script: Quickshell.shellPath("scripts/schemes.sh")

    readonly property var schemes: [
        { value: "scheme-tonal-spot", label: "Tonal Spot", desc: "Balanced palette with focused accents. The default." },
        { value: "scheme-vibrant", label: "Vibrant", desc: "Lively palette with saturated accents." },
        { value: "scheme-content", label: "Content", desc: "Colors that stay close to the wallpaper." },
        { value: "scheme-expressive", label: "Expressive", desc: "Vibrant palette with playful saturation." },
        { value: "scheme-fidelity", label: "Fidelity", desc: "Keeps the hue of the source color." },
        { value: "scheme-fruit-salad", label: "Fruit Salad", desc: "Bright accents with strong contrast." },
        { value: "scheme-monochrome", label: "Monochrome", desc: "Minimal palette built around one hue." },
        { value: "scheme-neutral", label: "Neutral", desc: "Muted palette with subdued tones." },
        { value: "scheme-rainbow", label: "Rainbow", desc: "Diverse palette across the spectrum." }
    ]
    readonly property var values: schemes.map(e => e.value)

    readonly property string scheme: Settings.themeScheme
    readonly property string mode: Settings.themeMode
    readonly property string seed: Theme.m3SourceColor
    readonly property string source: seed.length > 0 ? seed : fallback
    readonly property string signature: scheme + "|" + mode
    readonly property string previewKey: source + "|" + mode
    readonly property bool ready: loadedKey === previewKey || failed
    readonly property bool busy: gen.running

    property string fallback: ""
    property var previews: ({})
    property string loadedKey: ""
    property string runKey: ""
    property bool failed: false
    property bool queued: false

    function entry(value) {
        for (let i = 0; i < schemes.length; i++) {
            if (schemes[i].value === value)
                return schemes[i];
        }
        return schemes[0];
    }

    function label(value) {
        return entry(value).label;
    }

    function description(value) {
        return entry(value).desc;
    }

    function preview(value) {
        const p = previews[value];
        return p === undefined ? null : p;
    }

    function setScheme(value) {
        if (values.indexOf(value) < 0)
            return false;
        return Settings.set("themeScheme", value);
    }

    function setMode(value) {
        if (value !== "dark" && value !== "light")
            return false;
        return Settings.set("themeMode", value);
    }

    function refresh() {
        if (ready || source.length === 0)
            return;
        if (gen.running) {
            queued = true;
            return;
        }
        failed = false;
        runKey = previewKey;
        gen.exec(["sh", script, source, mode]);
    }

    function retry() {
        failed = false;
        loadedKey = "";
        refresh();
    }

    function parse(raw) {
        if (runKey !== previewKey) {
            queued = true;
            return;
        }
        const next = Object.assign({}, previews);
        let found = 0;
        String(raw).split("\n").forEach(line => {
            const t = line.trim();
            if (!t.startsWith("{"))
                return;
            let o;
            try {
                o = JSON.parse(t);
            } catch (e) {
                return;
            }
            if (!o || typeof o.value !== "string" || typeof o.primary !== "string")
                return;
            next[o.value] = {
                primary: o.primary,
                secondary: typeof o.secondary === "string" ? o.secondary : o.primary,
                tertiary: typeof o.tertiary === "string" ? o.tertiary : o.primary
            };
            found++;
        });
        if (found === 0) {
            failed = true;
            return;
        }
        previews = next;
        loadedKey = runKey;
        if (found === schemes.length)
            store.setText(JSON.stringify({ key: runKey, items: next }, null, 1) + "\n");
    }

    function restore(raw) {
        let data;
        try {
            data = JSON.parse(raw);
        } catch (e) {
            return;
        }
        if (!data || typeof data !== "object" || data.key !== previewKey || !data.items)
            return;
        previews = data.items;
        loadedKey = data.key;
    }

    onPreviewKeyChanged: {
        loadedKey = "";
        failed = false;
    }

    readonly property Process gen: Process {
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }

        onExited: (code, status) => {
            if (code !== 0 && root.runKey === root.previewKey && root.loadedKey !== root.runKey)
                root.failed = true;
            if (root.queued) {
                root.queued = false;
                root.refresh();
            }
        }
    }

    readonly property FileView store: FileView {
        path: root.cachePath
        atomicWrites: true
        printErrors: false
        onLoaded: root.restore(text())
    }
}
