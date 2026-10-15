import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Island
import qs.Modules.Spotlight

ShellRoot {
    Variants {
        model: Quickshell.screens

        Island {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens.slice(0, 1)

        Spotlight {
            required property var modelData
            screen: modelData
        }
    }

    IpcHandler {
        target: "spotlight"

        function toggle(): void {
            ShellState.spotlight = !ShellState.spotlight;
        }

        function open(): void {
            ShellState.spotlight = true;
        }

        function close(): void {
            ShellState.spotlight = false;
        }
    }

    IpcHandler {
        target: "island"

        function toggle(): void {
            ShellState.expanded = !ShellState.expanded;
        }

        function open(): void {
            ShellState.expanded = true;
        }

        function close(): void {
            ShellState.expanded = false;
        }

        function tab(name: string): void {
            if (ShellState.tabs.some(t => t.id === name)) {
                ShellState.tab = name;
                ShellState.expanded = true;
            }
        }
    }
}
