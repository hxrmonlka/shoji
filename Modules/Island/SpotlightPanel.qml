import QtQuick
import Quickshell
import qs.Commons

Item {
    id: root

    property int maxHeight: 520
    property bool active: false
    readonly property bool open: ShellState.spotlight && active

    readonly property var categories: [
        { id: "apps", label: "Apps", placeholder: "Search apps" },
        { id: "settings", label: "Settings", placeholder: "Search settings" },
        { id: "files", label: "Files", placeholder: "Search files and folders" }
    ]
    readonly property var modes: [
        { id: "calc", token: ">calc", label: "Calculator", desc: "Evaluate math with variables", icon: "\uf1ec", placeholder: "Type an expression" },
        { id: "web", token: ">w", label: "Web", desc: "Search the web", icon: "\uf0ac", placeholder: "Search the web" }
    ]
    readonly property var engines: ({
            kagi: { name: "Kagi", url: "https://kagi.com/search?q=" },
            google: { name: "Google", url: "https://www.google.com/search?q=" }
        })
    readonly property var engine: engines[Settings.searchEngine] ?? engines.kagi

    property string category: "apps"
    property string view: "grid"
    property string mode: ""
    property var results: []
    property int selected: -1
    readonly property var activeMode: modes.find(m => m.id === mode) ?? null
    property var lastMode: modes[0]
    onActiveModeChanged: if (activeMode) lastMode = activeMode
    readonly property var activeCategory: categories.find(c => c.id === category) ?? categories[0]

    readonly property int barHeight: 60
    readonly property int cols: 6
    readonly property int tileHeight: 92
    readonly property int rowHeight: 52
    readonly property int headerHeight: 34
    readonly property int listPad: 16
    readonly property int maxList: Math.max(120, maxHeight - barHeight - listPad)
    readonly property bool gridActive: view === "grid" && category === "apps" && mode === "" && results.every(r => r.kind === "header" || r.type === "app")
    readonly property bool viewEnabled: category === "apps" && mode === ""
    readonly property var gridData: gridActive ? buildRows(results) : ({ rows: [], nav: [], pos: [] })
    readonly property bool noResults: results.length === 0 && input.text.trim().length > 0 && !(mode === "" && category === "files" && Files.running)
    readonly property int contentHeight: gridActive ? gridData.rows.reduce((s, r) => s + (r.kind === "header" ? headerHeight : tileHeight), 0) : results.reduce((s, r) => s + (r.kind === "header" ? headerHeight : rowHeight), 0)
    readonly property int listHeight: noResults ? 56 : Math.min(contentHeight, maxList)
    readonly property int wantedHeight: barHeight + (listHeight > 0 ? listHeight + listPad : 0)

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

    function moveGrid(dx, dy) {
        const g = gridData;
        const p = selected >= 0 ? g.pos[selected] : undefined;
        if (!p) {
            selected = firstItem();
            return;
        }
        let target = -1;
        if (dx !== 0) {
            const line = g.nav[p.nav];
            const c = p.col + dx;
            if (c >= 0 && c < line.length) {
                target = line[c];
            } else {
                const n = p.nav + dx;
                if (n >= 0 && n < g.nav.length)
                    target = dx > 0 ? g.nav[n][0] : g.nav[n][g.nav[n].length - 1];
            }
        } else {
            const n = p.nav + dy;
            if (n >= 0 && n < g.nav.length) {
                const line = g.nav[n];
                target = line[Math.min(p.col, line.length - 1)];
            }
        }
        if (target >= 0)
            selected = target;
    }

    function buildRows(list) {
        const rows = [];
        const nav = [];
        const pos = [];
        let current = null;
        list.forEach((r, i) => {
            if (r.kind === "header") {
                rows.push({ kind: "header", title: r.title, number: r.number });
                current = null;
                return;
            }
            if (current === null || current.items.length === cols) {
                current = { kind: "row", items: [] };
                rows.push(current);
                nav.push([]);
            }
            pos[i] = { nav: nav.length - 1, col: current.items.length, row: rows.length - 1 };
            current.items.push({ data: r, index: i });
            nav[nav.length - 1].push(i);
        });
        return { rows: rows, nav: nav, pos: pos };
    }

    function listTop(index) {
        let y = 0;
        for (let k = 0; k < index; k++)
            y += results[k].kind === "header" ? headerHeight : rowHeight;
        return y;
    }

    function gridTop(row) {
        let y = 0;
        for (let k = 0; k < row; k++)
            y += gridData.rows[k].kind === "header" ? headerHeight : tileHeight;
        return y;
    }

    function reveal() {
        if (selected < 0)
            return;
        if (gridActive) {
            const p = gridData.pos[selected];
            if (!p)
                return;
            if (p.nav === 0)
                gridScroll.scrollTo(0);
            else
                gridScroll.reveal(gridTop(p.row), tileHeight);
        } else if (selected === firstItem()) {
            listScroll.scrollTo(0);
        } else {
            listScroll.reveal(listTop(selected), rowHeight);
        }
    }

    function parentDir(path) {
        const home = Quickshell.env("HOME");
        const dir = path.substring(0, path.lastIndexOf("/")) || "/";
        return dir.startsWith(home) ? "~" + dir.substring(home.length) : dir;
    }

    function matchPrefix(text) {
        const lower = text.toLowerCase();
        for (const m of modes) {
            if (!lower.startsWith(m.token))
                continue;
            if (text.length === m.token.length) {
                if (!modes.some(o => o.token !== m.token && o.token.startsWith(m.token)))
                    return { mode: m.id, rest: "" };
                continue;
            }
            if (/\s/.test(text[m.token.length]))
                return { mode: m.id, rest: text.substring(m.token.length + 1) };
        }
        return null;
    }

    function prefixHints(text) {
        const word = text.trim().toLowerCase();
        if (!word.startsWith(">") || /\s/.test(word))
            return [];
        return modes.filter(m => m.token.startsWith(word));
    }

    function setMode(id, rest) {
        mode = id;
        input.text = rest;
        input.cursorPosition = input.text.length;
        syncFiles();
        refresh();
    }

    function clearMode() {
        mode = "";
        syncFiles();
        refresh();
    }

    function setCategory(id) {
        if (mode !== "" || category === id)
            return;
        category = id;
        syncFiles();
        refresh();
    }

    function cycleCategory(step) {
        if (mode !== "")
            return;
        const i = categories.findIndex(c => c.id === category);
        setCategory(categories[(i + step + categories.length) % categories.length].id);
    }

    function syncFiles() {
        Files.search(mode === "" && category === "files" && prefixHints(input.text).length === 0 ? input.text : "");
    }

    function numbered(list) {
        let n = 0;
        return list.map(r => {
            if (r.kind !== "header")
                return r;
            n++;
            return { kind: "header", title: r.title, number: n };
        });
    }

    function appItem(e) {
        return { kind: "item", type: "app", title: e.name, subtitle: e.genericName || e.comment || "", entry: e };
    }

    function settingItem(e) {
        return { kind: "item", type: "setting", title: e.name, subtitle: e.genericName || e.comment || "", entry: e };
    }

    function buildCalc(q) {
        const r = Calc.evaluate(q);
        if (r.empty) {
            const vars = Calc.list();
            if (vars.length === 0)
                return [{ kind: "item", type: "info", glyph: "\uf1ec", title: "Calculator", subtitle: "Try 2^8, sqrt(144), 9\u00b2 or x = 5 then x^2" }];
            const out = [{ kind: "header", title: "Variables" }];
            vars.forEach(v => out.push({ kind: "item", type: "var", glyph: "\uf1ec", title: v.name + " = " + v.text, subtitle: "Enter copies the value, Delete removes it", name: v.name, text: v.text }));
            return out;
        }
        if (!r.ok)
            return [{ kind: "item", type: "info", glyph: "\uf05a", title: r.msg, subtitle: "" }];
        return [
            { kind: "header", title: "Result" },
            { kind: "item", type: "calc", glyph: "\uf1ec", title: r.name.length > 0 ? r.name + " = " + r.text : r.text, subtitle: r.name.length > 0 ? "Press Enter to store " + r.name : "Press Enter to copy", result: r }
        ];
    }

    function buildShoji(text) {
        const q = text.toLowerCase();
        const rows = [];
        if (q.length === 0)
            rows.push({ kind: "item", type: "shojiset", glyph: "\uf013", title: "Open Shoji Settings", subtitle: "Open the settings window", cat: "" });
        Settings.categories.filter(c => q.length === 0 || c.title.toLowerCase().includes(q)).forEach(c => rows.push({ kind: "item", type: "shojiset", glyph: c.icon, title: c.title, subtitle: "Open in Shoji Settings", cat: c.id }));
        if (q.length > 0) {
            Settings.schema.filter(e => (e.label + " " + (e.desc ?? "") + " " + e.key).toLowerCase().includes(q)).slice(0, 8).forEach(e => rows.push({ kind: "item", type: "shojiset", glyph: "\uf013", title: e.label, subtitle: Settings.catTitle(e.cat) + "  /  " + e.section, cat: e.cat }));
        }
        return rows;
    }

    function build(q, cat, activeId, files) {
        const text = q.trim();
        const out = [];
        let n = 0;
        const section = (title, rows) => {
            if (rows.length === 0)
                return;
            n++;
            out.push({ kind: "header", title: title, number: n });
            rows.forEach(r => out.push(r));
        };
        if (activeId === "calc")
            return numbered(buildCalc(q));
        if (activeId === "web") {
            section("Web", [{ kind: "item", type: "web", title: text.length > 0 ? "Search " + engine.name + " for \"" + text + "\"" : "Search " + engine.name, subtitle: text.length > 0 ? "Open in the default browser" : "Type your query", query: text }]);
            return out;
        }
        const hints = prefixHints(text);
        if (hints.length > 0) {
            section("Prefixes", hints.map(m => ({ kind: "item", type: "prefix", glyph: m.icon, title: m.label, subtitle: m.token + "  " + m.desc, mode: m.id })));
            return out;
        }
        if (cat === "apps") {
            if (text.length === 0) {
                const frequent = Apps.frequent();
                const seen = new Set(frequent.map(e => e.id));
                section("Frequently used apps", frequent.map(appItem));
                section("A-Z", Apps.apps.filter(e => !seen.has(e.id)).map(appItem));
            } else {
                section("Apps", Apps.find(text, false, 200).map(appItem));
            }
        } else if (cat === "settings") {
            section("Shoji settings", buildShoji(text));
            const system = text.length === 0 ? Apps.settingsEntries.slice(0, 60) : Apps.find(text, true, 30);
            section("System settings", system.map(settingItem));
        } else if (text.length < 2) {
            out.push({ kind: "item", type: "info", glyph: "\uf002", title: "Search files and folders", subtitle: "Type at least 2 characters" });
        } else {
            section("Folders", files.filter(f => f.dir).map(f => ({ kind: "item", type: "file", title: f.name, subtitle: parentDir(f.path), path: f.path, dir: true })));
            section("Files", files.filter(f => !f.dir).map(f => ({ kind: "item", type: "file", title: f.name, subtitle: parentDir(f.path), path: f.path, dir: false })));
        }
        return out;
    }

    function refresh() {
        results = build(input.text, category, mode, Files.results);
        selected = firstItem();
        listScroll.reset();
        gridScroll.reset();
    }

    function activate(item) {
        if (item.type === "info")
            return;
        if (item.type === "prefix") {
            setMode(item.mode, "");
            return;
        }
        if (item.type === "calc") {
            Calc.commit(item.result);
            if (item.result.name.length > 0) {
                input.text = "";
                return;
            }
            Quickshell.execDetached(["wl-copy", item.result.text]);
        } else if (item.type === "var") {
            Quickshell.execDetached(["wl-copy", item.text]);
        } else if (item.type === "shojiset") {
            ShellState.openSettings(item.cat);
            return;
        } else if (item.type === "web") {
            if (item.query.length === 0)
                return;
            Quickshell.execDetached(["xdg-open", engine.url + encodeURIComponent(item.query)]);
        } else if (item.type === "file") {
            Quickshell.execDetached(["xdg-open", item.path]);
        } else {
            Frecency.record(item.entry.id);
            item.entry.execute();
        }
        ShellState.spotlight = false;
    }

    function discard() {
        if (selected < 0 || selected >= results.length)
            return;
        const item = results[selected];
        if (item.type === "var") {
            Calc.remove(item.name);
            refresh();
        }
    }

    onOpenChanged: {
        if (open) {
            mode = "";
            category = "apps";
            view = Settings.spotlightView;
            input.text = "";
            syncFiles();
            refresh();
            Qt.callLater(() => input.forceActiveFocus());
        }
    }
    onSelectedChanged: Qt.callLater(reveal)
    onViewChanged: {
        listScroll.reset();
        gridScroll.reset();
        Qt.callLater(reveal);
    }
    Component.onCompleted: refresh()

    Connections {
        target: Files

        function onResultsChanged() {
            if (root.category === "files" && root.mode === "")
                root.refresh();
        }
    }

    Connections {
        target: Apps

        function onAllChanged() {
            root.refresh();
        }
    }

    component Chip: Item {
        id: chip

        property string label: ""
        property bool current: false

        readonly property bool pressed: chipArea.pressed

        signal clicked

        height: 30
        width: chipLabel.implicitWidth + 24

        Squash {
            id: chipSquash

            pressed: chipArea.pressed
        }

        Rectangle {
            id: chipBg

            anchors.fill: parent
            radius: 15
            color: chipFill.color
            transform: Scale {
                origin.x: chipBg.width / 2
                origin.y: chipBg.height / 2
                xScale: chipSquash.xScale
                yScale: chipSquash.yScale
            }
        }

        ColorSpring {
            id: chipText

            target: chip.current ? Theme.m3OnPrimaryContainer : Theme.m3OnSurfaceVariant
        }

        ColorSpring {
            id: chipFill

            target: !chip.current && chipArea.containsMouse ? Theme.glassInner(Theme.m3SurfaceContainerHighest) : "transparent"
        }

        Text {
            id: chipLabel

            anchors.centerIn: parent
            text: chip.label
            color: chipText.color
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        MouseArea {
            id: chipArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    Item {
        id: bar

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.barHeight

        Text {
            id: glass

            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            text: root.activeMode ? root.activeMode.icon : "\uf002"
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontIcon
            font.pixelSize: 18
        }

        Spring {
            id: badgeSpring

            target: root.activeMode ? 1 : 0
            token: Motion.spatialDefault
            epsilon: 0.001
        }

        Rectangle {
            id: badge

            anchors.left: glass.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, (badgeLabel.implicitWidth + 24) * badgeSpring.value)
            height: 30
            radius: 15
            clip: true
            visible: width > 0.5
            opacity: Motion.clamp01(badgeSpring.value)
            color: Theme.m3PrimaryContainer

            Text {
                id: badgeLabel

                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.lastMode.label
                color: Theme.m3OnPrimaryContainer
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Row {
            id: controls

            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Item {
                id: chipBox

                property real targetL: 0
                property real targetR: 0
                property bool currentPressed: false

                width: chipRow.width
                height: 30
                visible: root.mode === ""

                SlidePill {
                    from: chipBox.targetL
                    to: chipBox.targetR
                    pressed: chipBox.currentPressed
                }

                Row {
                    id: chipRow

                    spacing: 2

                    Repeater {
                        model: root.categories

                        delegate: Chip {
                            id: chipItem

                            required property var modelData

                            function sync() {
                                if (!current)
                                    return;
                                chipBox.targetL = x;
                                chipBox.targetR = x + width;
                            }

                            label: modelData.label
                            current: root.category === modelData.id
                            onClicked: root.setCategory(modelData.id)
                            onCurrentChanged: sync()
                            onXChanged: sync()
                            onWidthChanged: sync()
                            onPressedChanged: if (current) chipBox.currentPressed = pressed
                            Component.onCompleted: sync()
                        }
                    }
                }
            }

            Item {
                width: 13
                height: 30
                visible: root.mode === ""

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 18
                    color: Theme.m3OutlineVariant
                }
            }

            Item {
                id: viewBox

                readonly property bool grid: root.view === "grid"

                width: 64
                height: 30
                visible: root.mode === ""
                enabled: root.viewEnabled
                opacity: root.viewEnabled ? 1 : 0.35

                SlidePill {
                    from: viewBox.grid ? 0 : 34
                    to: viewBox.grid ? 30 : 64
                    pressed: viewBox.grid ? gridButton.pressed : listButton.pressed
                }

                IconButton {
                    id: gridButton

                    x: 0
                    width: 30
                    height: 30
                    icon: "\uf00a"
                    iconSize: 13
                    squash: true
                    plain: true
                    active: viewBox.grid
                    onClicked: root.view = "grid"
                }

                IconButton {
                    id: listButton

                    x: 34
                    width: 30
                    height: 30
                    icon: "\uf0ca"
                    iconSize: 13
                    squash: true
                    plain: true
                    active: !viewBox.grid
                    onClicked: root.view = "list"
                }
            }
        }

        TextInput {
            id: input

            anchors.left: glass.right
            anchors.leftMargin: 14 + badge.width + 8 * Motion.clamp01(badgeSpring.value)
            anchors.right: controls.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            selectByMouse: true
            color: Theme.m3OnSurface
            selectionColor: Theme.m3PrimaryContainer
            selectedTextColor: Theme.m3OnPrimaryContainer
            font.family: Theme.fontUi
            font.pixelSize: 20
            onTextChanged: {
                if (root.mode === "") {
                    const m = root.matchPrefix(text);
                    if (m) {
                        root.setMode(m.mode, m.rest);
                        return;
                    }
                }
                root.syncFiles();
                root.refresh();
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Backspace && root.mode !== "" && input.selectionStart === input.selectionEnd && input.cursorPosition === 0) {
                    root.clearMode();
                    event.accepted = true;
                }
            }
            Keys.onDeletePressed: root.discard()
            Keys.onDownPressed: root.gridActive ? root.moveGrid(0, 1) : root.move(1)
            Keys.onUpPressed: root.gridActive ? root.moveGrid(0, -1) : root.move(-1)
            Keys.onLeftPressed: event => {
                event.accepted = root.gridActive;
                if (root.gridActive)
                    root.moveGrid(-1, 0);
            }
            Keys.onRightPressed: event => {
                event.accepted = root.gridActive;
                if (root.gridActive)
                    root.moveGrid(1, 0);
            }
            Keys.onTabPressed: event => {
                root.cycleCategory(1);
                event.accepted = true;
            }
            Keys.onBacktabPressed: event => {
                root.cycleCategory(-1);
                event.accepted = true;
            }
            Keys.onReturnPressed: if (root.selected >= 0) root.activate(root.results[root.selected])
            Keys.onEnterPressed: if (root.selected >= 0) root.activate(root.results[root.selected])
            Keys.onEscapePressed: ShellState.spotlight = false

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0 && input.preeditText.length === 0
                text: root.activeMode ? root.activeMode.placeholder : root.activeCategory.placeholder
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
        visible: root.listHeight > 0
    }

    ListView {
        id: list

        anchors.top: bar.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        visible: !root.gridActive
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        model: root.gridActive ? [] : root.results

        delegate: ResultRow {
            width: ListView.view.width
            selected: index === root.selected
            onHovered: root.selected = index
            onActivated: root.activate(modelData)
        }
    }

    ListView {
        id: gridList

        anchors.top: bar.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        visible: root.gridActive
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        model: root.gridData.rows

        delegate: Item {
            id: gridRow

            required property var modelData
            required property int index
            readonly property bool isHeader: modelData.kind === "header"
            readonly property real cell: Math.floor((width - 20) / root.cols)

            width: ListView.view.width
            height: isHeader ? root.headerHeight : root.tileHeight

            SectionHeader {
                anchors.fill: parent
                visible: gridRow.isHeader
                number: gridRow.modelData.number ?? 0
                title: gridRow.isHeader ? gridRow.modelData.title : ""
            }

            Row {
                x: 10
                height: parent.height
                visible: !gridRow.isHeader

                Repeater {
                    model: gridRow.isHeader ? [] : gridRow.modelData.items

                    delegate: Item {
                        id: tile

                        required property var modelData
                        readonly property bool selected: modelData.index === root.selected

                        width: gridRow.cell
                        height: root.tileHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 16
                            color: tileFill.color

                            ColorSpring {
                                id: tileFill

                                target: tile.selected ? Theme.m3PrimaryContainer : "transparent"
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 12
                            spacing: 6

                            AppIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: 44
                                icon: tile.modelData.data.entry.icon
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: tile.modelData.data.title
                                elide: Text.ElideRight
                                color: tile.selected ? Theme.m3OnPrimaryContainer : Theme.m3OnSurface
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: root.selected = tile.modelData.index
                            onClicked: root.activate(tile.modelData.data)
                        }
                    }
                }
            }
        }
    }

    SmoothScroll {
        id: listScroll

        anchors.fill: list
        view: list
        contentSize: root.contentHeight
        enabled: !root.gridActive
    }

    SmoothScroll {
        id: gridScroll

        anchors.fill: gridList
        view: gridList
        contentSize: root.contentHeight
        enabled: root.gridActive
    }

    Text {
        anchors.top: bar.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        visible: root.noResults
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "No results"
        color: Theme.m3OnSurfaceVariant
        font.family: Theme.fontUi
        font.pixelSize: 14
    }
}
