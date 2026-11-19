pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property int bars: 6
    readonly property bool wanted: Settings.mergeCircles && Settings.visualizer && Media.playing
    readonly property string path: Quickshell.env("HOME") + "/.local/state/shoji/cava-pill.conf"
    readonly property string config: "[general]\nbars = 6\nframerate = 25\nautosens = 0\nsensitivity = 45\nsleep_timer = 3\nlower_cutoff_freq = 50\nhigher_cutoff_freq = 12000\n\n[input]\nmethod = pipewire\nsource = auto\n\n[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\nchannels = mono\nmono_option = average\n\n[smoothing]\nnoise_reduction = 35\nintegral = 90\ngravity = 95\nignore = 2\nmonstercat = 1.5\n"

    property bool ready: false
    property var values: new Array(bars).fill(0)

    function level(x) {
        if (!(x > 0))
            return 0;
        if (x >= 100)
            return 1;
        return Math.round(Math.sqrt(x * 0.01) * 32) / 32;
    }

    function parse(line) {
        if (!wanted || line.length === 0)
            return;
        const parts = line.split(";");
        if (parts.length < bars)
            return;
        const out = new Array(bars);
        let changed = false;
        for (let i = 0; i < bars; i++) {
            out[i] = level(parseInt(parts[i], 10));
            if (out[i] !== values[i])
                changed = true;
        }
        if (changed)
            values = out;
    }

    onWantedChanged: {
        if (wanted) {
            linger.stop();
            return;
        }
        values = new Array(bars).fill(0);
        if (proc.running)
            linger.restart();
    }

    Component.onCompleted: file.setText(config)

    readonly property Timer linger: Timer {
        interval: 4000
    }

    readonly property FileView file: FileView {
        path: root.path
        atomicWrites: true
        printErrors: false
        onSaved: root.ready = true
    }

    readonly property Process proc: Process {
        command: ["cava", "-p", root.path]
        running: root.ready && (root.wanted || root.linger.running)
        environment: ({
                "PIPEWIRE_LATENCY": "2400/48000",
                "PULSE_LATENCY_MSEC": "50"
            })
        onRunningChanged: {
            if (!running)
                root.values = new Array(root.bars).fill(0);
        }
        stdout: SplitParser {
            onRead: line => root.parse(line)
        }
    }
}
