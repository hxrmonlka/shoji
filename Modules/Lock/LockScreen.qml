import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Bluetooth
import qs.Commons

Item {
    id: root

    readonly property string wallpaper: Wallpapers.current
    property bool menuOpen: false

    function refocus(): void {
        input.forceActiveFocus();
    }

    function act(cmd: string): void {
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    Component.onCompleted: {
        refocus();
        intro.start();
    }

    opacity: 0

    NumberAnimation {
        id: intro

        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: 300
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.m3Surface
    }

    Image {
        id: img

        anchors.fill: parent
        visible: false
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        source: root.wallpaper ? "file://" + root.wallpaper : ""
        sourceSize: Qt.size(Math.max(root.width, 1), Math.max(root.height, 1))
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        visible: img.status === Image.Ready
        blurEnabled: true
        blur: 0.7
        blurMax: 64
        autoPaddingEnabled: false
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.15
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: root.refocus()
        onClicked: {
            root.menuOpen = false;
            root.refocus();
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 4

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(ShellState.clock.date, "HH:mm")
            color: Theme.m3OnSurface
            font.family: Theme.fontUi
            font.pixelSize: 144
            font.weight: Font.Light
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(ShellState.clock.date, "dddd, MMMM d")
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 22
        }
    }

    Rectangle {
        id: status

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        height: 44
        width: statusRow.implicitWidth + 24
        radius: height / 2
        color: Qt.alpha(Theme.m3SurfaceContainer, 0.7)
        border.color: Theme.m3OutlineVariant
        border.width: 1

        Row {
            id: statusRow

            anchors.centerIn: parent
            spacing: 18

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf1eb"
                font.family: Theme.fontIcon
                font.pixelSize: 17
                color: Network.wifiEnabled ? (Network.active ? Theme.m3OnSurface : Theme.m3OnSurfaceVariant) : Qt.alpha(Theme.m3OnSurfaceVariant, 0.4)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf293"
                font.family: Theme.fontIcon
                font.pixelSize: 17
                color: (Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled) ? Theme.m3OnSurface : Qt.alpha(Theme.m3OnSurfaceVariant, 0.4)
            }
        }
    }

    Rectangle {
        id: field

        property real shake: 0

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: shake
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        width: 380
        height: 60
        radius: height / 2
        color: Qt.alpha(Theme.m3SurfaceContainerHigh, 0.82)
        border.width: 1
        border.color: LockState.failed ? "#f2b8b5" : Theme.m3OutlineVariant

        SequentialAnimation {
            id: shaker

            NumberAnimation { target: field; property: "shake"; to: -14; duration: 50 }
            NumberAnimation { target: field; property: "shake"; to: 14; duration: 80 }
            NumberAnimation { target: field; property: "shake"; to: -10; duration: 70 }
            NumberAnimation { target: field; property: "shake"; to: 8; duration: 60 }
            NumberAnimation { target: field; property: "shake"; to: 0; duration: 50 }
        }

        Connections {
            target: LockState

            function onFailedChanged() {
                if (LockState.failed)
                    shaker.restart();
            }
        }

        TextInput {
            id: input

            width: 1
            height: 1
            opacity: 0
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData
            enabled: !LockState.busy
            focus: true
            onTextChanged: LockState.password = text
            onAccepted: LockState.submit()
            Keys.onEscapePressed: LockState.password = ""

            Connections {
                target: LockState

                function onPasswordChanged() {
                    if (input.text !== LockState.password)
                        input.text = LockState.password;
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            visible: LockState.password.length === 0
            text: LockState.busy ? "Checking" : LockState.failed ? LockState.message : "Enter password"
            color: LockState.failed ? "#f2b8b5" : Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 16
        }

        Item {
            id: clip

            anchors.left: parent.left
            anchors.right: confirm.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 8
            clip: true

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: LockState.password.length

                    PasswordShape {
                        color: Theme.m3Primary
                    }
                }
            }
        }

        Rectangle {
            id: confirm

            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48
            radius: width / 2
            color: LockState.password.length > 0 && !LockState.busy ? Theme.m3Primary : Theme.m3SurfaceContainerHighest

            Text {
                anchors.centerIn: parent
                text: "\uf061"
                font.family: Theme.fontIcon
                font.pixelSize: 16
                color: LockState.password.length > 0 && !LockState.busy ? Theme.m3OnPrimary : Theme.m3OnSurfaceVariant
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    LockState.submit();
                    root.refocus();
                }
            }
        }
    }

    Item {
        id: power

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        width: 52
        height: 52

        Rectangle {
            id: menu

            readonly property var entries: [
                { label: "Shutdown", icon: "\uf011", cmd: "systemctl poweroff" },
                { label: "Reboot", icon: "\uf021", cmd: "systemctl reboot" },
                { label: "Logout", icon: "\uf08b", cmd: Settings.logoutCommand }
            ]

            anchors.right: parent.right
            anchors.bottom: parent.top
            anchors.bottomMargin: 10
            width: 180
            height: col.implicitHeight + 16
            radius: 22
            color: Theme.m3SurfaceContainerHigh
            border.color: Theme.m3OutlineVariant
            border.width: 1
            visible: opacity > 0
            opacity: root.menuOpen ? 1 : 0
            scale: root.menuOpen ? 1 : 0.9
            transformOrigin: Item.BottomRight

            Behavior on opacity {
                NumberAnimation { duration: 140 }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.42, 1.67, 0.21, 0.9, 1, 1]
                }
            }

            Column {
                id: col

                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                Repeater {
                    model: menu.entries

                    Rectangle {
                        id: row

                        required property var modelData

                        width: col.width
                        height: 44
                        radius: 16
                        color: rowArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.icon
                            font.family: Theme.fontIcon
                            font.pixelSize: 15
                            color: Theme.m3OnSurfaceVariant
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 46
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.label
                            font.family: Theme.fontUi
                            font.pixelSize: 15
                            color: Theme.m3OnSurface
                        }

                        MouseArea {
                            id: rowArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.menuOpen = false;
                                root.act(row.modelData.cmd);
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.menuOpen ? Theme.m3PrimaryContainer : Qt.alpha(Theme.m3SurfaceContainer, 0.7)
            border.color: Theme.m3OutlineVariant
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "\uf011"
                font.family: Theme.fontIcon
                font.pixelSize: 18
                color: root.menuOpen ? Theme.m3OnPrimaryContainer : Theme.m3OnSurface
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.menuOpen = !root.menuOpen;
                    root.refocus();
                }
            }
        }
    }
}
