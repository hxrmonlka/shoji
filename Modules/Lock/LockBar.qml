import QtQuick
import M3Shapes
import qs.Commons

Item {
    id: root

    required property var auth

    signal confirmClicked

    readonly property int pillH: Settings.pillHeight
    readonly property int count: auth.shapes.count
    readonly property bool unlocking: auth.unlocking === true
    readonly property bool typing: count > 0 || auth.busy
    readonly property int phase: unlocking || !started ? 0 : typing ? 2 : 1
    readonly property real restW: Math.round(pillH * 5)
    readonly property real targetW: phase === 0 ? restW : phase === 1 ? restW + 28 : Math.min(480, Math.max(320, count * 18 + 140))
    readonly property real targetH: phase === 0 ? pillH : phase === 1 ? pillH + 6 : pillH + 18
    readonly property int lastShape: count > 0 ? (auth.passwordShapeAssignments[count - 1] ?? 0) : 0
    readonly property bool ready: count > 0 && !auth.busy
    readonly property color errorColor: "#f2b8b5"
    property bool started: false
    property real shake: 0

    width: wSpring.value
    height: hSpring.value

    Timer {
        running: true
        interval: 90
        onTriggered: root.started = true
    }

    Spring {
        id: wSpring

        target: root.targetW
        token: root.unlocking ? Motion.settle : Motion.spatialDefault
        epsilon: 0.05
    }

    Spring {
        id: hSpring

        target: root.targetH
        token: root.unlocking ? Motion.settle : Motion.spatialDefault
        epsilon: 0.05
    }

    Spring {
        id: contentSpring

        target: root.phase === 2 ? 1 : 0
        token: Motion.effectsDefault
        epsilon: 0.002
    }

    Spring {
        id: iconSpring

        target: root.phase === 1 ? 1 : 0
        token: Motion.lag
        epsilon: 0.002
    }

    SequentialAnimation {
        id: shaker

        NumberAnimation { target: root; property: "shake"; to: -14; duration: 50 }
        NumberAnimation { target: root; property: "shake"; to: 14; duration: 80 }
        NumberAnimation { target: root; property: "shake"; to: -10; duration: 70 }
        NumberAnimation { target: root; property: "shake"; to: 8; duration: 60 }
        NumberAnimation { target: root; property: "shake"; to: 0; duration: 50 }
    }

    Connections {
        target: root.auth

        function onFailedChanged() {
            if (root.auth.failed)
                shaker.restart();
        }
    }

    Rectangle {
        id: bar

        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(Theme.m3SurfaceContainerHigh, 0.82)
        border.width: 1
        border.color: root.auth.failed ? root.errorColor : Theme.m3OutlineVariant
        clip: true
        transform: Translate {
            x: root.shake
        }

        Text {
            anchors.centerIn: parent
            text: "\uf023"
            font.family: Theme.fontIcon
            font.pixelSize: Math.round(root.pillH * 0.4)
            color: root.auth.failed ? root.errorColor : Theme.m3OnSurface
            opacity: Math.max(0, Math.min(1, iconSpring.value))
            scale: 0.6 + 0.4 * Math.max(0, iconSpring.value)
            visible: opacity > 0.01
        }

        Item {
            anchors.fill: parent
            opacity: Math.max(0, Math.min(1, contentSpring.value))
            visible: opacity > 0.01

            Item {
                id: clip

                anchors.left: parent.left
                anchors.right: confirm.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 22
                anchors.rightMargin: 8
                clip: true

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: root.auth.shapes

                        Item {
                            id: dot

                            required property int shape

                            width: 18
                            height: 20

                            Rectangle {
                                anchors.centerIn: parent
                                width: 10
                                height: 10
                                radius: 5
                                color: Theme.m3Primary
                                visible: !Settings.materialPasswordShapes
                                scale: 0.4
                                opacity: 0

                                NumberAnimation on scale {
                                    from: 0.4
                                    to: 1
                                    duration: 320
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.42, 1.67, 0.21, 0.9, 1, 1]
                                }

                                NumberAnimation on opacity {
                                    from: 0
                                    to: 1
                                    duration: 90
                                }
                            }

                            PasswordShape {
                                anchors.centerIn: parent
                                color: Theme.m3Primary
                                kind: dot.shape
                                visible: Settings.materialPasswordShapes
                            }
                        }
                    }
                }
            }

            Item {
                id: confirm

                readonly property real side: Math.min(44, root.height - 12)

                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: side
                height: side
                scale: confirmArea.pressed ? 0.92 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                    }
                }

                MaterialShape {
                    anchors.fill: parent
                    shape: MaterialExpressiveShapes.catalog[root.lastShape] ?? MaterialShape.Circle
                    color: root.ready ? Theme.m3Primary : Theme.m3SurfaceContainerHighest
                    animationDuration: 280
                }

                Text {
                    anchors.centerIn: parent
                    visible: !root.auth.busy
                    text: "\uf061"
                    font.family: Theme.fontIcon
                    font.pixelSize: 16
                    color: root.ready ? Theme.m3OnPrimary : Theme.m3OnSurfaceVariant
                }

                Text {
                    id: spinner

                    anchors.centerIn: parent
                    visible: root.auth.busy
                    text: "\uf110"
                    font.family: Theme.fontIcon
                    font.pixelSize: 16
                    color: Theme.m3OnSurfaceVariant

                    RotationAnimator on rotation {
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        running: spinner.visible
                    }
                }

                MouseArea {
                    id: confirmArea

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.confirmClicked()
                }
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 12
        text: root.auth.busy ? "Checking" : root.auth.message
        color: root.auth.failed ? root.errorColor : Theme.m3OnSurfaceVariant
        font.family: Theme.fontUi
        font.pixelSize: 14
        opacity: root.auth.busy || root.auth.failed ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }
    }
}
