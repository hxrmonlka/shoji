pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import "PasswordShapeSequence.js" as PasswordShapeSequence

QtObject {
    id: root

    property bool locked: false
    property bool unlocking: false
    property string password: ""
    property bool busy: false
    property bool failed: false
    property string message: ""
    property int frameShape: 7
    readonly property bool secret: true
    readonly property string prompt: "Enter password"

    readonly property ListModel shapes: ListModel {}
    property var passwordShapeAssignments: []

    function syncShapes(): void {
        const n = password.length;

        if (n === 0) {
            passwordShapeAssignments = [];
            while (shapes.count > 0)
                shapes.remove(shapes.count - 1);
            return;
        }

        const pool = MaterialExpressiveShapes.catalog;
        while (passwordShapeAssignments.length < n) {
            const sequenceIndex = Math.floor(passwordShapeAssignments.length / pool.length);
            const previousLast = passwordShapeAssignments.length > 0
                ? passwordShapeAssignments[passwordShapeAssignments.length - 1]
                : -1;
            const sequence = PasswordShapeSequence.create(
                pool,
                sequenceIndex,
                previousLast,
                Settings.shufflePasswordShapes
            );
            passwordShapeAssignments = passwordShapeAssignments.concat(sequence);
        }

        while (shapes.count > n)
            shapes.remove(shapes.count - 1);
        while (shapes.count < n) {
            const index = shapes.count;
            shapes.append({ shape: passwordShapeAssignments[index] });
        }
    }

    function lock(): void {
        if (locked)
            return;
        ShellState.hidePanels();
        ShellState.spotlight = false;
        Network.refresh();
        const pool = MaterialShapes.frameKinds.filter(k => k !== frameShape);
        frameShape = pool[Math.floor(Math.random() * pool.length)];
        password = "";
        failed = false;
        message = "";
        busy = false;
        unlocking = false;
        locked = true;
    }

    function submit(): void {
        if (!locked || busy || password.length === 0)
            return;
        busy = true;
        failed = false;
        pamCtx.start();
    }

    function finish(): void {
        password = "";
        busy = false;
        failed = false;
        message = "";
        unlocking = true;
        unlockTimer.restart();
    }

    function fail(text: string): void {
        password = "";
        busy = false;
        failed = true;
        message = text;
    }

    onPasswordChanged: {
        syncShapes();
        if (password.length > 0 && failed) {
            failed = false;
            message = "";
        }
    }

    readonly property Timer unlockTimer: Timer {
        interval: 320
        onTriggered: {
            root.unlocking = false;
            root.locked = false;
        }
    }

    readonly property PamContext pamCtx: PamContext {
        config: Settings.lockPamConfig

        onPamMessage: {
            if (responseRequired)
                respond(root.password);
        }

        onCompleted: result => {
            if (result === PamResult.Success)
                root.finish();
            else
                root.fail(result === PamResult.Error ? "Authentication error" : "Incorrect password");
        }
    }

    readonly property Process logind: Process {
        command: ["dbus-monitor", "--system", "type='signal',interface='org.freedesktop.login1.Session',member='Lock'"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (/member=Lock\s*$/.test(line))
                    root.lock();
            }
        }
    }
}
