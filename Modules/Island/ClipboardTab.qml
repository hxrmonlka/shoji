import QtQuick
import Quickshell
import qs.Commons

Item {
    id: root

    property string query: ""
    readonly property string needle: query.trim().toLowerCase()
    readonly property var shown: needle.length === 0 ? ClipboardHistory.entries : ClipboardHistory.entries.filter(e => e.preview.toLowerCase().includes(needle))

    property int selected: -1
    readonly property var current: selected >= 0 && selected < shown.length ? shown[selected] : null

    function move(step) {
        if (shown.length === 0)
            return;
        selected = Math.max(0, Math.min(shown.length - 1, selected + step));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function use() {
        if (!current)
            return;
        ClipboardHistory.copy(current);
        ShellState.expanded = false;
    }

    function discard() {
        if (current)
            ClipboardHistory.remove(current);
    }

    onShownChanged: selected = shown.length === 0 ? -1 : Math.max(0, Math.min(selected, shown.length - 1))
    onNeedleChanged: selected = shown.length === 0 ? -1 : 0

    function focusField() {
        field.forceActiveFocus();
    }

    Keys.onEscapePressed: ShellState.expanded = false
    Component.onCompleted: {
        ClipboardHistory.refresh();
        field.forceActiveFocus();
    }

    Connections {
        target: ShellState

        function onExpandedChanged() {
            if (ShellState.expanded)
                Qt.callLater(root.focusField);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: "transparent"
        border.width: 1
        border.color: Theme.m3OutlineVariant

        Row {
            id: head

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 8

            Rectangle {
                width: head.width - clearBtn.width - head.spacing
                height: 40
                radius: 20
                color: Theme.m3SurfaceContainerHigh

                Text {
                    id: glass

                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf002"
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontIcon
                    font.pixelSize: 14
                }

                TextInput {
                    id: field

                    anchors.left: glass.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.m3OnSurface
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    clip: true
                    selectByMouse: true
                    onTextChanged: root.query = text
                    Keys.onDownPressed: root.move(1)
                    Keys.onUpPressed: root.move(-1)
                    Keys.onReturnPressed: root.use()
                    Keys.onEnterPressed: root.use()
                    Keys.onDeletePressed: root.discard()
                    Keys.onEscapePressed: {
                        if (text.length > 0)
                            text = "";
                        else
                            ShellState.expanded = false;
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text.length === 0
                        text: "Search clipboard"
                        color: Theme.m3OnSurfaceVariant
                        font: field.font
                    }
                }
            }

            Rectangle {
                id: clearBtn

                readonly property bool usable: ClipboardHistory.entries.length > 0

                width: clearText.implicitWidth + 32
                height: 40
                radius: 20
                color: clearFill.color
                opacity: usable ? 1 : 0.4

                ColorSpring {
                    id: clearFill

                    target: clearArea.containsMouse && clearBtn.usable ? Theme.m3PrimaryContainer : Theme.m3SurfaceContainerHigh
                }

                Text {
                    id: clearText

                    anchors.centerIn: parent
                    text: "Clear all"
                    color: Theme.m3OnSurface
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: clearArea

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: clearBtn.usable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ClipboardHistory.wipe()
                }
            }
        }

        ListView {
            id: list

            anchors.top: head.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.bottomMargin: 8
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel {
                values: root.shown
            }

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index
                readonly property bool selected: index === root.selected
                readonly property bool image: modelData.kind === "image"

                width: list.width
                height: image ? 92 : 56
                radius: 16
                color: rowFill.color

                ColorSpring {
                    id: rowFill

                    target: row.selected ? Theme.m3SurfaceContainerHighest : "transparent"
                }

                Loader {
                    id: lead

                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: row.image ? thumb : badge
                }

                Component {
                    id: badge

                    Rectangle {
                        width: 36
                        height: 36
                        radius: 12
                        color: Theme.m3PrimaryContainer

                        Text {
                            anchors.centerIn: parent
                            text: row.modelData.kind === "files" ? "\uf0c5" : "\uf15c"
                            color: Theme.m3OnPrimaryContainer
                            font.family: Theme.fontIcon
                            font.pixelSize: 15
                        }
                    }
                }

                Component {
                    id: thumb

                    RoundedImage {
                        width: 120
                        height: 72
                        radius: 12
                        source: "file://" + row.modelData.path
                        sourceSize: Qt.size(240, 144)
                    }
                }

                Column {
                    anchors.left: lead.right
                    anchors.leftMargin: 12
                    anchors.right: del.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: row.image ? "Image" : row.modelData.kind === "files" ? (row.modelData.count > 1 ? row.modelData.count + " files" : "File") : row.modelData.preview
                        color: Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: row.modelData.kind === "text" ? Font.Normal : Font.Medium
                        wrapMode: Text.Wrap
                        maximumLineCount: row.modelData.kind === "text" ? 2 : 1
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: row.modelData.kind !== "text"
                        width: parent.width
                        text: row.image ? row.modelData.ext.toUpperCase() + "  " + row.modelData.dims + "  " + row.modelData.size : row.modelData.preview
                        color: Theme.m3OnSurfaceVariant
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                }

                MouseArea {
                    id: rowArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.selected = row.index
                    onClicked: {
                        ClipboardHistory.copy(row.modelData);
                        ShellState.expanded = false;
                    }
                }

                Rectangle {
                    id: del

                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 15
                    color: delArea.containsMouse ? Theme.m3PrimaryContainer : "transparent"
                    opacity: row.selected || rowArea.containsMouse || delArea.containsMouse ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 120
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\uf00d"
                        color: delArea.containsMouse ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                        font.family: Theme.fontIcon
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: delArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ClipboardHistory.remove(row.modelData)
                    }
                }
            }
        }

        Text {
            anchors.centerIn: list
            visible: root.shown.length === 0
            text: root.needle.length > 0 ? "No matches" : "Clipboard is empty"
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 14
        }
    }
}
