pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string faceFile: Quickshell.env("HOME") + "/.face"
    property string iconFile: ""

    function refresh(): void {
        if (!query.running)
            query.running = true;
    }

    function parse(text: string): void {
        const m = text.match(/"((?:[^"\\]|\\.)*)"/);
        iconFile = m ? m[1] : "";
    }

    readonly property Process query: Process {
        command: ["sh", "-c", "busctl --system get-property org.freedesktop.Accounts /org/freedesktop/Accounts/User$(id -u) org.freedesktop.Accounts.User IconFile"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }
}
