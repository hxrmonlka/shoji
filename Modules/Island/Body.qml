import QtQuick
import qs.Commons

Item {
    id: root

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

    Loader {
        anchors.top: bar.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        active: root.visible
        sourceComponent: ({ calendar: calendarTab, launcher: launcherTab })[ShellState.tab] ?? null
    }

    Component {
        id: calendarTab

        CalendarTab {}
    }

    Component {
        id: launcherTab

        LauncherTab {}
    }
}
