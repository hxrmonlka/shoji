import QtQuick
import QtQuick.Layouts
import qs.Commons

Rectangle {
    id: root

    required property var notif

    implicitHeight: content.implicitHeight + 24
    radius: 18
    color: Theme.m3SurfaceContainerHigh

    RowLayout {
        id: content

        x: 12
        y: 12
        width: parent.width - 24
        spacing: 12

        Item {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            Layout.alignment: Qt.AlignTop

            RoundedImage {
                anchors.fill: parent
                radius: 18
                source: root.notif.image
                visible: root.notif.image.length > 0
            }

            AppIcon {
                anchors.fill: parent
                size: 36
                icon: root.notif.appIcon || root.notif.desktopEntry
                visible: root.notif.image.length === 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.notif.appName
                elide: Text.ElideRight
                color: Theme.m3OnSurfaceVariant
                opacity: 0.8
                font.family: Theme.fontUi
                font.pixelSize: 10
            }

            Text {
                Layout.fillWidth: true
                text: root.notif.summary
                visible: text.length > 0
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.notif.body
                visible: text.length > 0
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: 12
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.notif.actions.length > 0
                spacing: 6

                Repeater {
                    model: root.notif.actions

                    Rectangle {
                        id: action

                        required property var modelData

                        implicitWidth: actionText.implicitWidth + 20
                        implicitHeight: 26
                        radius: 13
                        color: actionFill.color

                        ColorSpring {
                            id: actionFill

                            target: actionArea.containsMouse ? Theme.m3PrimaryContainer : Theme.m3SurfaceContainerHighest
                        }

                        Text {
                            id: actionText

                            anchors.centerIn: parent
                            text: action.modelData.text
                            color: Theme.m3OnSurface
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: actionArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: action.modelData.invoke()
                        }
                    }
                }
            }
        }

        IconButton {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 28
            implicitHeight: 28
            iconSize: 11
            icon: "\uf00d"
            onClicked: root.notif.dismiss()
        }
    }
}
