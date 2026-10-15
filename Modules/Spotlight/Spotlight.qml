import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: win

    readonly property bool open: ShellState.spotlight
    readonly property string query: input.text
    readonly property var results: build(query, Files.results)
    readonly property bool noResults: query.trim().length > 0 && results.length === 0 && !Files.running
    readonly property int barHeight: 60
    readonly property int maxList: Math.max(120, Math.min(420, height - (height * 0.45 - barHeight / 2) - barHeight - 45))
    readonly property int listHeight: noResults ? 56 : Math.min(list.contentHeight, maxList)
    property int selected: -1

    function firstItem() {
        return results.findIndex(r => r.kind === "item");
    }

    function move(step) {
        let i = selected;
        do {
            i += step;
        } while (i >= 0 && i < results.length && results[i].kind === "header");
        if (i >= 0 && i < results.length)
            selected = i;
    }

    function parentDir(path) {
        const home = Quickshell.env("HOME");
        const dir = path.substring(0, path.lastIndexOf("/")) || "/";
        return dir.startsWith(home) ? "~" + dir.substring(home.length) : dir;
    }

    function build(q, files) {
        const text = q.trim();
        const out = [];
        if (text.length === 0)
            return out;
        const section = (title, rows) => {
            if (rows.length === 0)
                return;
            out.push({ kind: "header", title: title });
            rows.forEach(r => out.push(r));
        };
        section("Apps", Apps.find(text, false, 6).map(e => ({ kind: "item", type: "app", title: e.name, subtitle: e.genericName || e.comment || "", entry: e })));
        section("Settings", Apps.find(text, true, 4).map(e => ({ kind: "item", type: "setting", title: e.name, subtitle: e.genericName || e.comment || "", entry: e })));
        section("Files", files.map(f => ({ kind: "item", type: "file", title: f.name, subtitle: parentDir(f.path), path: f.path, dir: f.dir })));
        return out;
    }

    function activate(item) {
        if (item.type === "file")
            Quickshell.execDetached(["xdg-open", item.path]);
        else
            item.entry.execute();
        ShellState.spotlight = false;
    }

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || card.opacity > 0

    WlrLayershell.namespace: "shoji-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            ShellState.expanded = false;
            input.text = "";
            input.forceActiveFocus();
        }
    }
    onResultsChanged: selected = firstItem()

    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.spotlight = false
    }

    Rectangle {
        id: card

        width: 680
        height: win.barHeight + (win.listHeight > 0 ? win.listHeight + 21 : 0)
        x: (win.width - width) / 2
        y: win.height * 0.45 - win.barHeight / 2
        radius: 30
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant
        clip: true
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.96
        transformOrigin: Item.Top

        Behavior on height {
            NumberAnimation {
                duration: Motion.medium2
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.emphasized
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: win.open ? Motion.medium2 : Motion.short3
                easing.type: Easing.BezierSpline
                easing.bezierCurve: win.open ? Motion.emphasizedDecelerate : Motion.emphasizedAccelerate
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: win.open ? Motion.medium2 : Motion.short3
                easing.type: Easing.BezierSpline
                easing.bezierCurve: win.open ? Motion.emphasizedDecelerate : Motion.emphasizedAccelerate
            }
        }

        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: bar

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: win.barHeight

            Text {
                id: glass

                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontIcon
                font.pixelSize: 18
            }

            TextInput {
                id: input

                anchors.left: glass.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                selectByMouse: true
                color: Theme.m3OnSurface
                selectionColor: Theme.m3PrimaryContainer
                selectedTextColor: Theme.m3OnPrimaryContainer
                font.family: Theme.fontUi
                font.pixelSize: 22
                onTextChanged: Files.search(text)
                Keys.onDownPressed: win.move(1)
                Keys.onUpPressed: win.move(-1)
                Keys.onTabPressed: win.move(1)
                Keys.onBacktabPressed: win.move(-1)
                Keys.onReturnPressed: if (win.selected >= 0) win.activate(win.results[win.selected])
                Keys.onEnterPressed: if (win.selected >= 0) win.activate(win.results[win.selected])
                Keys.onEscapePressed: ShellState.spotlight = false

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0 && input.preeditText.length === 0
                    text: "Spotlight Search"
                    color: Theme.m3OnSurfaceVariant
                    font: input.font
                }
            }
        }

        Rectangle {
            anchors.top: bar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            height: 1
            color: Theme.m3OutlineVariant
            visible: win.listHeight > 0
        }

        ListView {
            id: list

            anchors.top: bar.bottom
            anchors.topMargin: 11
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: win.results
            currentIndex: win.selected
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: ResultRow {
                width: ListView.view.width
                selected: index === win.selected
                onHovered: win.selected = index
                onActivated: win.activate(modelData)
            }
        }

        Text {
            anchors.top: bar.bottom
            anchors.topMargin: 11
            anchors.left: parent.left
            anchors.right: parent.right
            height: 56
            visible: win.noResults
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "No results"
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 14
        }
    }
}
