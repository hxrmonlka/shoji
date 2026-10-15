import QtQuick
import qs.Commons

Item {
    id: row

    required property var modelData
    required property int index
    property bool selected: false
    readonly property bool isHeader: modelData.kind === "header"

    signal hovered
    signal activated

    height: isHeader ? 30 : 52

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        visible: row.isHeader
        text: row.modelData.title
        color: Theme.m3OnSurfaceVariant
        font.family: Theme.fontUi
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        visible: !row.isHeader
        radius: 16
        color: row.selected ? Theme.m3PrimaryContainer : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Motion.short3
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }

        AppIcon {
            id: icon

            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            size: 30
            icon: row.modelData.entry ? row.modelData.entry.icon : ""
            fallback: row.modelData.type === "file" ? (row.modelData.dir ? "\uf07b" : "\uf15b") : "\uf2d0"
        }

        Column {
            anchors.left: icon.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: row.modelData.title || ""
                elide: Text.ElideRight
                color: row.selected ? Theme.m3OnPrimaryContainer : Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 15
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: row.modelData.subtitle || ""
                elide: Text.ElideMiddle
                color: row.selected ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                opacity: 0.8
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !row.isHeader
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: row.hovered()
        onClicked: row.activated()
    }
}
