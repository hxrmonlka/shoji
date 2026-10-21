import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: root

    required property var notif
    property int order: 0
    property bool closing: false
    property real collapse: 0
    property int dir: 1
    property int delay: 0
    readonly property real gap: 8

    function close(direction: int, wait: int): void {
        if (closing)
            return;
        dir = direction;
        delay = wait;
        closing = true;
        snapBack.stop();
        leave.restart();
    }

    width: ListView.view ? ListView.view.width : 300
    height: Math.max(0, (face.height + gap) * (1 - collapse))
    clip: collapse > 0

    Connections {
        target: Notifs

        function onClearingChanged() {
            if (Notifs.clearing)
                root.close(1, Math.min(root.order, 8) * 45);
        }
    }

    SequentialAnimation {
        id: leave

        PauseAnimation {
            duration: root.delay
        }

        NumberAnimation {
            target: face
            property: "x"
            to: root.dir * (root.width + 40)
            duration: 240
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.3, 0, 0.8, 0.15, 1, 1]
        }

        NumberAnimation {
            target: root
            property: "collapse"
            to: 1
            duration: 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
        }

        ScriptAction {
            script: root.notif.dismiss()
        }
    }

    NumberAnimation {
        id: snapBack

        target: face
        property: "x"
        to: 0
        duration: 320
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.42, 1.67, 0.21, 0.9, 1, 1]
    }

    Rectangle {
        id: face

        width: root.width
        height: content.implicitHeight + 24
        radius: 18
        color: Theme.m3SurfaceContainerHigh
        opacity: 1 - Math.min(1, Math.abs(x) / (root.width * 0.9))

        DragHandler {
            id: drag

            enabled: !root.closing
            target: face
            xAxis.enabled: true
            yAxis.enabled: false
            onActiveChanged: {
                if (active) {
                    snapBack.stop();
                    return;
                }
                if (Math.abs(face.x) > root.width * 0.35)
                    root.close(face.x > 0 ? 1 : -1, 0);
                else
                    snapBack.restart();
            }
        }

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
                onClicked: root.close(1, 0)
            }
        }
    }
}
