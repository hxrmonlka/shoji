import QtQuick
import QtQuick.Layouts
import qs.Commons

Flickable {
    id: root

    required property string title
    required property var sections
    property bool resettable: false

    signal resetRequested

    contentWidth: width
    contentHeight: col.implicitHeight + 48
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function scrollTop(): void {
        contentY = 0;
    }

    ColumnLayout {
        id: col

        x: 32
        y: 24
        width: root.width - 64
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Rectangle {
                visible: root.resettable
                implicitWidth: resetText.implicitWidth + 28
                implicitHeight: 34
                radius: 17
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
                    onClicked: root.resetRequested()
                }
            }
        }

        Repeater {
            model: root.sections

            ColumnLayout {
                id: block

                required property var modelData

                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.leftMargin: 8
                    text: block.modelData.title
                    color: Theme.m3Primary
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: rows.implicitHeight
                    radius: 20
                    color: Theme.m3SurfaceContainer

                    ColumnLayout {
                        id: rows

                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 0

                        Repeater {
                            model: block.modelData.items

                            ColumnLayout {
                                id: item

                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                spacing: 0

                                Rectangle {
                                    visible: item.index > 0
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 20
                                    Layout.rightMargin: 20
                                    Layout.preferredHeight: 1
                                    color: Theme.m3OutlineVariant
                                    opacity: 0.6
                                }

                                SettingRow {
                                    Layout.fillWidth: true
                                    entry: item.modelData
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: root.sections.length === 0
            Layout.leftMargin: 8
            text: "No settings match your search."
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 14
        }
    }
}
