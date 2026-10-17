pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool wifiEnabled: false
    property var networks: []
    property var vpns: []

    readonly property var active: networks.find(n => n.active) ?? null
    readonly property string ssid: active ? active.ssid : ""
    readonly property var activeVpns: vpns.filter(v => v.active)
    readonly property bool vpnActive: activeVpns.length > 0
    readonly property string connectScript: 'nmcli -w 20 connection up id "$1" || nmcli -w 20 device wifi connect "$1"'

    function split(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                cur += line[++i];
            } else if (c === ":") {
                out.push(cur);
                cur = "";
            } else {
                cur += c;
            }
        }
        out.push(cur);
        return out;
    }

    function refresh() {
        if (!radio.running)
            radio.running = true;
        if (!wifi.running)
            wifi.running = true;
        if (!conns.running)
            conns.running = true;
    }

    function setWifi(on) {
        wifiEnabled = on;
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        settle.restart();
    }

    function connect(name) {
        Quickshell.execDetached(["sh", "-c", connectScript, "sh", name]);
        settle.restart();
    }

    function setVpn(name, on) {
        Quickshell.execDetached(["nmcli", "connection", on ? "up" : "down", "id", name]);
        settle.restart();
    }

    function parseWifi(text) {
        const seen = {};
        const list = [];
        text.split("\n").forEach(line => {
            if (line.length === 0)
                return;
            const f = split(line);
            const name = f[1];
            if (!name || (seen[name] !== undefined && !(f[0] === "*")))
                return;
            const entry = { ssid: name, signal: parseInt(f[2]) || 0, secure: (f[3] || "").length > 0, active: f[0] === "*" };
            if (seen[name] !== undefined)
                list[seen[name]] = entry;
            else {
                seen[name] = list.length;
                list.push(entry);
            }
        });
        list.sort((a, b) => (Number(b.active) - Number(a.active)) || (b.signal - a.signal));
        networks = list;
    }

    function parseConns(text) {
        vpns = text.split("\n").filter(l => l.length > 0).map(l => split(l)).filter(f => f[1] === "vpn" || f[1] === "wireguard").map(f => ({ name: f[0], active: (f[2] || "").length > 0 }));
    }

    readonly property Timer settle: Timer {
        interval: 2000
        onTriggered: root.refresh()
    }

    readonly property Timer poll: Timer {
        interval: 5000
        repeat: true
        running: ShellState.control
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    readonly property Process radio: Process {
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: root.wifiEnabled = text.trim() === "enabled"
        }
    }

    readonly property Process wifi: Process {
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.parseWifi(text)
        }
    }

    readonly property Process conns: Process {
        command: ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.parseConns(text)
        }
    }
}
