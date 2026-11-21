import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
    id: root

    property bool tabHost: false
    readonly property bool hasArt: Media.artUrl !== ""
    readonly property bool multiple: Media.multiple
    readonly property real travel: 90
    readonly property real fade: 1 - Math.min(1, Math.abs(shift) / travel)
    property real shift: 0
    property bool settling: false
    property real lastVelocity: 0
    property real dragBase: 0

    function band(dx) {
        const dir = dx < 0 ? 1 : -1;
        if (Media.canStep(dir))
            return Math.max(-travel, Math.min(travel, dx));
        const pull = 1 - 1 / (Math.abs(dx) * 0.55 / travel + 1);
        return (dx < 0 ? -1 : 1) * pull * travel;
    }

    function settleFrom(value, velocity) {
        settling = true;
        settle.value = value;
        settle.velocity = velocity;
        settle.kick();
    }

    function enter(dir) {
        settleFrom(dir * travel, 0);
    }

    Connections {
        target: Media

        function onStepped(dir) {
            root.enter(dir);
        }

        function onBumped(dir) {
            if (!out.running && !swipe.active)
                root.settleFrom(-dir * 12, 0);
        }
    }

    Spring {
        id: settle

        target: 0
        token: Motion.spatialDefault
        epsilon: 0.05
        onValueChanged: {
            if (root.settling)
                root.shift = value;
        }
        onRunningChanged: {
            if (!running)
                root.settling = false;
        }
    }

    SequentialAnimation {
        id: out

        property int dir: 0

        NumberAnimation {
            target: root
            property: "shift"
            to: -out.dir * root.travel
            duration: 100
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.7, 0, 0.84, 0, 1, 1]
        }

        ScriptAction {
            script: {
                if (!Media.step(out.dir))
                    root.settleFrom(root.shift, 0);
            }
        }
    }

    MediaBackdrop {
        anchors.fill: parent
        visible: !root.tabHost
        viz: true
    }

    component NavChevron: Item {
        id: chevron

        property string glyph: ""
        property int dir: 1

        width: 24
        height: 24
        opacity: Media.canStep(dir) ? 1 : 0.3

        Text {
            anchors.centerIn: parent
            text: chevron.glyph
            color: Theme.m3OnSurface
            font.family: Theme.fontIcon
            font.pixelSize: 12
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Media.step(chevron.dir)
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !Media.available
        text: "Nothing playing"
        color: Theme.m3OnSurfaceVariant
        font.family: Theme.fontUi
        font.pixelSize: 16
    }

    Item {
        id: swipeZone

        width: parent.width
        height: 164
        enabled: root.multiple

        DragHandler {
            id: swipe

            target: null
            acceptedButtons: Qt.LeftButton
            enabled: root.multiple && !out.running
            onCentroidChanged: root.lastVelocity = centroid.velocity.x
            onActiveChanged: {
                if (active) {
                    root.settling = false;
                    root.dragBase = root.shift;
                    return;
                }
                const dir = root.shift < 0 ? 1 : -1;
                const flick = Math.abs(root.lastVelocity) > 700 && root.lastVelocity * root.shift > 0;
                if (Media.canStep(dir) && (Math.abs(root.shift) > 48 || (flick && Math.abs(root.shift) > 12))) {
                    out.dir = dir;
                    out.restart();
                } else {
                    root.settleFrom(root.shift, 0);
                }
            }
            onActiveTranslationChanged: {
                if (active)
                    root.shift = root.band(root.dragBase + activeTranslation.x);
            }
        }
    }

    Item {
        anchors.fill: parent
        visible: Media.available

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            height: 24
            visible: root.multiple

            NavChevron {
                glyph: "\uf053"
                dir: -1
            }

            Repeater {
                model: Media.deck.length

                Item {
                    id: dotItem

                    required property int index

                    width: 14
                    height: 24

                    Rectangle {
                        anchors.centerIn: parent
                        width: 6 + 10 * dotSpring.value
                        height: 6
                        radius: 3
                        color: dotItem.index === Media.deckIndex ? Theme.m3Primary : Qt.rgba(1, 1, 1, 0.35)
                    }

                    Spring {
                        id: dotSpring

                        target: dotItem.index === Media.deckIndex ? 1 : 0
                        token: Motion.spatialFast
                        epsilon: 0.001
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Media.select(dotItem.index)
                    }
                }
            }

            NavChevron {
                glyph: "\uf054"
                dir: 1
            }
        }

        RoundedImage {
            id: thumb

            x: 24 + root.shift
            y: 24
            width: 132
            height: 132
            radius: 20
            opacity: root.fade
            source: Media.artUrl
            sourceSize: Qt.size(264, 264)
            visible: root.hasArt
        }

        Rectangle {
            x: 24 + root.shift
            y: 24
            width: 132
            height: 132
            radius: 20
            opacity: root.fade
            color: Theme.m3SurfaceContainerHighest
            visible: !root.hasArt

            Text {
                anchors.centerIn: parent
                text: "\uf001"
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontIcon
                font.pixelSize: 44
            }
        }

        Column {
            anchors.left: thumb.right
            anchors.leftMargin: 20 - root.shift * 0.35
            anchors.right: parent.right
            anchors.rightMargin: 24
            y: 30
            spacing: 4
            opacity: root.fade

            Text {
                width: parent.width
                text: Media.title
                elide: Text.ElideRight
                color: Theme.m3OnSurface
                font.family: Theme.fontUi
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                text: Media.artist
                visible: text.length > 0
                elide: Text.ElideRight
                color: Theme.m3OnSurface
                opacity: 0.8
                font.family: Theme.fontUi
                font.pixelSize: 16
            }

            Text {
                width: parent.width
                text: Media.source
                elide: Text.ElideRight
                color: Theme.m3OnSurfaceVariant
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
        }

        Item {
            id: timeline

            x: 24
            y: 172
            width: parent.width - 48
            height: 34

            Rectangle {
                id: track

                anchors.left: parent.left
                anchors.right: parent.right
                y: 4
                height: 6
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.2)

                Rectangle {
                    width: parent.width * seekFill.value
                    height: parent.height
                    radius: 3
                    color: Theme.m3Primary
                }

                Spring {
                    id: seekFill

                    target: Media.progress
                    token: Motion.effectsDefault
                    epsilon: 0.0005
                }
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                text: Media.format(Media.position)
                color: Theme.m3OnSurface
                opacity: 0.75
                font.family: Theme.fontUi
                font.pixelSize: 12
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: Media.length > 0 ? Media.format(Media.length) : ""
                color: Theme.m3OnSurface
                opacity: 0.75
                font.family: Theme.fontUi
                font.pixelSize: 12
            }

            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -6
                anchors.bottomMargin: 10
                enabled: Media.canSeek
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: mouse => Media.seekTo(mouse.x / width)
                onPositionChanged: mouse => Media.seekTo(mouse.x / width)
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 222
            spacing: 14

            Repeater {
                model: [
                    { glyph: "\uf048", action: "previous", size: 46 },
                    { glyph: Media.playing ? "\uf04c" : "\uf04b", action: "toggle", size: 56 },
                    { glyph: "\uf051", action: "next", size: 46 }
                ]

                Rectangle {
                    id: btn

                    required property var modelData

                    width: modelData.size
                    height: modelData.size
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: btnFill.color
                    scale: press.value

                    ColorSpring {
                        id: btnFill

                        target: btn.modelData.action === "toggle" ? (btnArea.containsMouse ? Theme.m3OnPrimaryContainer : Theme.m3Primary) : (btnArea.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent")
                    }

                    Spring {
                        id: press

                        target: btnArea.pressed ? 0.92 : 1
                        token: Motion.spatialFast
                        epsilon: 0.0005
                    }

                    Text {
                        anchors.centerIn: parent
                        text: btn.modelData.glyph
                        color: btn.modelData.action === "toggle" ? Theme.m3OnPrimary : Theme.m3OnSurface
                        font.family: Theme.fontIcon
                        font.pixelSize: btn.modelData.action === "toggle" ? 20 : 16
                    }

                    Ripple {
                        id: ripple1

                        anchors.fill: parent
                        radius: parent.radius
                    }

                    MouseArea {
                        id: btnArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => ripple1.press(btnArea, mouse)
                        onClicked: {
                            if (btn.modelData.action === "toggle")
                                Media.player.togglePlaying();
                            else if (btn.modelData.action === "next")
                                Media.player.next();
                            else
                                Media.player.previous();
                        }
                    }
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 24
            y: 237
            spacing: 10
            opacity: Media.volumeMode === "none" ? 0.4 : 1

            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: muteFill.color
                anchors.verticalCenter: parent.verticalCenter

                ColorSpring {
                    id: muteFill

                    target: muteArea.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: Media.muted || Media.volume <= 0.001 ? "\uf026" : Media.volume < 0.5 ? "\uf027" : "\uf028"
                    color: Theme.m3OnSurface
                    font.family: Theme.fontIcon
                    font.pixelSize: 14
                }

                Ripple {
                    id: ripple2

                    anchors.fill: parent
                    radius: parent.radius
                }

                MouseArea {
                    id: muteArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => ripple2.press(muteArea, mouse)
                    onClicked: Media.toggleMute()
                }
            }

            Item {
                width: 120
                height: 28
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.2)

                    Rectangle {
                        width: parent.width * volFill.value
                        height: parent.height
                        radius: 3
                        color: Theme.m3Primary
                    }

                    Spring {
                        id: volFill

                        target: Media.muted ? 0 : Media.volume
                        token: Motion.effectsDefault
                        epsilon: 0.0005
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: Media.volumeMode !== "none"
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: mouse => Media.setVolume(mouse.x / width)
                    onPositionChanged: mouse => Media.setVolume(mouse.x / width)
                }
            }
        }
    }
}
