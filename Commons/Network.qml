pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool radioOn: false
    property bool devUp: false
    property var pendingWifi: null
    property var networks: []
    property var vpns: []
    property var saved: ({})
    property string connecting: ""
    property string prompt: ""
    property bool promptEap: false
    property string error: ""
    property string jobKind: ""
    property string jobInput: ""
    property string jobErr: ""
    property bool holding: false

    readonly property bool wifiEnabled: pendingWifi !== null ? pendingWifi : (radioOn || devUp)
    readonly property var active: networks.find(n => n.active) ?? null
    readonly property string ssid: active ? active.ssid : ""
    readonly property var activeVpns: vpns.filter(v => v.active)
    readonly property bool vpnActive: activeVpns.length > 0
    readonly property bool open: ShellState.control || (ShellState.expanded && ShellState.tab === "control")
    readonly property var env: ({ LC_ALL: "C.UTF-8" })

    readonly property string forgetFn: 'forget() { nmcli -t -f UUID,TYPE connection show | while IFS=: read -r u t; do [ "$t" = 802-11-wireless ] || continue; [ "$(nmcli -g 802-11-wireless.ssid connection show uuid "$u")" = "$1" ] && nmcli connection delete uuid "$u" >/dev/null; done; }; '
    readonly property string newScript: forgetFn + 'ssid="$1"; forget "$ssid"; nmcli -w 30 --ask device wifi connect "$ssid" || { forget "$ssid" >/dev/null 2>&1; exit 1; }'
    readonly property string eapScript: forgetFn + 'ssid="$1"; forget "$ssid"; nmcli connection add type wifi ifname "*" con-name "$ssid" ssid "$ssid" wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity "$2" >/dev/null || exit 1; nmcli -w 30 --ask connection up id "$ssid" || { forget "$ssid" >/dev/null 2>&1; exit 1; }'
    readonly property string savedScript: 'nmcli -t -f UUID,TYPE connection show | while IFS=: read -r u t; do [ "$t" = 802-11-wireless ] || continue; o=$(nmcli -g 802-11-wireless.ssid,802-11-wireless-security.psk-flags,802-11-wireless-security.key-mgmt connection show uuid "$u"); printf "%s\\t%s\\t%s\\t%s\\n" "$u" "$(printf %s "$o" | sed -n 2p)" "$(printf %s "$o" | sed -n 3p)" "$(printf %s "$o" | sed -n 1p)"; done'

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

    function refresh(withSaved) {
        if (!radio.running)
            radio.running = true;
        if (!devs.running)
            devs.running = true;
        if (!wifi.running)
            wifi.running = true;
        if (!conns.running)
            conns.running = true;
        if (withSaved && !savedProc.running)
            savedProc.running = true;
    }

    function setWifi(on) {
        pendingWifi = on;
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        pending.restart();
    }

    function setHold(on) {
        if (on === holding)
            return;
        holding = on;
        ShellState.hold(on);
    }

    function askFor(name, eap) {
        promptEap = eap;
        prompt = name;
    }

    function cancelPrompt() {
        if (connecting !== "")
            return;
        prompt = "";
        error = "";
        ShellState.reclaimFocus();
    }

    function run(cmd, name, kind, input) {
        connecting = name;
        jobKind = kind;
        jobInput = input;
        jobErr = "";
        job.command = cmd;
        job.running = true;
    }

    function connect(name) {
        if (connecting !== "")
            return;
        const n = networks.find(x => x.ssid === name);
        if (!n || n.active)
            return;
        error = "";
        prompt = "";
        const p = saved[name];
        if (p && (!n.secure || ((parseInt(p.flags) || 0) & 3) === 0))
            run(["nmcli", "-w", "30", "connection", "up", "uuid", p.uuid], name, "saved", "");
        else if (!n.secure)
            run(["nmcli", "-w", "30", "device", "wifi", "connect", name], name, "open", "");
        else
            askFor(name, n.eap);
    }

    function submit(password, identity) {
        if (prompt === "" || connecting !== "")
            return;
        if (promptEap) {
            if (identity.length === 0 || password.length === 0) {
                error = "Enter username and password";
                return;
            }
            error = "";
            run(["sh", "-c", eapScript, "sh", prompt, identity], prompt, "eap", password + "\n");
            return;
        }
        if (password.length < 8 || password.length > 63) {
            error = "Password must be 8 to 63 characters";
            return;
        }
        error = "";
        run(["sh", "-c", newScript, "sh", prompt], prompt, "new", password + "\n");
    }

    function finish(code) {
        const name = connecting;
        const kind = jobKind;
        const msg = jobErr.trim();
        const n = networks.find(x => x.ssid === name);
        connecting = "";
        jobInput = "";
        if (code === 0) {
            prompt = "";
            error = "";
            ShellState.reclaimFocus();
        } else if (kind === "saved" && n && n.secure && /secret|password|auth/i.test(msg)) {
            error = "Saved password was rejected";
            askFor(name, n.eap);
        } else if (kind === "new" || kind === "eap") {
            error = /secret|password|auth|handshake/i.test(msg) ? "Wrong password" : msg.replace(/^Error: /, "");
        } else {
            error = msg.replace(/^Error: /, "");
        }
        refresh(true);
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
            const sec = f[3] || "";
            const entry = { ssid: name, signal: parseInt(f[2]) || 0, secure: sec.length > 0 && sec !== "--", eap: sec.includes("802.1X"), active: f[0] === "*" };
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

    function parseDevs(text) {
        devUp = text.split("\n").some(l => {
            const f = split(l);
            return f[0] === "wifi" && /^(connected|connecting|disconnected)/.test(f[1] || "");
        });
    }

    function parseSaved(text) {
        const map = {};
        text.split("\n").forEach(l => {
            const f = l.split("\t");
            if (f.length < 4)
                return;
            map[f.slice(3).join("\t").replace(/\\(.)/g, "$1")] = { uuid: f[0], flags: f[1], keyMgmt: f[2] };
        });
        saved = map;
    }

    function parseConns(text) {
        vpns = text.split("\n").filter(l => l.length > 0).map(l => split(l)).filter(f => f[1] === "vpn" || f[1] === "wireguard").map(f => ({ name: f[0], active: (f[2] || "").length > 0 }));
    }

    function setVpn(name, on) {
        Quickshell.execDetached(["nmcli", "connection", on ? "up" : "down", "id", name]);
        pending.restart();
    }

    onPromptChanged: setHold(prompt !== "")

    Component.onCompleted: refresh(true)

    readonly property Connections closer: Connections {
        target: ShellState

        function onPanelsOpenChanged(): void {
            if (!ShellState.panelsOpen)
                root.cancelPrompt();
        }
    }

    readonly property Timer pending: Timer {
        interval: 2500
        onTriggered: {
            root.pendingWifi = null;
            root.refresh(false);
        }
    }

    readonly property Timer pulse: Timer {
        interval: 120
        onTriggered: root.refresh(true)
    }

    readonly property Timer poll: Timer {
        interval: 5000
        repeat: true
        running: root.open
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    readonly property Timer scan: Timer {
        interval: 20000
        repeat: true
        running: root.open && root.wifiEnabled
        triggeredOnStart: true
        onTriggered: Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"])
    }

    readonly property Timer respawn: Timer {
        interval: 3000
        onTriggered: root.monitor.running = true
    }

    readonly property Timer jobDone: Timer {
        property int code: 0

        interval: 60
        onTriggered: root.finish(code)
    }

    readonly property Process monitor: Process {
        command: ["nmcli", "monitor"]
        running: true
        environment: root.env
        stdout: SplitParser {
            onRead: root.pulse.restart()
        }
        onExited: root.respawn.start()
    }

    readonly property Process job: Process {
        stdinEnabled: true
        environment: root.env
        stderr: StdioCollector {
            onStreamFinished: root.jobErr = text
        }
        onStarted: {
            if (root.jobInput.length > 0)
                write(root.jobInput);
        }
        onExited: code => {
            root.jobDone.code = code;
            root.jobDone.restart();
        }
    }

    readonly property Process radio: Process {
        command: ["nmcli", "radio", "wifi"]
        environment: root.env
        stdout: StdioCollector {
            onStreamFinished: root.radioOn = text.trim() === "enabled"
        }
    }

    readonly property Process devs: Process {
        command: ["nmcli", "-t", "-f", "TYPE,STATE", "device", "status"]
        environment: root.env
        stdout: StdioCollector {
            onStreamFinished: root.parseDevs(text)
        }
    }

    readonly property Process wifi: Process {
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]
        environment: root.env
        stdout: StdioCollector {
            onStreamFinished: root.parseWifi(text)
        }
    }

    readonly property Process conns: Process {
        command: ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show"]
        environment: root.env
        stdout: StdioCollector {
            onStreamFinished: root.parseConns(text)
        }
    }

    readonly property Process savedProc: Process {
        command: ["sh", "-c", root.savedScript]
        environment: root.env
        stdout: StdioCollector {
            onStreamFinished: root.parseSaved(text)
        }
    }
}
