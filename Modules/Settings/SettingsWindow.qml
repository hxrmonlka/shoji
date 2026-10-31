import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

FloatingWindow {
    id: win

    property string category: Settings.categories[0].id
    property string query: ""

    readonly property bool searching: query.trim().length > 0
    readonly property var sections: {
        const q = query.trim().toLowerCase();
        const out = [];
        const index = {};
        Settings.schema.forEach(e => {
            if (q.length > 0) {
                const hay = (e.label + " " + (e.desc ?? "") + " " + e.key).toLowerCase();
                if (hay.indexOf(q) < 0)
                    return;
            } else if (e.cat !== win.category) {
                return;
            }
            const title = q.length > 0 ? Settings.catTitle(e.cat) + "  /  " + e.section : e.section;
            if (!(title in index)) {
                index[title] = out.length;
                out.push({ title: title, items: [] });
            }
            out[index[title]].items.push(e);
        });
        return out;
    }

    function pick(id: string): void {
        search.text = "";
        query = "";
        category = id;
        page.scrollTop();
    }

    title: "Shoji Settings"
    implicitWidth: 960
    implicitHeight: 680
    minimumSize: Qt.size(720, 480)
    color: Theme.m3Surface
    onClosed: ShellState.settingsOpen = false

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.settingsOpen = false

        Rectangle {
            id: side

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 248
            color: Theme.m3SurfaceContainer

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 10
                    spacing: 10

                    Text {
                        text: "\uf013"
                        color: Theme.m3Primary
                        font.family: Theme.fontIcon
                        font.pixelSize: 20
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Shoji"
                        color: Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    Layout.bottomMargin: 8
                    radius: 20
                    color: Theme.m3SurfaceContainerHigh
                    border.width: search.activeFocus ? 2 : 0
                    border.color: Theme.m3Primary

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf002"
                        color: Theme.m3OnSurfaceVariant
                        font.family: Theme.fontIcon
                        font.pixelSize: 13
                    }

                    TextInput {
                        id: search

                        anchors.fill: parent
                        anchors.leftMargin: 38
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        color: Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        onTextEdited: {
                            win.query = text;
                            page.scrollTop();
                        }
                        Keys.onEscapePressed: {
                            if (text.length > 0) {
                                text = "";
                                win.query = "";
                            } else {
                                ShellState.settingsOpen = false;
                            }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 38
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text.length === 0
                        text: "Search settings"
                        color: Qt.alpha(Theme.m3OnSurfaceVariant, 0.7)
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                    }
                }

                Repeater {
                    model: Settings.categories

                    Rectangle {
                        id: entry

                        required property var modelData
                        readonly property bool current: !win.searching && win.category === modelData.id

                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 22
                        color: fill.color

                        ColorSpring {
                            id: fill

                            target: entry.current ? Theme.m3PrimaryContainer : entryArea.containsMouse ? Theme.m3SurfaceContainerHighest : "transparent"
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            text: entry.modelData.icon
                            color: entry.current ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
                            font.family: Theme.fontIcon
                            font.pixelSize: 15
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 50
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.title
                            color: entry.current ? Theme.m3OnPrimaryContainer : Theme.m3OnSurface
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            font.weight: entry.current ? Font.DemiBold : Font.Medium
                        }

                        Ripple {
                            id: ripple1

                            anchors.fill: parent
                            radius: parent.radius
                        }

                        MouseArea {
                            id: entryArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => ripple1.press(entryArea, mouse)
                            onClicked: win.pick(entry.modelData.id)
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 20
                    color: allFill.color

                    ColorSpring {
                        id: allFill

                        target: allArea.containsMouse ? Theme.m3SurfaceContainerHighest : Theme.m3SurfaceContainerHigh
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "Reset all settings"
                        color: Theme.m3OnSurface
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Ripple {
                        id: ripple2

                        anchors.fill: parent
                        radius: parent.radius
                    }

                    MouseArea {
                        id: allArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => ripple2.press(allArea, mouse)
                        onClicked: Settings.reset()
                    }
                }
            }
        }

        SettingsPage {
            id: page

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: side.right
            anchors.right: parent.right
            title: win.searching ? "Search results" : Settings.catTitle(win.category)
            sections: win.sections
            resettable: !win.searching
            onResetRequested: Settings.resetCategory(win.category)
        }
    }
}
