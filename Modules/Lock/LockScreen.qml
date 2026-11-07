import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Bluetooth
import qs.Commons

Item {
    id: root

    readonly property string wallpaper: Wallpapers.current
    readonly property int span: Math.max(width, height)
    property var auth: LockState
    property bool greeter: false
    property bool menuOpen: false
    property bool sessionsOpen: false
    readonly property bool picking: greeter && auth.picking
    property real reveal: 0

    function refocus(): void {
        if (greeter)
            console.log("GREETER refocus requested", "enabled", input.enabled, "activeFocus", input.activeFocus);
        input.forceActiveFocus();
        if (greeter) {
            Qt.callLater(() => {
                console.log("GREETER refocus result", "enabled", input.enabled, "activeFocus", input.activeFocus);
            });
        }
    }

    function act(cmd: string): void {
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    Component.onCompleted: {
        Profile.refresh();
        refocus();
        intro.start();
    }

    NumberAnimation {
        id: intro

        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: 300
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }

    Rectangle {
        anchors.fill: parent
        color: root.wallpaper ? "black" : Theme.m3Surface
    }

    Image {
        id: img

        anchors.fill: parent
        visible: false
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize: Qt.size(root.span, root.span)
        source: root.wallpaper && root.span > 0 ? "file://" + root.wallpaper : ""
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        visible: opacity > 0
        opacity: img.status === Image.Ready ? 1 : 0
        blurEnabled: true
        blur: 0.7
        blurMax: 64
        autoPaddingEnabled: false

        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }
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
        opacity: root.reveal

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
        opacity: root.reveal
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

    Avatar {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: field.top
        anchors.bottomMargin: 24
        opacity: root.picking ? 0 : root.reveal
        kind: root.auth.frameShape
        size: 96
        override: root.greeter ? root.auth.avatar : null
    }

    Row {
        id: userRow

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 120
        spacing: 20
        visible: opacity > 0.01
        opacity: root.picking ? root.reveal : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }

        Repeater {
            model: root.greeter ? root.auth.users : []

            Rectangle {
                id: card

                required property var modelData
                required property int index

                width: 140
                height: 168
                radius: 32
                color: card.index === root.auth.highlighted || cardArea.containsMouse ? Qt.alpha(Theme.m3SurfaceContainerHigh, 0.85) : "transparent"
                border.width: card.index === root.auth.highlighted ? 1 : 0
                border.color: Theme.m3Primary

                Avatar {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 16
                    size: 96
                    kind: MaterialShapes.frameKinds[card.index % MaterialShapes.frameKinds.length]
                    override: card.modelData.icon
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: card.modelData.real
                    color: Theme.m3OnSurface
                    font.family: Theme.fontUi
                    font.pixelSize: 15
                }

                MouseArea {
                    id: cardArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.auth.highlighted = card.index;
                        root.auth.submit();
                        root.refocus();
                    }
                }
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
        opacity: root.picking ? 0 : root.reveal
        width: 380
        height: 60
        radius: height / 2
        color: Qt.alpha(Theme.m3SurfaceContainerHigh, 0.82)
        border.width: 1
        border.color: root.auth.failed ? "#f2b8b5" : Theme.m3OutlineVariant

        SequentialAnimation {
            id: shaker

            NumberAnimation { target: field; property: "shake"; to: -14; duration: 50 }
            NumberAnimation { target: field; property: "shake"; to: 14; duration: 80 }
            NumberAnimation { target: field; property: "shake"; to: -10; duration: 70 }
            NumberAnimation { target: field; property: "shake"; to: 8; duration: 60 }
            NumberAnimation { target: field; property: "shake"; to: 0; duration: 50 }
        }

        Connections {
            target: root.auth

            function onFailedChanged() {
                if (root.auth.failed)
                    shaker.restart();
            }
        }

        TextInput {
            id: input

            width: 1
            height: 1
            opacity: 0
            echoMode: root.auth.secret ? TextInput.Password : TextInput.Normal
            inputMethodHints: Qt.ImhSensitiveData
            enabled: !root.auth.busy
            focus: true
            onTextChanged: {
                root.auth.password = text;
                if (root.greeter)
                    console.log("GREETER input text length", text.length);
            }
            onActiveFocusChanged: {
                if (root.greeter)
                    console.log("GREETER input activeFocus", activeFocus);
            }
            onEnabledChanged: {
                if (root.greeter)
                    console.log("GREETER input enabled", enabled);
            }
            Keys.onPressed: event => {
                if (root.greeter)
                    console.log("GREETER key event received");
            }
            onAccepted: root.auth.submit()
            Keys.onEscapePressed: root.auth.password = ""
            Keys.onLeftPressed: event => {
                if (root.picking)
                    root.auth.moveUser(-1);
                else
                    event.accepted = false;
            }
            Keys.onRightPressed: event => {
                if (root.picking)
                    root.auth.moveUser(1);
                else
                    event.accepted = false;
            }

            Connections {
                target: root.auth

                function onPasswordChanged() {
                    if (input.text !== root.auth.password)
                        input.text = root.auth.password;
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            visible: root.auth.password.length === 0
            text: root.auth.busy ? "Checking" : root.auth.failed ? root.auth.message : root.auth.prompt
            color: root.auth.failed ? "#f2b8b5" : Theme.m3OnSurfaceVariant
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

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.auth.secret
                text: root.auth.password
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 16
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.auth.secret

                Repeater {
                    model: root.auth.shapes

                    PasswordShape {
                        required property int shape

                        color: Theme.m3Primary
                        kind: shape
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
            color: root.auth.password.length > 0 && !root.auth.busy ? Theme.m3Primary : Theme.m3SurfaceContainerHighest

            Text {
                anchors.centerIn: parent
                text: "\uf061"
                font.family: Theme.fontIcon
                font.pixelSize: 16
                color: root.auth.password.length > 0 && !root.auth.busy ? Theme.m3OnPrimary : Theme.m3OnSurfaceVariant
            }

            Ripple {
                id: ripple1

                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                id: rippleArea1

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => ripple1.press(rippleArea1, mouse)
                onClicked: {
                    root.auth.submit();
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
        opacity: root.reveal
        width: 52
        height: 52

        Rectangle {
            id: menu

            readonly property var entries: [
                { label: "Shutdown", icon: "\uf011", cmd: "systemctl poweroff" },
                { label: "Reboot", icon: "\uf021", cmd: "systemctl reboot" },
                { label: "Logout", icon: "\uf08b", cmd: Settings.logoutCommand }
            ].slice(0, root.greeter ? 2 : 3)

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

                        Ripple {
                            id: ripple2

                            anchors.fill: parent
                            radius: parent.radius
                        }

                        MouseArea {
                            id: rowArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => ripple2.press(rowArea, mouse)
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

            Ripple {
                id: ripple3

                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                id: rippleArea3

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => ripple3.press(rippleArea3, mouse)
                onClicked: {
                    root.menuOpen = !root.menuOpen;
                    root.refocus();
                }
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: field.bottom
        anchors.topMargin: 14
        visible: root.greeter && root.auth.user !== "" && !root.picking
        opacity: root.reveal
        text: root.auth.user + (root.auth.users.length > 1 ? "  \u00b7  switch user" : "")
        color: Theme.m3OnSurfaceVariant
        font.family: Theme.fontUi
        font.pixelSize: 13

        MouseArea {
            anchors.fill: parent
            enabled: root.auth.users.length > 1
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.auth.reset();
                root.refocus();
            }
        }
    }

    Item {
        id: sessionBox

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        visible: root.greeter
        opacity: root.reveal
        width: sessionPill.width
        height: 52

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.top
            anchors.bottomMargin: 10
            width: 220
            height: sessionCol.implicitHeight + 16
            radius: 22
            color: Theme.m3SurfaceContainerHigh
            border.width: 1
            border.color: Theme.m3OutlineVariant
            opacity: root.sessionsOpen ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }
            }

            Column {
                id: sessionCol

                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                Repeater {
                    model: root.auth.sessions ?? []

                    Rectangle {
                        id: sessionRow

                        required property var modelData

                        width: sessionCol.width
                        height: 40
                        radius: 16
                        color: sessionArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: sessionRow.modelData.name
                            elide: Text.ElideRight
                            color: root.auth.session && root.auth.session.exec === sessionRow.modelData.exec ? Theme.m3Primary : Theme.m3OnSurface
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: sessionArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.auth.session = sessionRow.modelData;
                                root.sessionsOpen = false;
                                root.refocus();
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: sessionPill

            height: 52
            width: sessionLabel.implicitWidth + 44
            radius: height / 2
            color: root.sessionsOpen ? Theme.m3PrimaryContainer : Qt.alpha(Theme.m3SurfaceContainer, 0.7)
            border.width: 1
            border.color: Theme.m3OutlineVariant

            Text {
                id: sessionLabel

                anchors.centerIn: parent
                text: root.auth.session ? root.auth.session.name : "No session"
                color: root.sessionsOpen ? Theme.m3OnPrimaryContainer : Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 14
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.sessionsOpen = !root.sessionsOpen;
                    root.refocus();
                }
            }
        }
    }
}
