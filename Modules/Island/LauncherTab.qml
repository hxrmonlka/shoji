import QtQuick
import Quickshell
import qs.Commons

Item {
    id: root

    property string query: ""
    property int selected: -1
    readonly property bool searching: query.trim().length > 0
    readonly property var shown: searching ? Apps.find(query, false, 1000) : Apps.all

    onShownChanged: selected = searching && shown.length > 0 ? 0 : -1

    function focusField() {
        field.forceActiveFocus();
    }

    function move(dx, dy) {
        if (shown.length === 0)
            return;
        const base = selected < 0 ? 0 : selected;
        selected = Math.max(0, Math.min(shown.length - 1, base + dx + dy * grid.columns));
        grid.positionViewAtIndex(selected, GridView.Contain);
    }

    function launch() {
        if (selected < 0 || selected >= shown.length)
            return;
        shown[selected].execute();
        ShellState.expanded = false;
    }

    Component.onCompleted: field.forceActiveFocus()

    Connections {
        target: ShellState

        function onExpandedChanged() {
            if (!ShellState.expanded)
                field.text = "";
            else if (ShellState.tab === "launcher")
                Qt.callLater(root.focusField);
        }

        function onTabChanged() {
            if (ShellState.expanded && ShellState.tab === "launcher")
                Qt.callLater(root.focusField);
        }
    }

    Spring {
        id: bar

        target: root.searching ? 1 : 0
        token: Motion.effectsDefault
        epsilon: 0.002
    }

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: "transparent"
        border.width: 1
        border.color: Theme.m3OutlineVariant

        Rectangle {
            id: pill

            anchors.top: parent.top
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - 20, 360)
            height: 40
            radius: 20
            color: Theme.m3SurfaceContainerHigh
            border.width: 1
            border.color: Theme.m3OutlineVariant
            opacity: bar.value
            scale: 0.94 + 0.06 * bar.value

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
                selectByMouse: false
                onTextChanged: root.query = text
                onAccepted: root.launch()
                Keys.onLeftPressed: root.move(-1, 0)
                Keys.onRightPressed: root.move(1, 0)
                Keys.onUpPressed: root.move(0, -1)
                Keys.onDownPressed: root.move(0, 1)
                Keys.onEscapePressed: {
                    if (text.length > 0)
                        text = "";
                    else
                        ShellState.expanded = false;
                }
            }
        }

        GridView {
            id: grid

            readonly property int columns: 6

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 10
            anchors.topMargin: 10 + 50 * bar.value
            z: 1
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: Math.floor(width / columns)
            cellHeight: 92
            model: ScriptModel {
                values: root.shown
            }

            delegate: Item {
                id: tile

                required property var modelData
                required property int index

                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 16
                    color: tileFill.color

                    ColorSpring {
                        id: tileFill

                        target: area.containsMouse || tile.index === root.selected ? Theme.m3SurfaceContainerHighest : "transparent"
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6

                        AppIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            icon: tile.modelData.icon
                            size: 40
                        }

                        Text {
                            width: tile.width - 20
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.name
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: Theme.m3OnSurface
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            tile.modelData.execute();
                            ShellState.expanded = false;
                        }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.searching && root.shown.length === 0
            text: "No apps found"
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 14
        }
    }
}
