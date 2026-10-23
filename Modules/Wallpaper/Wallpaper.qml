import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: win

    property bool aFront: true
    readonly property string wanted: Wallpapers.current
    readonly property Image base: aFront ? imgA : imgB
    readonly property Image incoming: aFront ? imgB : imgA

    function url(path) {
        return path ? "file://" + path : "";
    }

    function begin() {
        if (incoming.status === Image.Ready && incoming.source.toString() !== "")
            fade.target = 1;
    }

    function finish() {
        const old = base;
        aFront = !aFront;
        fade.target = 0;
        fade.value = 0;
        old.source = "";
    }

    onWantedChanged: {
        const next = url(wanted);
        if (next === base.source.toString() || next === incoming.source.toString())
            return;
        if (base.source.toString() === "") {
            base.source = next;
            return;
        }
        fade.target = 0;
        fade.value = 0;
        incoming.source = next;
    }

    Component.onCompleted: base.source = url(wanted)

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: Theme.m3Surface

    WlrLayershell.namespace: "shoji-wallpaper"
    WlrLayershell.layer: WlrLayer.Background

    Image {
        id: imgA

        anchors.fill: parent
        z: win.aFront ? 0 : 1
        opacity: win.aFront ? 1 : fade.value
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        sourceSize: Qt.size(Math.max(win.width, win.height), Math.max(win.width, win.height))
        onStatusChanged: win.begin()
    }

    Image {
        id: imgB

        anchors.fill: parent
        z: win.aFront ? 1 : 0
        opacity: win.aFront ? fade.value : 1
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        sourceSize: Qt.size(Math.max(win.width, win.height), Math.max(win.width, win.height))
        onStatusChanged: win.begin()
    }

    Spring {
        id: fade

        target: 0
        token: Motion.effectsSlow
        epsilon: 0.002
        onValueChanged: if (target === 1 && value >= 0.999) win.finish()
    }
}
