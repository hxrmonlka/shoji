import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
    id: root

    property bool viz: false
    property real vizMargin: 20
    readonly property bool hasArt: Media.artUrl !== ""
    readonly property string artUrl: Media.artUrl
    property int front: 0
    property int pending: -1
    property bool fading: false

    function slotAt(i) {
        return i === 0 ? slotA : slotB;
    }

    function begin() {
        xf.value = 0;
        xf.velocity = 0;
        fading = true;
        xf.kick();
    }

    function show(url) {
        if (url === "")
            return;
        if (fading) {
            front = pending;
            fading = false;
        }
        pending = -1;
        const cur = slotAt(front);
        if (cur.url === url)
            return;
        if (cur.url === "") {
            cur.url = url;
            return;
        }
        const back = 1 - front;
        const target = slotAt(back);
        const same = target.url === url;
        pending = back;
        target.url = url;
        if (same && target.ready)
            begin();
    }

    onArtUrlChanged: show(artUrl)
    Component.onCompleted: show(artUrl)

    Rectangle {
        anchors.fill: parent
        color: Theme.m3SurfaceContainer
    }

    Spring {
        id: xf

        target: 1
        token: Motion.effectsSlow
        epsilon: 0.002
        onRunningChanged: {
            if (running || !root.fading)
                return;
            root.front = root.pending;
            root.fading = false;
            root.pending = -1;
        }
    }

    Spring {
        id: artFade

        target: root.hasArt ? 1 : 0
        token: Motion.effectsDefault
    }

    component Slot: Item {
        id: slot

        property string url: ""
        readonly property bool ready: img.status === Image.Ready

        signal loaded

        anchors.fill: parent
        visible: opacity > 0.001

        Image {
            id: img

            anchors.fill: parent
            source: slot.url
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(240, 240)
            asynchronous: true
            visible: false
            onStatusChanged: {
                if (status === Image.Ready)
                    slot.loaded();
            }
        }

        MultiEffect {
            anchors.fill: parent
            source: img
            visible: slot.ready
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            brightness: -0.2
            saturation: 0.2
        }
    }

    Item {
        anchors.fill: parent
        opacity: artFade.value

        Slot {
            id: slotA

            z: root.front === 0 ? 0 : 1
            opacity: root.front === 0 ? 1 : (root.fading ? xf.value : 0)
            onLoaded: {
                if (root.pending === 0 && !root.fading)
                    root.begin();
            }
        }

        Slot {
            id: slotB

            z: root.front === 1 ? 0 : 1
            opacity: root.front === 1 ? 1 : (root.fading ? xf.value : 0)
            onLoaded: {
                if (root.pending === 1 && !root.fading)
                    root.begin();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4 * artFade.value)
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.vizMargin
        anchors.rightMargin: root.vizMargin
        height: 70
        spacing: 4
        visible: root.viz
        opacity: 0.75 * vizFade.value

        Spring {
            id: vizFade

            target: Media.playing ? 1 : 0
            token: Motion.effectsDefault
        }

        Repeater {
            model: Cava.bars

            Rectangle {
                required property int index

                width: (parent.width - (Cava.bars - 1) * 4) / Cava.bars
                height: Math.max(4, (Cava.values[index] ?? 0) * 92)
                anchors.bottom: parent.bottom
                topLeftRadius: width / 2
                topRightRadius: width / 2
                bottomLeftRadius: 0
                bottomRightRadius: 0
                color: Theme.m3Primary
            }
        }
    }
}
