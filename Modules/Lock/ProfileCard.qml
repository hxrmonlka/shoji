import QtQuick
import qs.Commons

Item {
    id: root

    property string caption: ""
    property string name: ""
    property var avatarSource: null
    property int avatarKind: 7
    property bool clickable: false
    property bool showSwitch: false
    property bool highlighted: false
    property real reveal: 1

    signal clicked

    readonly property bool hovered: area.containsMouse

    width: Math.max(208, body.implicitWidth + 32)
    height: body.implicitHeight + 28
    visible: caption.length > 0 || name.length > 0

    Rectangle {
        id: card

        anchors.fill: parent
        radius: 24
        opacity: root.reveal
        color: root.highlighted || (root.clickable && root.hovered) ? Qt.alpha(Theme.m3SurfaceContainerHigh, 0.85) : Qt.alpha(Theme.m3SurfaceContainer, 0.7)
        border.width: 1
        border.color: root.highlighted ? Theme.m3Primary : Theme.m3OutlineVariant
        scale: root.clickable && area.pressed ? 0.97 : 1
        transform: Translate {
            y: (1 - root.reveal) * 8
        }

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
            }
        }

        Row {
            id: body

            anchors.centerIn: parent
            spacing: 14

            Avatar {
                anchors.verticalCenter: parent.verticalCenter
                size: 64
                kind: root.avatarKind
                override: root.avatarSource
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    visible: root.caption.length > 0
                    width: Math.min(implicitWidth, 260)
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    text: root.caption
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }

                Row {
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.name.length > 0
                        width: Math.min(implicitWidth, 220)
                        elide: Text.ElideRight
                        text: root.name
                        color: Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf313"
                        color: Theme.m3Primary
                        font.family: Theme.fontIcon
                        font.pixelSize: 18
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.showSwitch
                        opacity: root.hovered ? 1 : 0.6
                        text: "\uf0ec"
                        color: Theme.m3OnSurfaceVariant
                        font.family: Theme.fontIcon
                        font.pixelSize: 14

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: true
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
