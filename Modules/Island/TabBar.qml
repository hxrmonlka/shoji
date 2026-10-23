import QtQuick
import qs.Commons

Item {
    id: root

    required property var tabs
    required property string current

    signal picked(string tabId)

    readonly property int chipHeight: 36
    readonly property int gap: 8
    readonly property int fadeWidth: 28
    readonly property color fadeClear: Qt.rgba(Theme.m3SurfaceContainer.r, Theme.m3SurfaceContainer.g, Theme.m3SurfaceContainer.b, 0)
    readonly property real viewWidth: Math.min(width, Settings.panelWidth - 32)
    property real rowWidth: 0
    readonly property real period: rowWidth > 0 ? rowWidth + gap : 0
    property real target: 0
    property real dragStart: 0
    readonly property real wrapped: period > 0 ? ((pos.value % period) + period) % period : 0

    function reveal(tabId: string): void {
        if (period <= 0)
            return;
        const i = tabs.findIndex(t => t.id === tabId);
        const strip = copies.itemAt(1);
        const chip = strip && i >= 0 ? strip.chipAt(i) : null;
        if (!chip)
            return;
        const half = chip.width / 2;
        const mid = viewWidth / 2;
        let best = null;
        for (let k = 0; k < 3; k++) {
            const c = k * period - wrapped + chip.x + half;
            if (c - half >= 0 && c + half <= viewWidth)
                return;
            const d = c - mid;
            if (best === null || Math.abs(d) < Math.abs(best))
                best = d;
        }
        target = pos.value + best;
    }

    implicitHeight: 48
    onCurrentChanged: reveal(current)

    Spring {
        id: pos

        target: root.target
        token: Motion.effectsDefault
        epsilon: 0.05
    }

    Item {
        id: view

        anchors.horizontalCenter: parent.horizontalCenter
        width: root.viewWidth
        height: parent.height
        clip: true

        Repeater {
            id: copies

            model: 3

            delegate: Row {
                id: strip

                required property int index

                function chipAt(i: int): Item {
                    return chips.itemAt(i);
                }

                x: index * root.period - root.wrapped
                anchors.verticalCenter: parent.verticalCenter
                height: root.chipHeight
                spacing: root.gap
                onImplicitWidthChanged: {
                    if (index === 0)
                        root.rowWidth = implicitWidth;
                }

                Repeater {
                    id: chips

                    model: root.tabs

                    delegate: Rectangle {
                        id: chip

                        required property var modelData
                        readonly property bool active: modelData.id === root.current

                        width: chipRow.implicitWidth + 32
                        height: root.chipHeight
                        radius: height / 2
                        color: chipFill.color

                        ColorSpring {
                            id: chipFill

                            target: chip.active ? Theme.m3PrimaryContainer : chipArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
                        }

                        Row {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.icon
                                color: chip.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                                font.family: Theme.fontIcon
                                font.pixelSize: 16
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.label
                                color: chip.active ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                                font.family: Theme.fontUi
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: chipArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.picked(chip.modelData.id)
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.fadeWidth
            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Theme.m3SurfaceContainer
                }

                GradientStop {
                    position: 1
                    color: root.fadeClear
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.fadeWidth
            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: root.fadeClear
                }

                GradientStop {
                    position: 1
                    color: Theme.m3SurfaceContainer
                }
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const d = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                root.target -= d / 120 * 96;
            }
        }

        DragHandler {
            target: null
            yAxis.enabled: false
            onActiveChanged: {
                if (active) {
                    root.dragStart = pos.value;
                    root.target = pos.value;
                }
            }
            onTranslationChanged: {
                if (!active)
                    return;
                root.target = root.dragStart - translation.x;
                pos.value = root.target;
                pos.velocity = 0;
            }
        }
    }
}
