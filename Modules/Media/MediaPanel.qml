import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
    id: root

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
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 80
        spacing: 4
        opacity: 0.45 * vizFade.value

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

    Text {
        anchors.centerIn: parent
        visible: !Media.available
        text: "Nothing playing"
        color: Theme.m3OnSurfaceVariant
        font.family: Theme.fontUi
        font.pixelSize: 16
    }

    Item {
        anchors.fill: parent
        visible: Media.available

        RoundedImage {
            id: thumb

            x: 24
            y: 24
            width: 132
            height: 132
            radius: 20
            source: Media.artUrl
            sourceSize: Qt.size(264, 264)
            visible: root.hasArt
        }

        Rectangle {
            x: 24
            y: 24
            width: 132
            height: 132
            radius: 20
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
            anchors.leftMargin: 20
            anchors.right: parent.right
            anchors.rightMargin: 24
            y: 30
            spacing: 4

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
