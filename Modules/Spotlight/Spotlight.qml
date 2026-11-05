import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: win

    readonly property bool open: ShellState.spotlight
    readonly property string query: input.text
    readonly property var results: build(query, Files.results, mode)
    readonly property bool noResults: results.length === 0 && (mode === "" ? query.trim().length > 0 && !Files.running : mode === "clipboard" || mode === "settings")
    readonly property string noResultsText: mode === "clipboard" && query.trim().length === 0 ? "Clipboard is empty" : "No results"
    readonly property var modes: [
        { id: "clipboard", token: ">c", label: "Clipboard", desc: "Search the clipboard history", icon: "\uf328", placeholder: "Search clipboard" },
        { id: "calc", token: ">calc", label: "Calculator", desc: "Evaluate math with variables", icon: "\uf1ec", placeholder: "Type an expression" },
        { id: "settings", token: ">settings", label: "Shoji Settings", desc: "Jump to a Shoji setting", icon: "\uf013", placeholder: "Search Shoji settings" },
        { id: "web", token: ">w", label: "Web", desc: "Search the web", icon: "\uf0ac", placeholder: "Search the web" }
    ]
    property string mode: ""
    readonly property var activeMode: modes.find(m => m.id === mode) ?? null
    property var lastMode: modes[0]
    onActiveModeChanged: if (activeMode) lastMode = activeMode
    readonly property var engines: ({
            kagi: { name: "Kagi", url: "https://kagi.com/search?q=" },
            google: { name: "Google", url: "https://www.google.com/search?q=" }
        })
    readonly property var engine: engines[Settings.searchEngine] ?? engines.kagi
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
        if (id === "clipboard")
            ClipboardHistory.refresh();
    }

    function clearMode() {
        mode = "";
        Files.search(input.text);
    }

    function oneLine(s) {
        return s.replace(/\s+/g, " ").trim();
    }

    function buildClipboard(text) {
        const needle = text.toLowerCase();
        const entries = ClipboardHistory.entries.filter(e => needle.length === 0 || e.preview.toLowerCase().includes(needle)).slice(0, 40);
        if (entries.length === 0)
            return [];
        const out = [{ kind: "header", title: "Clipboard" }];
        entries.forEach(e => {
            const image = e.kind === "image";
            const files = e.kind === "files";
            out.push({
                kind: "item",
                type: "clip",
                glyph: image ? "\uf03e" : files ? "\uf0c5" : "\uf328",
                title: image ? "Image" : files ? (e.count > 1 ? e.count + " files" : "File") : oneLine(e.preview),
                subtitle: image ? e.ext.toUpperCase() + "  " + e.dims + "  " + e.size : files ? e.preview : "",
                clip: e
            });
        });
        return out;
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

    function buildSettings(text) {
        const q = text.toLowerCase();
        const out = [];
        const cats = Settings.categories.filter(c => q.length === 0 || c.title.toLowerCase().includes(q));
        if (q.length === 0)
            out.push({ kind: "header", title: "Shoji Settings" }, { kind: "item", type: "shojiset", glyph: "\uf013", title: "Open Shoji Settings", subtitle: "Open the settings window", cat: "" });
        if (cats.length > 0) {
            out.push({ kind: "header", title: "Categories" });
            cats.forEach(c => out.push({ kind: "item", type: "shojiset", glyph: c.icon, title: c.title, subtitle: "Open in Shoji Settings", cat: c.id }));
        }
        if (q.length > 0) {
            const hits = Settings.schema.filter(e => (e.label + " " + (e.desc ?? "") + " " + e.key).toLowerCase().includes(q)).slice(0, 8);
            if (hits.length > 0) {
                out.push({ kind: "header", title: "Settings" });
                hits.forEach(e => out.push({ kind: "item", type: "shojiset", glyph: "\uf013", title: e.label, subtitle: Settings.catTitle(e.cat) + "  /  " + e.section, cat: e.cat }));
            }
        }
        return out;
    }

    function build(q, files, activeId) {
        const text = q.trim();
        const out = [];
        if (activeId === "clipboard")
            return buildClipboard(text);
        if (activeId === "calc")
            return buildCalc(q);
        if (activeId === "settings")
            return buildSettings(text);
        if (activeId === "web") {
            out.push({ kind: "header", title: "Web" });
            out.push({ kind: "item", type: "web", title: text.length > 0 ? "Search " + engine.name + " for \"" + text + "\"" : "Search " + engine.name, subtitle: text.length > 0 ? "Open in the default browser" : "Type your query", query: text });
            return out;
        }
        if (text.length === 0)
            return out;
        const hints = prefixHints(text);
        if (hints.length > 0) {
            out.push({ kind: "header", title: "Prefixes" });
            hints.forEach(m => out.push({ kind: "item", type: "prefix", glyph: m.icon, title: m.label, subtitle: m.token + "  " + m.desc, mode: m.id }));
            return out;
        }
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
        } else if (item.type === "var")
            Quickshell.execDetached(["wl-copy", item.text]);
        else if (item.type === "clip")
            ClipboardHistory.copy(item.clip);
        else if (item.type === "shojiset") {
            ShellState.openSettings(item.cat);
            return;
        } else if (item.type === "web") {
            if (item.query.length === 0)
                return;
            Quickshell.execDetached(["xdg-open", engine.url + encodeURIComponent(item.query)]);
        } else if (item.type === "file")
            Quickshell.execDetached(["xdg-open", item.path]);
        else
            item.entry.execute();
        ShellState.spotlight = false;
    }

    function discard() {
        if (selected < 0 || selected >= results.length)
            return;
        const item = results[selected];
        if (item.type === "clip")
            ClipboardHistory.remove(item.clip);
        else if (item.type === "var")
            Calc.remove(item.name);
    }

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open || fade.value > 0.001 || pop.running

    WlrLayershell.namespace: "shoji-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            ShellState.expanded = false;
            mode = "";
            input.text = "";
            input.forceActiveFocus();
        }
    }
    onResultsChanged: selected = firstItem()

    Spring {
        id: pop

        target: win.open ? 1 : 0
        token: Motion.spatialDefault
        epsilon: 0.0005
    }

    Spring {
        id: fade

        target: win.open ? 1 : 0
        token: Motion.effectsDefault
        epsilon: 0.0005
    }

    Spring {
        id: grow

        target: win.barHeight + (win.listHeight > 0 ? win.listHeight + 21 : 0)
        token: Motion.spatialDefault
        epsilon: 0.05
    }

    MouseArea {
        anchors.fill: parent
        onClicked: ShellState.spotlight = false
    }

    Rectangle {
        id: card

        width: 680
        height: Math.max(win.barHeight, grow.value)
        x: (win.width - width) / 2
        y: win.height * 0.45 - win.barHeight / 2
        radius: 30
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant
        clip: true
        opacity: Motion.clamp01(fade.value)
        scale: Motion.lerp(0.94, 1, pop.value)
        transformOrigin: Item.Top

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
                text: win.activeMode ? win.activeMode.icon : "\uf002"
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontIcon
                font.pixelSize: 18
            }

            Spring {
                id: badgeSpring

                target: win.activeMode ? 1 : 0
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
                    text: win.lastMode.label
                    color: Theme.m3OnPrimaryContainer
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            TextInput {
                id: input

                anchors.left: glass.right
                anchors.leftMargin: 14 + badge.width + 8 * Motion.clamp01(badgeSpring.value)
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
                onTextChanged: {
                    if (win.mode === "") {
                        const m = win.matchPrefix(text);
                        if (m) {
                            win.setMode(m.mode, m.rest);
                            return;
                        }
                    }
                    Files.search(win.mode === "" && win.prefixHints(text).length === 0 ? text : "");
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Backspace && win.mode !== "" && input.selectionStart === input.selectionEnd && input.cursorPosition === 0) {
                        win.clearMode();
                        event.accepted = true;
                    }
                }
                Keys.onDeletePressed: win.discard()
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
                    text: win.activeMode ? win.activeMode.placeholder : "Spotlight Search"
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
            text: win.noResultsText
            color: Theme.m3OnSurfaceVariant
            font.family: Theme.fontUi
            font.pixelSize: 14
        }
    }
}
