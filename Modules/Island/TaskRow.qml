import QtQuick
import qs.Commons

Item {
    id: row

    required property var modelData
    readonly property var task: modelData
    property bool editing: false

    signal toggled
    signal removed
    signal editRequested
    signal committed(string text)
    signal cancelled

    function beginEdit() {
        input.text = task.text;
        input.forceActiveFocus();
        input.selectAll();
    }

    height: 44

    onEditingChanged: if (editing) beginEdit()
    Component.onCompleted: if (editing) beginEdit()

    HoverHandler {
        id: hover
    }

    Rectangle {
        id: check

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 22
        radius: 11
        color: row.task.done ? Theme.m3Primary : "transparent"
        border.width: 2
        border.color: row.task.done ? Theme.m3Primary : Theme.m3OutlineVariant

        Behavior on color {
            ColorAnimation {
                duration: Motion.short4
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }

        Text {
            anchors.centerIn: parent
            text: "\uf00c"
            visible: row.task.done
            color: Theme.m3OnPrimary
            font.family: Theme.fontIcon
            font.pixelSize: 11
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: row.toggled()
        }
    }

    Text {
        anchors.left: check.right
        anchors.leftMargin: 12
        anchors.right: actions.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        visible: !row.editing
        text: row.task.text
        elide: Text.ElideRight
        color: row.task.done ? Theme.m3OnSurfaceVariant : Theme.m3OnSurface
        font.family: Theme.fontUi
        font.pixelSize: 14
        font.strikeout: row.task.done

        MouseArea {
            anchors.fill: parent
            onDoubleClicked: row.editRequested()
        }
    }

    TextInput {
        id: input

        anchors.left: check.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: row.editing
        clip: true
        selectByMouse: true
        color: Theme.m3OnSurface
        selectionColor: Theme.m3PrimaryContainer
        selectedTextColor: Theme.m3OnPrimaryContainer
        font.family: Theme.fontUi
        font.pixelSize: 14
        Keys.onReturnPressed: row.committed(text)
        Keys.onEnterPressed: row.committed(text)
        Keys.onEscapePressed: row.cancelled()
        onActiveFocusChanged: if (!activeFocus && row.editing) row.cancelled()
    }

    Row {
        id: actions

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        opacity: hover.hovered && !row.editing ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.short3
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }

        Repeater {
            model: [{ glyph: "\uf040", action: "edit" }, { glyph: "\uf1f8", action: "remove" }]

            Rectangle {
                id: btn

                required property var modelData

                width: 28
                height: 28
                radius: 14
                color: btnArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: btn.modelData.glyph
                    color: Theme.m3OnSurfaceVariant
                    font.family: Theme.fontIcon
                    font.pixelSize: 13
                }

                MouseArea {
                    id: btnArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: btn.modelData.action === "edit" ? row.editRequested() : row.removed()
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.m3OutlineVariant
        opacity: 0.5
    }
}
