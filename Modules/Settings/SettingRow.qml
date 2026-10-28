import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: root

    required property var entry

    readonly property string kind: entry.type ?? "int"
    readonly property real body: kind === "bool" ? toggleRow.implicitHeight : kind === "string" ? textRow.implicitHeight : kind === "choice" ? choiceRow.implicitHeight : kind === "scheme" ? schemeCol.implicitHeight : sliderRow.implicitHeight

    implicitHeight: body + 28

    component Caption: ColumnLayout {
        id: cap

        required property var entry

        spacing: 2

        Text {
            Layout.fillWidth: true
            text: cap.entry.label
            elide: Text.ElideRight
            color: Theme.m3OnSurface
            font.family: Theme.fontUi
            font.pixelSize: 14
            font.weight: Font.Medium
        }

        Text {
            Layout.fillWidth: true
            visible: (cap.entry.desc ?? "").length > 0
            text: cap.entry.desc ?? ""
            wrapMode: Text.WordWrap
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 12
        }
    }

    component Toggle: Rectangle {
        id: sw

        property bool on: false

        signal flipped

        implicitWidth: 52
        implicitHeight: 30
        radius: height / 2
        color: fill.color

        ColorSpring {
            id: fill

            target: sw.on ? Theme.m3Primary : Theme.m3SurfaceContainerHighest
        }

        Spring {
            id: pos

            target: sw.on ? 1 : 0
            token: Motion.effectsDefault
            epsilon: 0.001
        }

        Rectangle {
            width: 22
            height: 22
            radius: 11
            y: (parent.height - height) / 2
            x: Motion.lerp(4, parent.width - width - 4, Motion.clamp01(pos.value))
            color: sw.on ? Theme.m3OnPrimary : Theme.m3OnSurfaceVariant
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.flipped()
        }
    }

    RowLayout {
        id: toggleRow

        visible: root.kind === "bool"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        Caption {
            Layout.fillWidth: true
            entry: root.entry
        }

        Toggle {
            on: root.kind === "bool" && Settings.get(root.entry.key)
            onFlipped: Settings.set(root.entry.key, !Settings.get(root.entry.key))
        }
    }

    RowLayout {
        id: sliderRow

        visible: root.kind !== "bool" && root.kind !== "string" && root.kind !== "choice" && root.kind !== "scheme"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        Caption {
            Layout.preferredWidth: 240
            entry: root.entry
        }

        ValueSlider {
            id: slider

            Layout.fillWidth: true
            from: root.entry.min ?? 0
            to: root.entry.max ?? 1
            step: root.entry.step ?? 0
            value: root.kind === "bool" || root.kind === "string" ? 0 : Settings.get(root.entry.key)
            onCommitted: v => Settings.set(root.entry.key, v)
        }

        Text {
            Layout.preferredWidth: 56
            horizontalAlignment: Text.AlignRight
            text: Math.round(slider.shown)
            color: Theme.m3OnSurface
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    ColumnLayout {
        id: textRow

        visible: root.kind === "string"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Caption {
            Layout.fillWidth: true
            entry: root.entry
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 14
            color: Theme.m3SurfaceContainerHighest
            border.width: input.activeFocus ? 2 : 0
            border.color: Theme.m3Primary

            TextInput {
                id: input

                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true
                color: Theme.m3OnSurface
                selectionColor: Theme.m3PrimaryContainer
                selectedTextColor: Theme.m3OnPrimaryContainer
                font.family: Theme.fontUi
                font.pixelSize: 13
                onEditingFinished: Settings.set(root.entry.key, text)

                Binding on text {
                    when: !input.activeFocus && root.kind === "string"
                    value: Settings.get(root.entry.key)
                }
            }

            Text {
                anchors.fill: parent
                anchors.leftMargin: 14
                verticalAlignment: Text.AlignVCenter
                visible: input.text.length === 0 && !input.activeFocus
                text: "Not set"
                color: Qt.alpha(Theme.m3OnSurfaceVariant, 0.6)
                font.family: Theme.fontUi
                font.pixelSize: 13
            }
        }
    }

    RowLayout {
        id: choiceRow

        visible: root.kind === "choice"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        Caption {
            Layout.preferredWidth: 240
            entry: root.entry
        }

        Row {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            Repeater {
                model: root.entry.options

                Rectangle {
                    id: pill

                    required property var modelData
                    readonly property bool chosen: Settings.get(root.entry.key) === modelData.value

                    width: pillLabel.implicitWidth + 30
                    height: 34
                    radius: 17
                    color: pillFill.color
                    border.width: 1
                    border.color: pillRing.color

                    ColorSpring {
                        id: pillFill

                        target: pillArea.containsMouse ? Theme.m3SurfaceContainerHighest : pill.chosen ? Theme.m3PrimaryContainer : "transparent"
                    }

                    ColorSpring {
                        id: pillRing

                        target: pill.chosen ? Theme.m3Primary : Theme.m3OutlineVariant
                    }

                    Text {
                        id: pillLabel

                        anchors.centerIn: parent
                        text: pill.modelData.label
                        color: pill.chosen ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: pill.chosen ? Font.DemiBold : Font.Medium
                    }

                    MouseArea {
                        id: pillArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.set(root.entry.key, pill.modelData.value)
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: schemeCol

        visible: root.kind === "scheme"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Caption {
            Layout.fillWidth: true
            entry: root.entry
        }

        SchemeGrid {
            Layout.fillWidth: true
        }
    }
}
