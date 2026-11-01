import QtQuick
import qs.Commons

Item {
    id: root

    readonly property bool busy: Network.connecting !== ""
    property bool reveal: false

    implicitHeight: col.implicitHeight

    function submit() {
        Network.submit(pass.text, user.text);
    }

    Component.onCompleted: (Network.promptEap ? user : pass).forceActiveFocus()

    Column {
        id: col

        width: parent.width
        spacing: 6

        Rectangle {
            width: parent.width
            height: 36
            radius: 12
            visible: Network.promptEap
            color: Theme.m3SurfaceContainerHighest
            border.width: user.activeFocus ? 1 : 0
            border.color: Theme.m3Primary

            TextInput {
                id: user

                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 13
                clip: true
                enabled: !root.busy
                KeyNavigation.tab: pass
                onAccepted: pass.forceActiveFocus()
                Keys.onEscapePressed: Network.cancelPrompt()
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: user.text.length === 0
                text: "Username"
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: 13
            }
        }

        Row {
            width: parent.width
            spacing: 4

            Rectangle {
                width: parent.width - 72 - 8
                height: 36
                radius: 12
                color: Theme.m3SurfaceContainerHighest
                border.width: pass.activeFocus ? 1 : 0
                border.color: Theme.m3Primary

                TextInput {
                    id: pass

                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: root.reveal ? TextInput.Normal : TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    color: Theme.m3OnSurface
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    clip: true
                    enabled: !root.busy
                    onAccepted: root.submit()
                    Keys.onEscapePressed: Network.cancelPrompt()
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pass.text.length === 0
                    text: "Password"
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }
            }

            IconButton {
                icon: root.reveal ? "\uf070" : "\uf06e"
                iconSize: 13
                active: root.reveal
                onClicked: root.reveal = !root.reveal
            }

            IconButton {
                icon: root.busy ? "\uf110" : "\uf00c"
                iconSize: 13
                enabled: !root.busy
                onClicked: root.submit()
            }
        }

        Text {
            width: parent.width
            visible: Network.error.length > 0
            text: Network.error
            wrapMode: Text.Wrap
            color: "#f2b8b5"
            font.family: Theme.fontUi
            font.pixelSize: 12
        }
    }
}
