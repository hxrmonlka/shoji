pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/Pictures/Wallpapers"
    readonly property string stateDir: home + "/.local/state/shoji"
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"
    readonly property string thumbDir: cacheHome + "/shoji/thumbs"
    readonly property int count: folder.count
    readonly property string script: 'cfg="$HOME/.config/matugen/config.toml"; if grep -qs "templates.shoji" "$cfg"; then exec matugen image "$1" --mode dark --source-color-index 0; else exec matugen image "$1" --mode dark --source-color-index 0 --config "$2"; fi'

    property string current: ""
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

    function apply(path) {
        if (!path)
            return;
        current = path;
        store.setText(JSON.stringify({ path: path }));
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
                root.current = JSON.parse(text()).path || "";
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
