import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

Item {
    id: root

    property int kind: 0
    property real size: 96
    property int index: 0
    readonly property var candidates: [Profile.iconFile, Profile.faceFile].filter(s => s.length > 0)
    readonly property string current: index < candidates.length ? candidates[index] : ""
    readonly property bool ready: img.status === Image.Ready

    width: size
    height: size

    onCandidatesChanged: index = 0

    component Silhouette: Item {
        id: sil

        property color fill: "black"

        anchors.fill: parent

        Item {
            width: 100
            height: 100
            scale: root.size / 100
            transformOrigin: Item.TopLeft

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: "transparent"
                    fillColor: sil.fill

                    PathSvg {
                        path: MaterialShapes.build(root.kind)
                    }
                }
            }
        }
    }

    Silhouette {
        fill: Theme.m3PrimaryContainer
        opacity: root.ready ? 0 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !root.ready
        text: "\uf007"
        font.family: Theme.fontIcon
        font.pixelSize: root.size * 0.38
        color: Theme.m3OnPrimaryContainer
    }

    Image {
        id: img

        anchors.fill: parent
        visible: false
        asynchronous: true
        cache: false
        smooth: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        source: root.current ? "file://" + root.current : ""
        onStatusChanged: {
            if (status === Image.Error && root.index < root.candidates.length)
                root.index++;
        }
    }

    Silhouette {
        id: mask

        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        opacity: root.ready ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }
}
