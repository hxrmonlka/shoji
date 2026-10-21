import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: Notifs.count > 0 ? "Notifications  " + Notifs.count : "Notifications"
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            IconButton {
                implicitWidth: 32
                implicitHeight: 32
                iconSize: 13
                icon: Notifs.dnd ? "\uf1f6" : "\uf0f3"
                active: Notifs.dnd
                onClicked: Notifs.toggleDnd()
            }

            IconButton {
                implicitWidth: 32
                implicitHeight: 32
                iconSize: 13
                icon: "\uf1f8"
                visible: Notifs.count > 0
                onClicked: Notifs.clearAnimated()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: Notifs.count === 0
            text: Notifs.dnd ? "Do not disturb is on" : "No notifications"
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 12
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel {
                values: Notifs.items
            }

            add: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 200
                    }

                    NumberAnimation {
                        property: "x"
                        from: -36
                        to: 0
                        duration: 300
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
                    }
                }
            }

            displaced: Transition {
                NumberAnimation {
                    property: "y"
                    duration: 260
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
                }
            }

            delegate: NotificationCard {
                required property var modelData
                required property int index

                notif: modelData
                order: index
            }
        }
    }
}
