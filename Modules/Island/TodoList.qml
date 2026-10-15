import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
    id: root

    required property date day
    property int editingId: -1
    readonly property var tasks: Todos.forDate(day)
    readonly property bool isToday: Todos.key(day) === Todos.key(ShellState.clock.date)

    function submit() {
        Todos.add(day, addInput.text);
        addInput.text = "";
    }

    spacing: 10
    Keys.onEscapePressed: ShellState.expanded = false
    onDayChanged: editingId = -1

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: "Tasks"
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }

            Text {
                text: Qt.formatDate(root.day, "dddd, MMM d")
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
        }

        Rectangle {
            visible: root.isToday
            Layout.preferredWidth: todayLabel.implicitWidth + 16
            Layout.preferredHeight: 22
            radius: 11
            color: Theme.m3PrimaryContainer

            Text {
                id: todayLabel

                anchors.centerIn: parent
                text: "Today"
                color: Theme.m3OnPrimaryContainer
                font.family: Theme.fontUi
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.m3OutlineVariant
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ListView {
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.tasks

            delegate: TaskRow {
                width: ListView.view.width
                editing: root.editingId === modelData.id
                onToggled: Todos.toggle(modelData.id)
                onRemoved: Todos.remove(modelData.id)
                onEditRequested: root.editingId = modelData.id
                onCommitted: text => {
                    Todos.edit(modelData.id, text);
                    root.editingId = -1;
                    root.forceActiveFocus();
                }
                onCancelled: {
                    root.editingId = -1;
                    root.forceActiveFocus();
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.tasks.length === 0
            text: "No tasks for this day"
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 13
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.m3OutlineVariant
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: 20
        color: "transparent"
        border.width: 1
        border.color: addBorder.color

        ColorSpring {
            id: addBorder

            target: addInput.activeFocus ? Theme.m3Primary : Theme.m3OutlineVariant
        }

        TextInput {
            id: addInput

            anchors.left: parent.left
            anchors.right: addButton.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16
            anchors.rightMargin: 8
            clip: true
            selectByMouse: true
            color: Theme.m3OnSurface
            selectionColor: Theme.m3PrimaryContainer
            selectedTextColor: Theme.m3OnPrimaryContainer
            font.family: Theme.fontUi
            font.pixelSize: 14
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
            Keys.onEscapePressed: {
                text = "";
                root.forceActiveFocus();
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: addInput.text.length === 0 && addInput.preeditText.length === 0
                text: "Add a task"
                color: Theme.m3OnSurfaceVariant
                font: addInput.font
            }
        }

        Rectangle {
            id: addButton

            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            radius: 14
            color: Theme.m3Primary

            Text {
                anchors.centerIn: parent
                text: "\uf067"
                color: Theme.m3OnPrimary
                font.family: Theme.fontIcon
                font.pixelSize: 12
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.submit()
            }
        }
    }
}
