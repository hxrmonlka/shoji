import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
    id: root

    property bool viz: false
    property real vizMargin: 20
    readonly property bool hasArt: Media.artUrl !== ""

    Rectangle {
        anchors.fill: parent
        color: Theme.m3SurfaceContainer
    }

    Image {
        id: art

        anchors.fill: parent
        source: Media.artUrl
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(240, 240)
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: art
        visible: root.hasArt && art.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        brightness: -0.2
        saturation: 0.2
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.hasArt ? 0.4 : 0)
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.vizMargin
        anchors.rightMargin: root.vizMargin
        height: 80
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
                height: Math.max(4, (Cava.values[index] ?? 0) * 80)
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
