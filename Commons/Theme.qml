pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string fontUi: "Roboto Flex"
    readonly property string fontIcon: "JetBrainsMono Nerd Font"

    readonly property color m3Primary: file.adapter.primary
    readonly property color m3OnPrimary: file.adapter.on_primary
    readonly property color m3PrimaryContainer: file.adapter.primary_container
    readonly property color m3OnPrimaryContainer: file.adapter.on_primary_container
    readonly property color m3Surface: file.adapter.surface
    readonly property color m3OnSurface: file.adapter.on_surface
    readonly property color m3OnSurfaceVariant: file.adapter.on_surface_variant
    readonly property color m3SurfaceContainer: file.adapter.surface_container
    readonly property color m3SurfaceContainerHigh: file.adapter.surface_container_high
    readonly property color m3SurfaceContainerHighest: file.adapter.surface_container_highest
    readonly property color m3OutlineVariant: file.adapter.outline_variant

    readonly property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.local/state/shoji/colors.json"
        watchChanges: true
        onFileChanged: reload()

        adapter: JsonAdapter {
            property string primary: "#c0c1ff"
            property string on_primary: "#1000a9"
            property string primary_container: "#3f3fc6"
            property string on_primary_container: "#e1e0ff"
            property string surface: "#131318"
            property string on_surface: "#e4e1e9"
            property string on_surface_variant: "#c7c5d0"
            property string surface_container: "#1f1f25"
            property string surface_container_high: "#2a292f"
            property string surface_container_highest: "#35343a"
            property string outline_variant: "#46464f"
        }
    }
}
