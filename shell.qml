import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Island

ShellRoot {
    Variants {
        model: Quickshell.screens

        Island {
            required property var modelData
            screen: modelData
        }
    }

    IpcHandler {
        target: "island"

        function toggle(): void {
            State.expanded = !State.expanded;
        }

        function open(): void {
            State.expanded = true;
        }

        function close(): void {
            State.expanded = false;
        }
    }
}
