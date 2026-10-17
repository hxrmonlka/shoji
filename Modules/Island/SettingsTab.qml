import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: root

    readonly property var groups: [
        { id: "island", title: "Island" },
        { id: "circles", title: "Circles" },
        { id: "display", title: "Display" }
    ]

    function rows(group) {
        return Settings.schema.filter(e => e.group === group);
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(left.implicitHeight, right.implicitHeight) + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: left

            x: 0
            y: 4
            width: (flick.width - 24) / 2
            spacing: 8

            Repeater {
                model: [root.groups[0]]

                ColumnLayout {
                    id: block

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: block.modelData.title
                        color: Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: root.rows(block.modelData.id)

                        SettingRow {
                            required property var modelData

                            Layout.fillWidth: true
                            entry: modelData
                        }
                    }
                }
            }
        }

        ColumnLayout {
            id: right

            x: left.width + 24
            y: 4
            width: left.width
            spacing: 8

            Repeater {
                model: [root.groups[1], root.groups[2]]

                ColumnLayout {
                    id: block2

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: block2.modelData.title
                        color: Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: root.rows(block2.modelData.id)

                        SettingRow {
                            required property var modelData

                            Layout.fillWidth: true
                            entry: modelData
                        }
                    }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignLeft
                Layout.topMargin: 4
                implicitWidth: resetText.implicitWidth + 28
                implicitHeight: 32
                radius: 16
                color: resetFill.color

                ColorSpring {
                    id: resetFill

                    target: resetArea.containsMouse ? Theme.m3SurfaceContainerHighest : Theme.m3SurfaceContainerHigh
                }

                Text {
                    id: resetText

                    anchors.centerIn: parent
                    text: "Reset to defaults"
                    color: Theme.m3OnSurface
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: resetArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Settings.reset()
                }
            }
        }
    }

    component SettingRow: RowLayout {
        id: row

        required property var entry

        spacing: 10

        Text {
            Layout.preferredWidth: 112
            text: row.entry.label
            elide: Text.ElideRight
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 12
        }

        ValueSlider {
            id: slider

            Layout.fillWidth: true
            from: row.entry.min
            to: row.entry.max
            step: row.entry.step
            value: Settings.get(row.entry.key)
            onCommitted: v => Settings.set(row.entry.key, v)
        }

        Text {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: Math.round(slider.shown)
            color: Theme.m3OnSurface
            font.family: Theme.fontUi
            font.pixelSize: 12
        }
    }
}
