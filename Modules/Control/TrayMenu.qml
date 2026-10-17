import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

ColumnLayout {
    id: root

    property var handle: null
    property string title: ""
    property var trail: []
    readonly property var shown: trail.length > 0 ? trail[trail.length - 1] : handle

    signal done

    spacing: 2

    onHandleChanged: trail = []

    QsMenuOpener {
        id: opener

        menu: root.shown
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        text: root.trail.length > 0 ? root.trail[root.trail.length - 1].text : root.title
        elide: Text.ElideRight
        color: Theme.m3OnSurfaceVariant
        font.family: Theme.fontUi
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    ListRow {
        Layout.fillWidth: true
        visible: root.trail.length > 0
        icon: "\uf053"
        label: "Back"
        onClicked: root.trail = root.trail.slice(0, -1)
    }

    Repeater {
        model: opener.children

        delegate: Item {
            id: row

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: modelData.isSeparator ? 9 : 40

            Rectangle {
                visible: row.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: Theme.m3OutlineVariant
            }

            ListRow {
                visible: !row.modelData.isSeparator
                anchors.fill: parent
                enabled: row.modelData.enabled
                opacity: row.modelData.enabled ? 1 : 0.5
                label: row.modelData.text
                active: row.modelData.buttonType !== QsMenuButtonType.None && row.modelData.checkState === Qt.Checked
                trailing: row.modelData.hasChildren ? "\uf054" : ""
                onClicked: {
                    if (row.modelData.hasChildren) {
                        root.trail = root.trail.concat([row.modelData]);
                    } else {
                        row.modelData.triggered();
                        root.done();
                    }
                }
            }
        }
    }
}
