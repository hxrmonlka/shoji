pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

QtObject {
    id: root

    property string password: ""
    property string user: ""
    property bool secret: false
    property string prompt: "Username"
    property bool busy: false
    property bool failed: false
    property string message: ""
    property int frameShape: 0
    property var sessions: []
    property var users: []
    property int highlighted: 0
    property bool usersLoaded: false
    property var session: null
    property string wantedSession: ""
    property string lastUser: ""
    property bool stateLoaded: false
    property bool sessionsLoaded: false
    property bool started: false

    readonly property bool picking: user === "" && users.length > 1
    readonly property string avatar: {
        const u = users.find(x => x.name === user);
        return u ? u.icon : "";
    }
    readonly property string statePath: Quickshell.env("SHOJI_GREETER_STATE") || (Quickshell.env("HOME") + "/.local/state/shoji/greeter.json")
    readonly property ListModel shapes: ListModel {}

    function syncShapes(): void {
        const n = secret ? password.length : 0;
        while (shapes.count > n)
            shapes.remove(shapes.count - 1);
        while (shapes.count < n)
            shapes.append({ shape: Math.floor(Math.random() * 7) });
    }

    function moveUser(step: int): void {
        if (users.length === 0)
            return;
        highlighted = (highlighted + step + users.length) % users.length;
    }

    function begin(name: string): void {
        user = name;
        password = "";
        busy = true;
        Greetd.createSession(name);
    }

    function reset(): void {
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        user = "";
        password = "";
        secret = false;
        prompt = "Username";
        busy = false;
        failed = false;
        message = "";
        if (users.length === 1 && Greetd.available)
            begin(users[0].name);
    }

    function submit(): void {
        if (busy)
            return;
        if (picking) {
            begin(users[highlighted].name);
            return;
        }
        if (password.length === 0)
            return;
        if (user === "") {
            const name = password.trim();
            password = "";
            if (name.length > 0)
                begin(name);
            return;
        }
        const answer = password;
        busy = true;
        failed = false;
        password = "";
        Greetd.respond(answer);
    }

    function pick(): void {
        if (sessions.length === 0) {
            session = null;
            return;
        }
        session = sessions.find(s => s.name === wantedSession) ?? sessions.find(s => /mango/i.test(s.exec)) ?? sessions[0];
    }

    function maybeStart(): void {
        if (started || !stateLoaded || !sessionsLoaded || !usersLoaded)
            return;
        started = true;
        pick();
        const last = users.findIndex(u => u.name === lastUser);
        if (last >= 0)
            highlighted = last;
        if (!Greetd.available)
            return;
        if (users.length === 1)
            begin(users[0].name);
        else if (users.length === 0 && lastUser.length > 0)
            begin(lastUser);
    }

    function save(): void {
        stateFile.setText(JSON.stringify({ user: user, session: session ? session.name : "" }));
    }

    function sessionCommand(): var {
        const log = Quickshell.env("SHOJI_GREETER_SESSION_LOG");
        return [log ? session.exec + " >>'" + log + "' 2>&1" : session.exec];
    }

    function launchSession(): void {
        if (!session) {
            failed = true;
            message = "No session available";
            reset();
            return;
        }
        save();
        Greetd.launch(sessionCommand(), ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=" + session.id, "XDG_SESSION_DESKTOP=" + session.id]);
    }

    onPasswordChanged: {
        syncShapes();
        if (password.length > 0 && failed) {
            failed = false;
            message = "";
        }
    }

    onSecretChanged: syncShapes()

    Component.onCompleted: {
        const pool = MaterialShapes.frameKinds;
        frameShape = pool[Math.floor(Math.random() * pool.length)];
        Quickshell.execDetached(["mkdir", "-p", statePath.substring(0, statePath.lastIndexOf("/"))]);
    }

    readonly property Connections greetd: Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (error) {
                root.failed = true;
                root.message = message;
                return;
            }
            if (!responseRequired)
                return;
            root.secret = !echoResponse;
            root.prompt = message.replace(/:\s*$/, "").trim() || "Password";
            root.busy = false;
        }

        function onAuthFailure(message: string): void {
            root.failed = true;
            root.message = "Incorrect password";
            root.password = "";
            if (root.user !== "") {
                root.busy = true;
                Greetd.createSession(root.user);
            } else {
                root.busy = false;
            }
        }

        function onReadyToLaunch(): void {
            root.launchSession();
        }

        function onError(error: string): void {
            root.busy = false;
            root.failed = true;
            root.message = "Login service error";
        }
    }

    readonly property FileView stateFile: FileView {
        path: root.statePath
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root.wantedSession = j.session || "";
                root.lastUser = j.user || "";
            } catch (e) {
            }
            root.stateLoaded = true;
            root.maybeStart();
        }
        onLoadFailed: {
            root.stateLoaded = true;
            root.maybeStart();
        }
    }

    readonly property Process finder: Process {
        command: ["sh", Quickshell.shellPath("scripts/greeter-sessions.sh")]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const p = line.split("\t");
                if (p.length >= 3)
                    root.sessions = root.sessions.concat([{ name: p[0], exec: p[1], id: p[2] }]);
            }
        }
        onExited: {
            root.sessionsLoaded = true;
            root.maybeStart();
        }
    }

    readonly property Process userFinder: Process {
        command: ["sh", Quickshell.shellPath("scripts/greeter-users.sh")]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const p = line.split("\t");
                if (p[0].length > 0)
                    root.users = root.users.concat([{ name: p[0], real: p[1] || p[0], icon: p[2] || "" }]);
            }
        }
        onExited: {
            root.usersLoaded = true;
            root.maybeStart();
        }
    }
}
