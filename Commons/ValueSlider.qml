import QtQuick
import qs.Commons

Item {
    id: root

    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0
    property string label: ""
    property bool showValue: false
    property string valueText: Math.round(fraction * 100) + "%"
    readonly property bool labeled: label.length > 0 || showValue
    readonly property real trackHeight: labeled ? 28 : 12
    readonly property bool pressed: area.pressed
    readonly property real shown: pressed ? pending : value
    readonly property real fraction: to > from ? Motion.clamp01((shown - from) / (to - from)) : 0

    property real pending: value

    signal moved(real v)
    signal committed(real v)

    implicitHeight: 28
    implicitWidth: 160
    opacity: enabled ? 1 : 0.4

    function snap(x) {
        let v = from + Motion.clamp01(x / width) * (to - from);
        if (step > 0)
            v = Math.round((v - from) / step) * step + from;
        return Math.max(from, Math.min(to, v));
    }

    Spring {
        id: fill

        target: root.fraction
        token: root.pressed ? Motion.effectsFast : Motion.effectsDefault
        epsilon: 0.0005
    }

    component Captions: Item {
        id: caps

        property color tint: Theme.m3OnSurface
        property string label: ""
        property string valueText: ""
        property bool showValue: false

        visible: label.length > 0 || showValue

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: valueLabel.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: caps.label
            elide: Text.ElideRight
            color: caps.tint
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        Text {
            id: valueLabel

            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            visible: caps.showValue
            text: caps.showValue ? caps.valueText : ""
            color: caps.tint
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackHeight
        radius: height / 2
        color: Theme.m3SurfaceContainerHighest

        Captions {
            anchors.fill: parent
            tint: Theme.m3OnSurface
            label: root.label
            valueText: root.valueText
            showValue: root.showValue
        }

        Rectangle {
            width: Math.min(parent.width, Math.max(parent.height, parent.width * fill.value))
            height: parent.height
            radius: parent.radius
            color: Theme.m3Primary
            clip: true

            Captions {
                width: track.width
                height: track.height
                tint: Theme.m3OnPrimary
                label: root.label
                valueText: root.valueText
                showValue: root.showValue
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => {
            root.pending = root.snap(mouse.x);
            root.moved(root.pending);
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const v = root.snap(mouse.x);
            if (v !== root.pending) {
                root.pending = v;
                root.moved(v);
            }
        }
        onReleased: root.committed(root.pending)
    }
}
