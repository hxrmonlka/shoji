import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: root

    readonly property int squareSize: Math.floor(Math.max(180, Math.min(width * 0.46, height - 28 - 12 - 22)))
    readonly property real luma: 0.2126 * ColorPicker.current.r + 0.7152 * ColorPicker.current.g + 0.0722 * ColorPicker.current.b

    Keys.onEscapePressed: ShellState.expanded = false

    component PillButton: Rectangle {
        id: pill

        property string icon: ""
        property string text: ""
        property bool primary: false

        signal clicked

        implicitWidth: row.implicitWidth + 32
        implicitHeight: 40
        radius: 20
        color: fill.color

        ColorSpring {
            id: fill

            target: pill.primary ? (area.containsMouse ? Theme.m3Primary : Theme.m3PrimaryContainer) : (area.containsMouse ? Theme.m3PrimaryContainer : Theme.m3SurfaceContainerHigh)
        }

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.icon
                color: pill.primary && area.containsMouse ? Theme.m3OnPrimary : Theme.m3OnSurface
                font.family: Theme.fontIcon
                font.pixelSize: 14
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.primary && area.containsMouse ? Theme.m3OnPrimary : Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    component ChannelRow: RowLayout {
        id: ch

        property string label: ""
        property int value: 0

        signal edited(int v)

        spacing: 10

        ValueSlider {
            Layout.fillWidth: true
            label: ch.label
            from: 0
            to: 255
            step: 1
            value: ch.value
            onMoved: v => ch.edited(Math.round(v))
        }

        Rectangle {
            Layout.preferredWidth: 60
            Layout.preferredHeight: 32
            radius: 16
            color: Theme.m3SurfaceContainerHigh

            TextInput {
                id: num

                anchors.fill: parent
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 13
                selectByMouse: true
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator {
                    bottom: 0
                    top: 255
                }
                text: String(ch.value)
                onTextEdited: {
                    if (text.length > 0)
                        ch.edited(parseInt(text));
                }
                onEditingFinished: text = String(ch.value)

                Connections {
                    target: ch

                    function onValueChanged() {
                        if (!num.activeFocus)
                            num.text = String(ch.value);
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: "transparent"
        border.width: 1
        border.color: Theme.m3OutlineVariant

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 16

            ColumnLayout {
                Layout.preferredWidth: root.squareSize
                Layout.fillHeight: true
                spacing: 12

                SvSquare {
                    Layout.preferredWidth: root.squareSize
                    Layout.preferredHeight: root.squareSize
                    hue: ColorPicker.hue
                    sat: ColorPicker.sat
                    val: ColorPicker.val
                    tint: ColorPicker.current
                    onMoved: (s, v) => ColorPicker.setSv(s, v)
                }

                Item {
                    Layout.preferredWidth: root.squareSize
                    Layout.preferredHeight: 22

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 14
                        radius: 7
                        border.width: 1
                        border.color: Theme.m3OutlineVariant
                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0
                                color: "#ff0000"
                            }

                            GradientStop {
                                position: 0.1667
                                color: "#ffff00"
                            }

                            GradientStop {
                                position: 0.3333
                                color: "#00ff00"
                            }

                            GradientStop {
                                position: 0.5
                                color: "#00ffff"
                            }

                            GradientStop {
                                position: 0.6667
                                color: "#0000ff"
                            }

                            GradientStop {
                                position: 0.8333
                                color: "#ff00ff"
                            }

                            GradientStop {
                                position: 1
                                color: "#ff0000"
                            }
                        }
                    }

                    Rectangle {
                        x: ColorPicker.hue * (parent.width - width)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        radius: 11
                        color: Qt.hsva(ColorPicker.hue, 1, 1, 1)
                        border.width: 3
                        border.color: "#ffffff"
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => ColorPicker.setHue(Motion.clamp01((mouse.x - 11) / (width - 22)))
                        onPositionChanged: mouse => {
                            if (pressed)
                                ColorPicker.setHue(Motion.clamp01((mouse.x - 11) / (width - 22)));
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    radius: 20
                    color: ColorPicker.current
                    border.width: 1
                    border.color: Theme.m3OutlineVariant

                    Text {
                        anchors.centerIn: parent
                        text: ColorPicker.hex
                        color: root.luma > 0.6 ? "#000000" : "#ffffff"
                        font.family: Theme.fontUi
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        Layout.preferredWidth: 28
                        text: "HEX"
                        color: Theme.m3OnSurfaceVariant
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Theme.m3SurfaceContainerHigh

                        TextInput {
                            id: hexField

                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.m3OnSurface
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            selectByMouse: true
                            maximumLength: 7
                            validator: RegularExpressionValidator {
                                regularExpression: /^#?[0-9a-fA-F]{0,6}$/
                            }
                            text: ColorPicker.hex
                            onTextEdited: ColorPicker.setHex(text)
                            onEditingFinished: text = ColorPicker.hex

                            Connections {
                                target: ColorPicker

                                function onHexChanged() {
                                    if (!hexField.activeFocus)
                                        hexField.text = ColorPicker.hex;
                                }
                            }
                        }
                    }
                }

                ChannelRow {
                    Layout.fillWidth: true
                    label: "R"
                    value: ColorPicker.red
                    onEdited: v => ColorPicker.setChannel("r", v)
                }

                ChannelRow {
                    Layout.fillWidth: true
                    label: "G"
                    value: ColorPicker.green
                    onEdited: v => ColorPicker.setChannel("g", v)
                }

                ChannelRow {
                    Layout.fillWidth: true
                    label: "B"
                    value: ColorPicker.blue
                    onEdited: v => ColorPicker.setChannel("b", v)
                }

                Text {
                    Layout.fillWidth: true
                    text: "H " + Math.round(ColorPicker.hue * 360) + "\u00b0    S " + Math.round(ColorPicker.sat * 100) + "%    V " + Math.round(ColorPicker.val * 100) + "%"
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                }

                Item {
                    Layout.fillHeight: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    PillButton {
                        Layout.fillWidth: true
                        icon: "\uf1fb"
                        text: "Pick from screen"
                        primary: true
                        onClicked: ColorPicker.begin("gui")
                    }

                    PillButton {
                        Layout.fillWidth: true
                        icon: ColorPicker.copied ? "\uf00c" : "\uf0c5"
                        text: ColorPicker.copied ? "Copied" : "Copy hex"
                        onClicked: ColorPicker.copyHex(false)
                    }
                }
            }
        }
    }
}
