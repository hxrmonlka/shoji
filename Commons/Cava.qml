pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property int bars: 40
    readonly property bool wanted: Media.available && Settings.visualizer
    readonly property string path: Quickshell.env("HOME") + "/.local/state/shoji/cava.conf"
    readonly property string config: "[general]\nbars = " + bars + "\nframerate = 60\n\n[input]\nmethod = pipewire\nsource = auto\n\n[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\nascii_max_range = 100\nbar_delimiter = 59\nframe_delimiter = 10\n\n[smoothing]\nnoise_reduction = 70\n"

    property bool ready: false
    property var values: new Array(bars).fill(0)

    function parse(line) {
        if (!ShellState.media)
            return;
        const parts = line.split(";");
        const out = new Array(bars);
        for (let i = 0; i < bars; i++)
            out[i] = Math.min(1, (parseInt(parts[i]) || 0) / 100);
        values = out;
    }

    onWantedChanged: {
        if (!wanted)
            values = new Array(bars).fill(0);
    }

    Component.onCompleted: file.setText(config)

    readonly property FileView file: FileView {
        path: root.path
        atomicWrites: true
        printErrors: false
        onSaved: root.ready = true
    }

    readonly property Process proc: Process {
        command: ["cava", "-p", root.path]
        running: root.ready && root.wanted
        stdout: SplitParser {
            onRead: line => root.parse(line)
        }
    }
}
