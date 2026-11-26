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

    height: isHeader ? 34 : 52

    SectionHeader {
        anchors.fill: parent
        visible: row.isHeader
        number: row.modelData.number ?? 0
        title: row.isHeader ? row.modelData.title : ""
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        visible: !row.isHeader
        radius: 16
        color: rowFill.color

        ColorSpring {
            id: rowFill

            target: row.selected ? Theme.m3PrimaryContainer : "transparent"
        }

        AppIcon {
            id: icon

            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            size: 30
            icon: row.modelData.entry ? row.modelData.entry.icon : ""
            fallback: row.modelData.glyph ?? (row.modelData.type === "file" ? (row.modelData.dir ? "\uf07b" : "\uf15b") : row.modelData.type === "web" ? "\uf0ac" : "\uf2d0")
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
