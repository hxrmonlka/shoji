import QtQuick
import qs.Commons

Item {
    id: root

    readonly property var warm: ({ launcher: 1500, wallpapers: 3000 })

    TabBar {
        id: bar

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        tabs: ShellState.tabs
        current: ShellState.tab
        onPicked: tabId => ShellState.tab = tabId
    }

    Item {
        anchors.top: bar.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 16

        Repeater {
            model: ShellState.tabs

            delegate: Loader {
                id: slot

                required property var modelData
                readonly property bool current: ShellState.tab === modelData.id
                readonly property int warmDelay: root.warm[modelData.id] ?? 0
                property bool kept: false

                anchors.fill: parent
                active: kept || current
                visible: current
                sourceComponent: ({ calendar: calendarTab, launcher: launcherTab, wallpapers: wallpaperTab, settings: settingsTab })[modelData.id] ?? null
                onLoaded: if (warmDelay > 0) kept = true

                Timer {
                    interval: slot.warmDelay
                    running: slot.warmDelay > 0
                    onTriggered: slot.kept = true
                }
            }
        }
    }

    Component {
        id: calendarTab

        CalendarTab {}
    }

    Component {
        id: launcherTab

        LauncherTab {}
    }

    Component {
        id: wallpaperTab

        WallpaperTab {}
    }

    Component {
        id: settingsTab

        SettingsTab {}
    }
}
