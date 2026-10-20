pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

QtObject {
    id: root

    property bool locked: false
    property string password: ""
    property bool busy: false
    property bool failed: false
    property string message: ""

    function lock(): void {
        if (locked)
            return;
        ShellState.hidePanels();
        ShellState.spotlight = false;
        Network.refresh();
        password = "";
        failed = false;
        message = "";
        busy = false;
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
        locked = false;
    }

    function fail(text: string): void {
        password = "";
        busy = false;
        failed = true;
        message = text;
    }

    onPasswordChanged: {
        if (password.length > 0 && failed) {
            failed = false;
            message = "";
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
