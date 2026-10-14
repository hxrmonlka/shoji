import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
    id: root

    property date shown: new Date(State.clock.date.getFullYear(), State.clock.date.getMonth(), 1)
    readonly property date firstOfMonth: new Date(shown.getFullYear(), shown.getMonth(), 1)
    readonly property int offset: (firstOfMonth.getDay() + 6) % 7

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
            color: Theme.onSurface
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
                color: navArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

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
                    color: Theme.onSurfaceVariant
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

        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

            Text {
                required property string modelData

                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Theme.onSurfaceVariant
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
                readonly property bool isToday: day.toDateString() === State.clock.date.toDateString()

                Layout.fillWidth: true
                Layout.preferredHeight: 40

                Rectangle {
                    anchors.centerIn: parent
                    width: 36
                    height: 36
                    radius: 18
                    color: cell.isToday ? Theme.primary : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: cell.day.getDate()
                    color: cell.isToday ? Theme.onPrimary : cell.inMonth ? Theme.onSurface : Theme.outlineVariant
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                }
            }
        }
    }
}
