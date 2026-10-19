pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string defaultDir: home + "/Pictures/Wallpapers"
    readonly property string dirLabel: dir.startsWith(home) ? "~" + dir.slice(home.length) : dir
    readonly property string chooseScript: 'd="$1"; if command -v zenity >/dev/null 2>&1; then exec zenity --file-selection --directory --title="Wallpaper folder" --filename="$d/"; elif command -v kdialog >/dev/null 2>&1; then exec kdialog --getexistingdirectory "$d"; elif command -v yad >/dev/null 2>&1; then exec yad --file --directory --title="Wallpaper folder" --filename="$d/"; else exit 127; fi'
    readonly property string stateDir: home + "/.local/state/shoji"
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"
    readonly property string thumbDir: cacheHome + "/shoji/thumbs"
    readonly property int count: folder.count
    readonly property string script: 'cfg="$HOME/.config/matugen/config.toml"; if grep -qs "templates.shoji" "$cfg"; then exec matugen image "$1" --mode dark --source-color-index 0; else exec matugen image "$1" --mode dark --source-color-index 0 --config "$2"; fi'

    property string dir: defaultDir
    property string current: ""
    property bool choosing: false
    property bool chooserMissing: false
    property string pending: ""
    property bool dirty: false
    property bool busy: false
    property bool thumbsReady: false
    property bool thumbsAgain: false
    property int thumbsRev: 0

    function thumbUrl(path) {
        const t = thumbDir + "/" + path.replace(/\//g, "+") + ".jpg";
        return "file://" + encodeURI(t).replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    function buildThumbs() {
        if (thumbs.running) {
            thumbsAgain = true;
            return;
        }
        thumbs.exec(["nice", "-n", "15", "sh", Quickshell.shellPath("scripts/thumbs.sh"), dir, thumbDir]);
    }

    function save() {
        store.setText(JSON.stringify({ path: current, dir: dir }));
    }

    function setDir(d) {
        const clean = d.length > 1 ? d.replace(/\/+$/, "") : d;
        if (!clean || clean === dir)
            return;
        dir = clean;
        save();
    }

    function choose() {
        if (chooser.running)
            return;
        choosing = true;
        chooserMissing = false;
        chooser.exec(["sh", "-c", chooseScript, "shoji-choose", dir]);
    }

    function apply(path) {
        if (!path)
            return;
        current = path;
        save();
        pending = path;
        if (matugen.running) {
            dirty = true;
            return;
        }
        launch();
    }

    function launch() {
        busy = true;
        matugen.exec(["sh", "-c", script, "shoji-matugen", pending, stateDir + "/matugen.toml"]);
    }

    function indexOfCurrent() {
        for (let i = 0; i < folder.count; i++) {
            if (folder.get(i, "filePath") === current)
                return i;
        }
        return -1;
    }

    function cycle(step) {
        if (folder.count === 0)
            return;
        const i = indexOfCurrent();
        const next = i < 0 ? 0 : (i + step + folder.count) % folder.count;
        apply(folder.get(next, "filePath"));
    }

    function random() {
        if (folder.count === 0)
            return;
        let i = Math.floor(Math.random() * folder.count);
        if (folder.count > 1 && folder.get(i, "filePath") === current)
            i = (i + 1) % folder.count;
        apply(folder.get(i, "filePath"));
    }

    onDirChanged: thumbDebounce.restart()

    Component.onCompleted: {
        thumbDebounce.start();
        standalone.setText("[config]\n\n[templates.shoji]\ninput_path = '" + Quickshell.shellDir + "/matugen/colors.json'\noutput_path = '" + stateDir + "/colors.json'\n");
    }

    readonly property FolderListModel folder: FolderListModel {
        folder: "file://" + root.dir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp"]
        caseSensitive: false
        showDirs: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        onCountChanged: root.thumbDebounce.restart()
    }

    readonly property Timer thumbDebounce: Timer {
        interval: 600
        onTriggered: root.buildThumbs()
    }

    readonly property Process thumbs: Process {
        onExited: (code, status) => {
            root.thumbsReady = code === 0;
            if (code === 0)
                root.thumbsRev++;
            if (root.thumbsAgain) {
                root.thumbsAgain = false;
                root.buildThumbs();
            }
        }
    }

    readonly property FileView store: FileView {
        path: root.stateDir + "/wallpaper.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                root.current = saved.path || "";
                if (saved.dir)
                    root.dir = saved.dir;
            } catch (e) {
                root.current = "";
            }
        }
    }

    readonly property FileView standalone: FileView {
        path: root.stateDir + "/matugen.toml"
        atomicWrites: true
        printErrors: false
    }

    readonly property Process chooser: Process {
        stdout: StdioCollector {
            onStreamFinished: root.setDir(text.trim())
        }
        onExited: (code, status) => {
            root.choosing = false;
            root.chooserMissing = code === 127;
        }
    }

    readonly property Process matugen: Process {
        onExited: {
            if (root.dirty) {
                root.dirty = false;
                root.launch();
            } else {
                root.busy = false;
            }
        }
    }
}
