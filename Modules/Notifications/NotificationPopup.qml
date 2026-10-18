import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: root

    readonly property var info: Notifs.popupInfo

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            Notifs.hidePopup();
            if (mouse.button === Qt.LeftButton)
                ShellState.control = true;
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 14

        Item {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            Layout.alignment: Qt.AlignVCenter

            RoundedImage {
                anchors.fill: parent
                radius: 22
                source: root.info.image
                visible: root.info.image.length > 0
            }

            AppIcon {
                anchors.fill: parent
                size: 44
                icon: root.info.icon
                visible: root.info.image.length === 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.info.summary || root.info.appName
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.info.body
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
        }
    }
}
