import QtQuick
import qs.Commons

Item {
    id: root

    readonly property var warm: ({ launcher: 1500, wallpapers: 3000 })
    property int curIdx: ShellState.tabs.findIndex(t => t.id === ShellState.tab)
    property int prevIdx: curIdx

    Connections {
        target: ShellState

        function onTabChanged() {
            root.prevIdx = root.curIdx;
            root.curIdx = ShellState.tabs.findIndex(t => t.id === ShellState.tab);
        }
    }

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
                required property int index
                readonly property bool current: ShellState.tab === modelData.id
                readonly property int warmDelay: root.warm[modelData.id] ?? 0
                readonly property int side: current ? (root.prevIdx < index ? 1 : -1) : (index < root.curIdx ? -1 : 1)
                readonly property real shift: (1 - Motion.clamp01(presence.value)) * side * 28
                property bool kept: false

                anchors.fill: parent
                anchors.leftMargin: shift
                anchors.rightMargin: -shift
                opacity: Motion.clamp01(presence.value)
                active: kept || current || presence.value > 0.001
                visible: current || presence.value > 0.001
                sourceComponent: ({ calendar: calendarTab, launcher: launcherTab, monitor: monitorTab, wallpapers: wallpaperTab, clipboard: clipboardTab, color: colorTab })[modelData.id] ?? null
                onLoaded: if (warmDelay > 0 || modelData.keep) kept = true

                Spring {
                    id: presence

                    target: slot.current ? 1 : 0
                    token: Motion.effectsDefault
                    epsilon: 0.002
                }

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
        id: monitorTab

        MonitorTab {}
    }

    Component {
        id: wallpaperTab

        WallpaperTab {}
    }

    Component {
        id: clipboardTab

        ClipboardTab {}
    }

    Component {
        id: colorTab

        ColorTab {}
    }
}
