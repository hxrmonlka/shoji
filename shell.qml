import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Island
import qs.Modules.Lock
import qs.Modules.Screenshot
import qs.Modules.Spotlight
import qs.Modules.Wallpaper

ShellRoot {
    Component.onCompleted: {
        Apps.warm();
        Brightness.refresh();
        Notifs.hidePopup();
        ClipboardHistory.start();
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: scope

            required property var modelData

            Backdrop {
                screen: scope.modelData
            }

            Island {
                screen: scope.modelData
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Wallpaper {
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

    Lock {}

    Variants {
        model: Quickshell.screens

        RegionSelector {}
    }

    IpcHandler {
        target: "screenshot"

        function fullscreen(): void {
            Screenshot.fullscreen("");
        }

        function output(name: string): void {
            Screenshot.fullscreen(name);
        }

        function window(): void {
            Screenshot.window();
        }

        function region(): void {
            Screenshot.region();
        }
    }

    IpcHandler {
        target: "lock"

        function activate(): void {
            LockState.lock();
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
        target: "wallpaper"

        function set(path: string): void {
            Wallpapers.apply(path);
        }

        function next(): void {
            Wallpapers.cycle(1);
        }

        function previous(): void {
            Wallpapers.cycle(-1);
        }

        function random(): void {
            Wallpapers.random();
        }
    }

    IpcHandler {
        target: "media"

        function toggle(): void {
            ShellState.media = !ShellState.media;
            ShellState.pin();
        }

        function open(): void {
            ShellState.media = true;
            ShellState.pin();
        }

        function close(): void {
            ShellState.media = false;
        }

        function playPause(): void {
            if (Media.player)
                Media.player.togglePlaying();
        }

        function next(): void {
            if (Media.player)
                Media.player.next();
        }

        function previous(): void {
            if (Media.player)
                Media.player.previous();
        }
    }

    IpcHandler {
        target: "control"

        function toggle(): void {
            ShellState.control = !ShellState.control;
            ShellState.pin();
        }

        function open(): void {
            ShellState.control = true;
            ShellState.pin();
        }

        function close(): void {
            ShellState.control = false;
        }
    }

    IpcHandler {
        target: "power"

        function toggle(): void {
            ShellState.power = !ShellState.power;
        }

        function open(): void {
            ShellState.power = true;
        }

        function close(): void {
            ShellState.power = false;
        }
    }

    IpcHandler {
        target: "notifications"

        function toggleDnd(): void {
            Notifs.toggleDnd();
        }

        function dnd(on: bool): void {
            Notifs.setDnd(on);
        }

        function clear(): void {
            Notifs.clear();
        }

        function hidePopup(): void {
            Notifs.hidePopup();
        }
    }

    IpcHandler {
        target: "osd"

        function volume(steps: int): void {
            ShellState.adjust("volume", steps * 120);
        }

        function brightness(steps: int): void {
            ShellState.adjust("brightness", steps * 120);
        }
    }

    IpcHandler {
        target: "settings"

        function set(key: string, value: string): bool {
            return Settings.set(key, value);
        }

        function get(key: string): string {
            return Settings.defs[key] ? String(Settings.get(key)) : "";
        }

        function reset(): void {
            Settings.reset();
        }

        function reload(): void {
            Settings.reload();
        }
    }

    IpcHandler {
        target: "island"

        function toggle(): void {
            ShellState.expanded = !ShellState.expanded;
            ShellState.pin();
        }

        function open(): void {
            ShellState.expanded = true;
            ShellState.pin();
        }

        function close(): void {
            ShellState.expanded = false;
        }

        function tab(name: string): void {
            if (ShellState.tabs.some(t => t.id === name)) {
                ShellState.tab = name;
                ShellState.expanded = true;
                ShellState.pin();
            }
        }
    }
}
