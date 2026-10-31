import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
    id: root

    spacing: 10

    Component.onCompleted: warmup.start()

    Binding {
        target: Schemes
        property: "fallback"
        value: Wallpapers.current
    }

    Connections {
        target: Schemes

        function onPreviewKeyChanged() {
            debounce.restart();
        }
    }

    Timer {
        id: warmup

        interval: 150
        onTriggered: Schemes.refresh()
    }

    Timer {
        id: debounce

        interval: 400
        onTriggered: Schemes.refresh()
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: Schemes.schemes

            Rectangle {
                id: tile

                required property var modelData
                readonly property bool selected: Schemes.scheme === modelData.value
                readonly property var swatch: Schemes.preview(modelData.value)
                readonly property color dotPrimary: swatch ? swatch.primary : selected ? Theme.m3Primary : Theme.m3SurfaceContainerHighest
                readonly property color dotSecondary: swatch ? swatch.secondary : selected ? Theme.m3Secondary : Theme.m3SurfaceContainerHigh
                readonly property color dotTertiary: swatch ? swatch.tertiary : selected ? Theme.m3Tertiary : Theme.m3SurfaceContainer

                Layout.fillWidth: true
                Layout.preferredHeight: 84
                radius: 16
                color: fill.color
                border.width: selected ? 2 : 1
                border.color: ring.color
                opacity: fade.value

                ColorSpring {
                    id: fill

                    target: area.containsMouse ? Theme.m3SurfaceContainerHigh : Theme.m3SurfaceContainer
                }

                ColorSpring {
                    id: ring

                    target: tile.selected ? Theme.m3Primary : Theme.m3OutlineVariant
                }

                Spring {
                    id: fade

                    target: Schemes.ready || tile.swatch ? 1 : 0.5
                    token: Motion.effectsDefault
                    epsilon: 0.002
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 78
                        Layout.preferredHeight: 28

                        Repeater {
                            model: 3

                            Rectangle {
                                id: dotRect

                                required property int index
                                readonly property color tint: index === 0 ? tile.dotPrimary : index === 1 ? tile.dotSecondary : tile.dotTertiary

                                x: index * 25
                                width: 28
                                height: 28
                                radius: 14
                                color: anim.color
                                border.width: 1
                                border.color: Qt.alpha(Theme.m3OnSurface, 0.14)
                                z: index

                                ColorSpring {
                                    id: anim

                                    target: dotRect.tint
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData.label
                        elide: Text.ElideRight
                        color: tile.selected ? Theme.m3Primary : Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: tile.selected ? Font.DemiBold : Font.Medium
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    width: 18
                    height: 18
                    radius: 9
                    color: Theme.m3Primary
                    visible: tile.selected

                    Text {
                        anchors.centerIn: parent
                        text: "\uf00c"
                        color: Theme.m3OnPrimary
                        font.family: Theme.fontIcon
                        font.pixelSize: 9
                    }
                }

                Ripple {
                    id: ripple1

                    anchors.fill: parent
                    radius: parent.radius
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => ripple1.press(area, mouse)
                    onClicked: Schemes.setScheme(tile.modelData.value)
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: hint.implicitHeight

        Text {
            id: hint

            anchors.left: parent.left
            anchors.right: parent.right
            text: Schemes.source.length === 0 ? "Pick a wallpaper to build the previews." : Schemes.failed ? "Matugen returned no previews. Tap to retry." : Schemes.description(Schemes.scheme)
            wrapMode: Text.WordWrap
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 12
        }

        MouseArea {
            anchors.fill: parent
            enabled: Schemes.failed
            cursorShape: Qt.PointingHandCursor
            onClicked: Schemes.retry()
        }
    }
}
