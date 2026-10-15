import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: root

    property date selected: new Date()

    Keys.onEscapePressed: ShellState.expanded = false

    RowLayout {
        anchors.fill: parent
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 300
            Layout.fillHeight: true
            radius: 20
            color: "transparent"
            border.width: 1
            border.color: Theme.m3OutlineVariant

            TodoList {
                anchors.fill: parent
                anchors.margins: 16
                day: root.selected
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 20
            color: "transparent"
            border.width: 1
            border.color: Theme.m3OutlineVariant

            Calendar {
                anchors.fill: parent
                anchors.margins: 16
                selected: root.selected
                onDaySelected: picked => root.selected = picked
            }
        }
    }
}
