import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
    id: root

    property date selected: new Date()
    property date shown: new Date(ShellState.clock.date.getFullYear(), ShellState.clock.date.getMonth(), 1)
    readonly property date firstOfMonth: new Date(shown.getFullYear(), shown.getMonth(), 1)
    readonly property int offset: (firstOfMonth.getDay() + 6) % 7

    signal daySelected(date picked)

    function shift(months) {
        shown = new Date(shown.getFullYear(), shown.getMonth() + months, 1);
    }

    function cellDate(index) {
        return new Date(shown.getFullYear(), shown.getMonth(), 1 - offset + index);
    }

    spacing: 10

    RowLayout {
        Layout.fillWidth: true

        Text {
            Layout.fillWidth: true
            text: Qt.formatDate(root.shown, "MMMM yyyy")
            color: Theme.m3OnSurface
            font.family: Theme.fontUi
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }

        Repeater {
            model: [{ glyph: "\uf104", step: -1 }, { glyph: "\uf105", step: 1 }]

            Rectangle {
                id: nav

                required property var modelData

                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 16
                color: navArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Motion.short3
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.standard
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: nav.modelData.glyph
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontIcon
                    font.pixelSize: 16
                }

                MouseArea {
                    id: navArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.shift(nav.modelData.step)
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 4
        columnSpacing: 0
        uniformCellWidths: true

        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

            Text {
                required property string modelData

                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
        }

        Repeater {
            model: 42

            Item {
                id: cell

                required property int index
                readonly property date day: root.cellDate(index)
                readonly property bool inMonth: day.getMonth() === root.shown.getMonth()
                readonly property bool isToday: Todos.key(day) === Todos.key(ShellState.clock.date)
                readonly property bool isSelected: Todos.key(day) === Todos.key(root.selected)

                Layout.fillWidth: true
                Layout.preferredHeight: 40

                Rectangle {
                    anchors.centerIn: parent
                    width: 36
                    height: 36
                    radius: 18
                    color: cell.isToday ? Theme.m3Primary : cellArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
                    border.width: cell.isSelected && !cell.isToday ? 2 : 0
                    border.color: Theme.m3Primary

                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.short3
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.standard
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: Todos.hasAny(cell.day) ? -2 : 0
                    text: cell.day.getDate()
                    color: cell.isToday ? Theme.m3OnPrimary : cell.inMonth ? Theme.m3OnSurface : Theme.m3OutlineVariant
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: cell.isToday || cell.isSelected ? Font.DemiBold : Font.Normal
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 11
                    width: 4
                    height: 4
                    radius: 2
                    visible: Todos.hasAny(cell.day)
                    color: Todos.hasOpen(cell.day) ? (cell.isToday ? Theme.m3OnPrimary : Theme.m3Primary) : Theme.m3OutlineVariant
                }

                MouseArea {
                    id: cellArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.shown = new Date(cell.day.getFullYear(), cell.day.getMonth(), 1);
                        root.daySelected(cell.day);
                    }
                }
            }
        }
    }
}
