pragma Singleton

import QtQuick

QtObject {
    id: root

    property var islands: ({})
    property var frames: ({})
    property var shots: ({})
    property bool holding: false
    property int pending: 0
    property int serial: 0

    function register(name, island): void {
        const next = Object.assign({}, islands);
        next[name] = island;
        islands = next;
    }

    function unregister(name, island): void {
        if (islands[name] !== island)
            return;
        const next = Object.assign({}, islands);
        delete next[name];
        islands = next;
    }

    function fallbackFrame() {
        const h = Settings.pillHeight;
        return {
            w: Math.round(h * 5),
            h: h,
            r: h / 2,
            cx: 0,
            top: Settings.topMargin,
            fill: Theme.glass(Theme.m3SurfaceContainer),
            border: Theme.m3OutlineVariant,
            atRest: false,
            fallback: true
        };
    }

    function frameFor(name) {
        return frames[name] ?? fallbackFrame();
    }

    function shotFor(name) {
        return shots[name] ?? null;
    }

    function restFor(name) {
        const island = islands[name];
        return island ? island.restFrame() : fallbackFrame();
    }

    function settle(): void {
        pending = Math.max(0, pending - 1);
        if (pending === 0) {
            holding = false;
            holdTimer.stop();
        }
    }

    function capture(): void {
        const id = ++serial;
        const nextFrames = {};
        for (const name of Object.keys(islands)) {
            const frame = islands[name].captureFrame();
            if (frame)
                nextFrames[name] = frame;
        }
        frames = nextFrames;
        shots = ({});
        pending = 0;
        for (const name of Object.keys(nextFrames)) {
            pending++;
            const started = islands[name].grabCapture(result => {
                if (id !== root.serial)
                    return;
                const next = Object.assign({}, root.shots);
                next[name] = result;
                root.shots = next;
                root.settle();
            });
            if (!started)
                settle();
        }
        holding = pending > 0;
        if (holding)
            holdTimer.restart();
    }

    readonly property Timer holdTimer: Timer {
        interval: 150
        onTriggered: {
            root.pending = 0;
            root.holding = false;
        }
    }
}
